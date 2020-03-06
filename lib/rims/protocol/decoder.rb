# -*- coding: utf-8 -*-

require 'logger'
require 'net/imap'
require 'pp'
require 'time'

module RIMS
  module Protocol
    class Decoder
      # to use `StringIO' as mock in unit test
      using Riser::CompatibleStringIO

      def self.new_decoder(*args, **opts)
        InitialDecoder.new(*args, **opts)
      end

      IMAP_CMDs = {}
      UID_CMDs = {}

      def self.imap_command_normalize(name)
        name.upcase
      end

      def self.logging_error_chain(error, logger)
        Error.trace_error_chain(error) do |exception|
          if (logger.debug?) then
            Error.optional_data(exception) do |error, data|
              logger.debug("error message: #{error.message} (#{error.class})")
              for name, value in data
                logger.debug("error data [#{name}]: #{value.pretty_inspect}")
              end
            end
          end
          logger.error(exception)
        end
      end

      def self.repl(decoder, limits, input, output, logger)
        output_write = lambda{|data|
          begin
            if (data == :flush) then
              output.flush
            else
              logger.debug("response data: #{Protocol.io_data_log(data)}") if logger.debug?
              output << data
            end
          rescue
            logger.error('response write error.')
            logging_error_chain($!, logger)
            raise
          end
        }
        server_output_write = lambda{|res|
          for data in res
            output_write.call(data)
          end
          output.flush

          nil
        }
        response_write = lambda{|response|
          output_write.call(response)
          output.flush
          logger.info("server response: #{response.strip}")
        }
        apply_imap_command = lambda{|name, *args, uid: false|
          last_line = nil
          if (uid) then
            decoder.__send__(name, *args, uid: true) {|response|
              output_write.call(response)
              last_line = response if (response.is_a? String)
            }
          else
            decoder.__send__(name, *args) {|response|
              output_write.call(response)
              last_line = response if (response.is_a? String)
            }
          end
          output.flush
          logger.info("server response: #{last_line.strip}") if last_line
        }

        apply_imap_command.call(:ok_greeting)

        conn_timer = ConnectionTimer.new(limits, input.to_io)
        request_reader = decoder.make_requrest_reader(input, output)
        input_gets = request_reader.method(:gets)

        begin
          until (conn_timer.command_wait_timeout?)
            conn_timer.command_wait or break

            begin
              atom_list = request_reader.read_command
            rescue LineTooLongError
              raise
            rescue LiteralSizeTooLargeError
              logger.error('literal size too large error.')
              logging_error_chain($!, logger)
              response_write.call("#{request_reader.command_tag || '*'} BAD literal size too large\r\n")
              next
            rescue
              logger.error('invalid client command.')
              logging_error_chain($!, logger)
              response_write.call("#{request_reader.command_tag || '*'} BAD client command syntax error\r\n")
              next
            end

            break unless atom_list

            tag, command, *opt_args = atom_list
            normalized_command = imap_command_normalize(command)
            logger.info("client command: #{tag} #{command}")
            if (logger.debug?) then
              case (normalized_command)
              when 'LOGIN'
                log_opt_args = opt_args.dup
                log_opt_args[-1] = '********'
              when 'AUTHENTICATE'
                if (opt_args[1]) then
                  log_opt_args = opt_args.dup
                  log_opt_args[1] = '********'
                else
                  log_opt_args = opt_args
                end
              else
                log_opt_args = opt_args
              end
              logger.debug("client command parameter: #{log_opt_args.inspect}")
            end

            begin
              if (name = IMAP_CMDs[normalized_command]) then
                case (name)
                when :uid
                  unless (opt_args.empty?) then
                    uid_command, *uid_args = opt_args
                    logger.info("uid command: #{uid_command}")
                    logger.debug("uid parameter: #{uid_args}") if logger.debug?
                    if (uid_name = UID_CMDs[imap_command_normalize(uid_command)]) then
                      apply_imap_command.call(uid_name, tag, *uid_args, uid: true)
                    else
                      logger.error("unknown uid command: #{uid_command}")
                      response_write.call("#{tag} BAD unknown uid command\r\n")
                    end
                  else
                    logger.error('empty uid parameter.')
                    response_write.call("#{tag} BAD empty uid parameter\r\n")
                  end
                when :authenticate
                  apply_imap_command.call(:authenticate, tag, input_gets, server_output_write, *opt_args)
                when :idle
                  apply_imap_command.call(:idle, tag, input_gets, server_output_write, conn_timer, *opt_args)
                else
                  apply_imap_command.call(name, tag, *opt_args)
                end
              else
                logger.error("unknown command: #{command}")
                response_write.call("#{tag} BAD unknown command\r\n")
              end
            rescue LineTooLongError
              raise
            rescue
              logger.error('unexpected error.')
              logging_error_chain($!, logger)
              response_write.call("#{tag} BAD unexpected error\r\n")
            end

            if (normalized_command == 'LOGOUT') then
              break
            end

            decoder = decoder.next_decoder
          end
        rescue LineTooLongError
          logger.error('line too long error.')
          logging_error_chain($!, logger)
          response_write.call("* BAD line too long\r\n")
          response_write.call("* BYE server autologout: connection terminated\r\n")
        else
          if (conn_timer.command_wait_timeout?) then
            if (limits.command_wait_timeout_seconds > 0) then
              response_write.call("* BYE server autologout: idle for too long\r\n")
            else
              response_write.call("* BYE server autologout: shutdown\r\n")
            end
          end
        end

        nil
      ensure
        # don't forget to clean up if the next decoder has been generated
        decoder.next_decoder.cleanup
      end

      def initialize(auth, logger)
        @auth = auth
        @logger = logger
        @next_decoder = self
      end

      attr_reader :next_decoder

      def logging_error_chain(error)
        self.class.logging_error_chain(error, @logger)
      end
      private :logging_error_chain

      def guard_error(imap_command, tag, *args, **kw_args, &block)
        begin
          if (kw_args.empty?) then
            __send__(imap_command, tag, *args, &block)
          else
            __send__(imap_command, tag, *args, **kw_args, &block)
          end
        rescue LineTooLongError
          raise
        rescue SyntaxError
          @logger.error('client command syntax error.')
          logging_error_chain($!)
          yield("#{tag} BAD client command syntax error\r\n")
        rescue ArgumentError
          @logger.error('invalid command parameter.')
          logging_error_chain($!)
          yield("#{tag} BAD invalid command parameter\r\n")
        rescue
          raise if ($!.class.name =~ /AssertionFailedError/)
          @logger.error('internal server error.')
          logging_error_chain($!)
          yield("#{tag} BAD internal server error\r\n")
        end
      end
      private :guard_error

      class << self
        def to_imap_command(name)
          imap_command_normalize(name.to_s)
        end
        private :to_imap_command

        def kw_params(method)
          params = method.parameters
          params.find_all{|arg_type, arg_name|
            case (arg_type)
            when :key, :keyreq
              true
            else
              false
            end
          }.map{|arg_type, arg_name|
            arg_name
          }
        end
        private :kw_params

        def should_be_imap_command(name)
          cmd = to_imap_command(name)
          unless (IMAP_CMDs.key? cmd) then
            raise ArgumentError, "not an IMAP command: #{name}"
          end

          method = instance_method(name)
          if (UID_CMDs.key? cmd) then
            unless (kw_params(method).include? :uid) then
              raise ArgumentError, "not defined `uid' keyword parameter: #{name}"
            end
          else
            if (kw_params(method).include? :uid) then
              raise ArgumentError, "not allowed `uid' keyword parameter: #{name}"
            end
          end

          nil
        end
        private :should_be_imap_command

        def imap_command(name)
          should_be_imap_command(name)
          orig_name = "_#{name}".to_sym
          alias_method orig_name, name
          define_method name, lambda{|tag, *args, **kw_args, &block|
            guard_error(orig_name, tag, *args, **kw_args, &block)
          }
          name.to_sym
        end
        private :imap_command

        def make_engine_and_recovery_if_needed(drb_services, username, logger: Logger.new(STDOUT))
          unique_user_id = Authentication.unique_user_id(username)
          logger.debug("unique user ID: #{username} -> #{unique_user_id}") if logger.debug?

          logger.info("open mail store: #{unique_user_id} [ #{username} ]")
          engine = drb_services[:engine, unique_user_id]

          begin
            engine.recovery_if_needed(username) {|response| yield(response) }
          rescue
            engine.destroy
            raise
          end

          engine
        end
      end

      def make_logout_response(tag)
        yield("* BYE server logout\r\n")
        yield("#{tag} OK LOGOUT completed\r\n")
      end
      private :make_logout_response

      def ok_greeting
        yield("* OK RIMS v#{VERSION} IMAP4rev1 service ready.\r\n")
      end

      # common IMAP command
      IMAP_CMDs['CAPABILITY'] = :capability

      def capability(tag)
        capability_list = %w[ IMAP4rev1 UIDPLUS IDLE ]
        capability_list += @auth.capability.map{|auth_capability| "AUTH=#{auth_capability}" }
        yield("* CAPABILITY #{capability_list.join(' ')}\r\n")
        yield("#{tag} OK CAPABILITY completed\r\n")
      end
      imap_command :capability
    end

    class InitialDecoder < Decoder
      class << self
        def imap_command(name)
          name = name.to_sym

          cmd = to_imap_command(name)
          Decoder::IMAP_CMDs[cmd] = name

          method = instance_method(name)
          if (kw_params(method).include? :uid) then
            Decoder::IMAP_CMDs['UID'] = :uid
            Decoder::UID_CMDs[cmd] = name
          end

          orig_name = "_#{name}".to_sym
          alias_method orig_name, name
          define_method name, lambda{|tag, *args, **kw_args, &block|
            guard_error(orig_name, tag, *args, **kw_args, &block)
          }

          name
        end
        private :imap_command
      end

      def initialize(drb_services, auth, logger,
                     mail_delivery_user: Service::DEFAULT_CONFIG.mail_delivery_user,
                     line_length_limit: Service::DEFAULT_CONFIG.protocol_line_length_limit,
                     literal_size_limit: (1024**2)*10)
        super(auth, logger)
        @drb_services = drb_services
        @mail_delivery_user = mail_delivery_user
        @line_length_limit = line_length_limit
        @literal_size_limit = literal_size_limit
        @logger.debug("RIMS::Protocol::InitialDecoder#initialize at #{self}") if @logger.debug?
      end

      def make_requrest_reader(input, output)
        RequestReader.new(input, output, @logger,
                          line_length_limit: @line_length_limit,
                          literal_size_limit: @literal_size_limit)
      end

      def auth?
        false
      end

      def selected?
        false
      end

      def cleanup
        @logger.debug("RIMS::Protocol::InitialDecoder#cleanup at #{self}") if @logger.debug?
        nil
      end

      def make_not_authenticated_response(tag)
        yield("#{tag} NO not authenticated\r\n")
      end
      private :make_not_authenticated_response

      def noop(tag)
        yield("#{tag} OK NOOP completed\r\n")
      end
      imap_command :noop

      def logout(tag, &block)
        @next_decoder = LogoutDecoder.new(self, @logger)
        make_logout_response(tag, &block)
      end
      imap_command :logout

      def accept_authentication(username)
        case (username)
        when @mail_delivery_user
          @logger.info("mail delivery user: #{username}")
          MailDeliveryDecoder.new(self, @drb_services, @auth, @logger)
        else
          engine = self.class.make_engine_and_recovery_if_needed(@drb_services, username, logger: @logger) {|untagged_response| yield(untagged_response) }
          UserMailboxDecoder.new(self, engine, @auth, @logger)
        end
      end
      private :accept_authentication

      def authenticate(tag, client_response_input_gets, server_challenge_output_write,
                       auth_type, inline_client_response_data_base64=nil)
        auth_reader = AuthenticationReader.new(@auth, client_response_input_gets, server_challenge_output_write, @logger)
        if (username = auth_reader.authenticate_client(auth_type, inline_client_response_data_base64)) then
          if (username != :*) then
            @logger.info("authentication OK: #{username}")
            @next_decoder = accept_authentication(username) {|untagged_response|
              yield(untagged_response)
              yield(:flush)
            }
            yield("#{tag} OK AUTHENTICATE #{auth_type} success\r\n")
          else
            @logger.info('bad authentication.')
            yield("#{tag} BAD AUTHENTICATE failed\r\n")
          end
        else
          yield("#{tag} NO authentication failed\r\n")
        end
      end
      imap_command :authenticate

      def login(tag, username, password)
        if (@auth.authenticate_login(username, password)) then
          @logger.info("login authentication OK: #{username}")
          @next_decoder = accept_authentication(username) {|untagged_response|
            yield(untagged_response)
            yield(:flush)
          }
          yield("#{tag} OK LOGIN completed\r\n")
        else
          yield("#{tag} NO failed to login\r\n")
        end
      end
      imap_command :login

      def select(tag, mbox_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :select

      def examine(tag, mbox_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :examine

      def create(tag, mbox_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :create

      def delete(tag, mbox_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :delete

      def rename(tag, src_name, dst_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :rename

      def subscribe(tag, mbox_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :status

      def append(tag, mbox_name, *opt_args, msg_text, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :append

      def check(tag, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :check

      def close(tag, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :close

      def expunge(tag, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :copy

      def idle(tag, client_input_gets, server_output_write, connection_timer, &block)
        make_not_authenticated_response(tag, &block)
      end
      imap_command :idle
    end

    class LogoutDecoder < Decoder
      def initialize(parent_decoder, logger)
        super(nil, logger)
        @parent_decoder = parent_decoder
        @logger.debug("RIMS::Protocol::LogoutDecoder#initialize at #{self}") if @logger.debug?
      end

      def auth?
        false
      end

      def selected?
        false
      end

      def cleanup
        @logger.debug("RIMS::Protocol::LogoutDecoder#cleanup at #{self}") if @logger.debug?
        unless (@parent_decoder.nil?) then
          @parent_decoder.cleanup
          @parent_decoder = nil
        end

        nil
      end

      def capability(tag)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :capability

      def noop(tag)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :noop

      def logout(tag)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :logout

      def authenticate(tag, client_response_input_gets, server_challenge_output_write,
                       auth_type, inline_client_response_data_base64=nil)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :authenticate

      def login(tag, username, password)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :login

      def select(tag, mbox_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :select

      def examine(tag, mbox_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :examine

      def create(tag, mbox_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :create

      def delete(tag, mbox_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :delete

      def rename(tag, src_name, dst_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :rename

      def subscribe(tag, mbox_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :status

      def append(tag, mbox_name, *opt_args, msg_text)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :append

      def check(tag)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :check

      def close(tag)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :close

      def expunge(tag)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :copy

      def idle(tag, client_input_gets, server_output_write, connection_timer)
        raise ProtocolError, 'invalid command in logout state.'
      end
      imap_command :idle
    end

    class AuthenticatedDecoder < Decoder
      def authenticate(tag, client_response_input_gets, server_challenge_output_write,
                       auth_type, inline_client_response_data_base64=nil, &block)
        yield("#{tag} NO duplicated authentication\r\n")
      end
      imap_command :authenticate

      def login(tag, username, password, &block)
        yield("#{tag} NO duplicated login\r\n")
      end
      imap_command :login
    end

    class UserMailboxDecoder < AuthenticatedDecoder
      class BulkResponse
        def initialize(limit_count, limit_size)
          @limit_count = limit_count
          @limit_size = limit_size
          @responses = []
          @size = 0
        end

        def count
          @responses.length
        end

        attr_reader :size

        def add(response)
          @responses << response
          @size += response.bytesize
          self
        end

        alias << add

        def empty?
          @responses.empty?
        end

        def full?
          count >= @limit_count || size >= @limit_size
        end

        def flush
          res = @responses
          if (count >= @limit_count) then
            res = [ res.join('') ]
          end

          @responses = []
          @size = 0

          res
        end
      end

      class Engine
        def initialize(unique_user_id, mail_store, logger,
                       bulk_response_count: 100,
                       bulk_response_size: 1024**2 * 10,
                       read_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                       write_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                       cleanup_write_lock_timeout_seconds: 1,
                       charset_aliases: RFC822::DEFAULT_CHARSET_ALIASES,
                       charset_convert_options: nil)
          @unique_user_id = unique_user_id
          @mail_store = mail_store
          @logger = logger
          @bulk_response_count = bulk_response_count
          @bulk_response_size = bulk_response_size
          @read_lock_timeout_seconds = read_lock_timeout_seconds
          @write_lock_timeout_seconds = write_lock_timeout_seconds
          @cleanup_write_lock_timeout_seconds = cleanup_write_lock_timeout_seconds
          @charset_aliases = charset_aliases
          @charset_convert_options = charset_convert_options
          @folders = {}
          @logger.debug("RIMS::Protocol::UserMailboxDecoder::Engine#initialize at #{self}") if @logger.debug?
        end

        attr_reader :unique_user_id
        attr_reader :mail_store # for test only

        def recovery_if_needed(username)
          @mail_store.write_synchronize(@write_lock_timeout_seconds) {
            if (@mail_store.abort_transaction?) then
              @logger.warn("user data recovery start: #{username}")
              yield("* OK [ALERT] start user data recovery.\r\n")
              @mail_store.recovery_data(logger: @logger).sync
              @logger.warn("user data recovery end: #{username}")
              yield("* OK completed user data recovery.\r\n")

              self
            end
          }
        end

        def open_folder(mbox_id, read_only: false)
          folder = @mail_store.open_folder(mbox_id, read_only: read_only)
          token = folder.object_id
          if (@folders.key? token) then
            raise "internal error: duplicated folder token: #{token}"
          end
          @folders[token] = folder

          @logger.debug("RIMS::Protocol::UserMailboxDecoder::Engine#open_folder: #{token}") if @logger.debug?
          token
        end
        private :open_folder

        def close_folder(token)
          @logger.debug("RIMS::Protocol::UserMailboxDecoder::Engine#close_folder: #{token}") if @logger.debug?
          folder = @folders.delete(token) or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.reload if folder.updated?
          begin
            if (block_given?) then
              saved_recent_msgs = @mail_store.mbox_flag_num(folder.mbox_id, 'recent')
              folder.close do |msg_num|
                yield("* #{msg_num} EXPUNGE\r\n")
              end
              last_recent_msgs = @mail_store.mbox_flag_num(folder.mbox_id, 'recent')
              if (last_recent_msgs != saved_recent_msgs) then
                yield("* #{last_recent_msgs} RECENT\r\n")
              end
            else
              folder.close
            end
          ensure
            folder.detach
          end
          @mail_store.sync

          nil
        end
        private :close_folder

        def cleanup(token)
          if (token) then
            begin
              @mail_store.write_synchronize(@cleanup_write_lock_timeout_seconds) {
                folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
                close_folder(token) do |untagged_response|
                  folder.server_response_multicast_push(untagged_response)
                end
              }
            rescue WriteLockTimeoutError
              @logger.warn("give up to close folder becaue of write-lock timeout over #{@write_lock_timeout_seconds} seconds")
              @folders.delete(token)
            end
          end

          nil
        end

        def destroy
          @logger.debug("RIMS::Protocol::UserMailboxDecoder::Engine#destroy at #{self}") if @logger.debug?
          tmp_mail_store = @mail_store
          ReadWriteLock.write_lock_timeout_detach(@cleanup_write_lock_timeout_seconds, @write_lock_timeout_seconds, logger: @logger) {|timeout_seconds|
            tmp_mail_store.write_synchronize(timeout_seconds) {
              @logger.info("close mail store: #{@unique_user_id}")
              tmp_mail_store.close
            }
          }
          @mail_store = nil

          nil
        end

        def guard_authenticated(imap_command, token, tag, *args, exclusive: false, **kw_args, &block)
          if (exclusive.nil?) then
            if (kw_args.empty?) then
              __send__(imap_command, token, tag, *args, &block)
            else
              __send__(imap_command, token, tag, *args, **kw_args, &block)
            end
          else
            begin
              if (exclusive) then
                @mail_store.write_synchronize(@write_lock_timeout_seconds) {
                  guard_authenticated(imap_command, token, tag, *args, exclusive: nil, **kw_args, &block)
                }
              else
                @mail_store.read_synchronize(@read_lock_timeout_seconds){
                  guard_authenticated(imap_command, token, tag, *args, exclusive: nil, **kw_args, &block)
                }
              end
            rescue ReadLockTimeoutError
              @logger.error("write-lock timeout over #{@write_lock_timeout_seconds} seconds")
              yield([ "#{tag} BAD write-lock timeout over #{@write_lock_timeout_seconds} seconds" ])
            rescue WriteLockTimeoutError
              @logger.error("read-lock timeout over #{@read_lock_timeout_seconds} seconds")
              yield([ "#{tag} BAD read-lock timeout over #{@read_lock_timeout_seconds} seconds" ])
            end
          end
        end
        private :guard_authenticated

        def guard_selected(imap_command, token, tag, *args, **kw_args, &block)
          if (token) then
            guard_authenticated(imap_command, token, tag, *args, **kw_args, &block)
          else
            yield([ "#{tag} NO not selected\r\n" ])
          end
        end
        private :guard_selected

        class << self
          def imap_command_authenticated(name, **guard_optional)
            name = name.to_sym
            orig_name = "_#{name}".to_sym
            alias_method orig_name, name

            guard_options_name = "_#{name}_guard_options".to_sym
            define_method guard_options_name, lambda{ guard_optional }
            private guard_options_name

            class_eval(<<-EOF, __FILE__, __LINE__ + 1)
              def #{name}(token, tag, *args, **kw_args, &block)
                guard_authenticated(:#{orig_name}, token, tag, *args, **kw_args, **#{guard_options_name}, &block)
              end
            EOF

            name
          end
          private :imap_command_authenticated

          def imap_command_selected(name, **guard_optional)
            name = name.to_sym
            orig_name = "_#{name}".to_sym
            alias_method orig_name, name

            guard_options_name = "_#{name}_guard_options".to_sym
            define_method guard_options_name, lambda{ guard_optional }
            private guard_options_name

            class_eval(<<-EOF, __FILE__, __LINE__ + 1)
              def #{name}(token, tag, *args, **kw_args, &block)
                guard_selected(:#{orig_name}, token, tag, *args, **kw_args, **#{guard_options_name}, &block)
              end
            EOF

            name
          end
          private :imap_command_selected
        end

        def new_bulk_response
          BulkResponse.new(@bulk_response_count, @bulk_response_size)
        end
        private :new_bulk_response

        def noop(token, tag)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            begin
              @mail_store.read_synchronize(@read_lock_timeout_seconds) {
                folder.server_response_fetch{|untagged_response|
                  res << untagged_response
                  yield(res.flush) if res.full?
                }
              }
            rescue ReadLockTimeoutError
              @logger.warn("give up to get folder status because of read-lock timeout over #{@read_lock_timeout_seconds} seconds")
            end
          end
          res << "#{tag} OK NOOP completed\r\n"
          yield(res.flush)
        end

        def folder_open_msgs(token)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          all_msgs = @mail_store.mbox_msg_num(folder.mbox_id)
          recent_msgs = @mail_store.mbox_flag_num(folder.mbox_id, 'recent')
          unseen_msgs = all_msgs - @mail_store.mbox_flag_num(folder.mbox_id, 'seen')
          yield("* #{all_msgs} EXISTS\r\n")
          yield("* #{recent_msgs} RECENT\r\n")
          yield("* OK [UNSEEN #{unseen_msgs}]\r\n")
          yield("* OK [UIDVALIDITY #{folder.mbox_id}]\r\n")
          yield("* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n")
          nil
        end
        private :folder_open_msgs

        def select(token, tag, mbox_name)
          if (token) then
            close_no_response(token)
          end

          res = new_bulk_response
          new_token = nil
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)

          if (id = @mail_store.mbox_id(mbox_name_utf8)) then
            new_token = open_folder(id)
            folder_open_msgs(new_token) {|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
            res << "#{tag} OK [READ-WRITE] SELECT completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res.flush)

          new_token
        end
        imap_command_authenticated :select

        def examine(token, tag, mbox_name)
          if (token) then
            close_no_response(token)
          end

          res = new_bulk_response
          new_token = nil
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)

          if (id = @mail_store.mbox_id(mbox_name_utf8)) then
            new_token = open_folder(id, read_only: true)
            folder_open_msgs(new_token) {|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
            res << "#{tag} OK [READ-ONLY] EXAMINE completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res.flush)

          new_token
        end
        imap_command_authenticated :examine

        def create(token, tag, mbox_name)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (@mail_store.mbox_id(mbox_name_utf8)) then
            res << "#{tag} NO duplicated mailbox\r\n"
          else
            @mail_store.add_mbox(mbox_name_utf8)
            res << "#{tag} OK CREATE completed\r\n"
          end
          yield(res.flush)
        end
        imap_command_authenticated :create, exclusive: true

        def delete(token, tag, mbox_name)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (id = @mail_store.mbox_id(mbox_name_utf8)) then
            if (id != @mail_store.mbox_id('INBOX')) then
              @mail_store.del_mbox(id)
              res << "#{tag} OK DELETE completed\r\n"
            else
              res << "#{tag} NO not delete inbox\r\n"
            end
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res.flush)
        end
        imap_command_authenticated :delete, exclusive: true

        def rename(token, tag, src_name, dst_name)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          src_name_utf8 = Net::IMAP.decode_utf7(src_name)
          dst_name_utf8 = Net::IMAP.decode_utf7(dst_name)
          unless (id = @mail_store.mbox_id(src_name_utf8)) then
            res << "#{tag} NO not found a mailbox\r\n"
            return yield(res.flush)
          end
          if (id == @mail_store.mbox_id('INBOX')) then
            res << "#{tag} NO not rename inbox\r\n"
            return yield(res.flush)
          end
          if (@mail_store.mbox_id(dst_name_utf8)) then
            res << "#{tag} NO duplicated mailbox\r\n"
            return yield(res.flush)
          end
          @mail_store.rename_mbox(id, dst_name_utf8)
          res << "#{tag} OK RENAME completed\r\n"
          yield(res.flush)
        end
        imap_command_authenticated :rename, exclusive: true

        def subscribe(token, tag, mbox_name)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (@mail_store.mbox_id(mbox_name_utf8)) then
            res << "#{tag} OK SUBSCRIBE completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res.flush)
        end
        imap_command_authenticated :subscribe

        def unsubscribe(token, tag, mbox_name)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (@mail_store.mbox_id(mbox_name_utf8)) then
            res << "#{tag} NO not implemented subscribe/unsbscribe command\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res.flush)
        end
        imap_command_authenticated :unsubscribe

        def list_mbox(ref_name, mbox_name)
          ref_name_utf8 = Net::IMAP.decode_utf7(ref_name)
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)

          mbox_filter = Protocol.compile_wildcard(mbox_name_utf8)
          mbox_list = @mail_store.each_mbox_id.map{|id| [ id, @mail_store.mbox_name(id) ] }
          mbox_list.keep_if{|id, name| name.start_with? ref_name_utf8 }
          mbox_list.keep_if{|id, name| name[(ref_name_utf8.length)..-1] =~ mbox_filter }

          for id, name_utf8 in mbox_list
            name = Net::IMAP.encode_utf7(name_utf8)
            attrs = '\Noinferiors'
            if (@mail_store.mbox_flag_num(id, 'recent') > 0) then
              attrs << ' \Marked'
            else
              attrs << ' \Unmarked'
            end
            yield("(#{attrs}) NIL #{Protocol.quote(name)}")
          end

          nil
        end
        private :list_mbox

        def list(token, tag, ref_name, mbox_name)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          if (mbox_name.empty?) then
            res << "* LIST (\\Noselect) NIL \"\"\r\n"
          else
            list_mbox(ref_name, mbox_name) {|mbox_entry|
              res << "* LIST #{mbox_entry}\r\n"
              yield(res.flush) if res.full?
            }
          end
          res << "#{tag} OK LIST completed\r\n"
          yield(res.flush)
        end
        imap_command_authenticated :list

        def lsub(token, tag, ref_name, mbox_name)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          if (mbox_name.empty?) then
            res << "* LSUB (\\Noselect) NIL \"\"\r\n"
          else
            list_mbox(ref_name, mbox_name) {|mbox_entry|
              res << "* LSUB #{mbox_entry}\r\n"
              yield(res.flush) if res.full?
            }
          end
          res << "#{tag} OK LSUB completed\r\n"
          yield(res.flush)
        end
        imap_command_authenticated :lsub

        def status(token, tag, mbox_name, data_item_group)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (id = @mail_store.mbox_id(mbox_name_utf8)) then
            unless ((data_item_group.is_a? Array) && (data_item_group[0] == :group)) then
              raise SyntaxError, 'second arugment is not a group list.'
            end

            values = []
            for item in data_item_group[1..-1]
              case (item.upcase)
              when 'MESSAGES'
                values << 'MESSAGES' << @mail_store.mbox_msg_num(id)
              when 'RECENT'
                values << 'RECENT' << @mail_store.mbox_flag_num(id, 'recent')
              when 'UIDNEXT'
                values << 'UIDNEXT' << @mail_store.uid(id)
              when 'UIDVALIDITY'
                values << 'UIDVALIDITY' << id
              when 'UNSEEN'
                unseen_flags = @mail_store.mbox_msg_num(id) - @mail_store.mbox_flag_num(id, 'seen')
                values << 'UNSEEN' << unseen_flags
              else
                raise SyntaxError, "unknown status data: #{item}"
              end
            end

            res << "* STATUS #{Protocol.quote(mbox_name)} (#{values.join(' ')})\r\n"
            res << "#{tag} OK STATUS completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res.flush)
        end
        imap_command_authenticated :status

        def mailbox_size_server_response_multicast_push(mbox_id)
          all_msgs = @mail_store.mbox_msg_num(mbox_id)
          recent_msgs = @mail_store.mbox_flag_num(mbox_id, 'recent')

          f = @mail_store.open_folder(mbox_id, read_only: true)
          begin
            f.server_response_multicast_push("* #{all_msgs} EXISTS\r\n")
            f.server_response_multicast_push("* #{recent_msgs} RECENT\r\n")
          ensure
            f.close
          end

          nil
        end
        private :mailbox_size_server_response_multicast_push

        def append(token, tag, mbox_name, *opt_args, msg_text)
          res = new_bulk_response
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (mbox_id = @mail_store.mbox_id(mbox_name_utf8)) then
            msg_flags = []
            msg_date = Time.now

            if ((! opt_args.empty?) && (opt_args[0].is_a? Array)) then
              opt_flags = opt_args.shift
              if (opt_flags[0] != :group) then
                raise SyntaxError, 'bad flag list.'
              end
              for flag_atom in opt_flags[1..-1]
                case (flag_atom.upcase)
                when '\ANSWERED'
                  msg_flags << 'answered'
                when '\FLAGGED'
                  msg_flags << 'flagged'
                when '\DELETED'
                  msg_flags << 'deleted'
                when '\SEEN'
                  msg_flags << 'seen'
                when '\DRAFT'
                  msg_flags << 'draft'
                else
                  raise SyntaxError, "invalid flag: #{flag_atom}"
                end
              end
            end

            if ((! opt_args.empty?) && (opt_args[0].is_a? String)) then
              begin
                msg_date = Time.parse(opt_args.shift)
              rescue ArgumentError
                raise SyntaxError, $!.message
              end
            end

            unless (opt_args.empty?) then
              raise SyntaxError, "unknown option: #{opt_args.inspect}"
            end

            uid = @mail_store.add_msg(mbox_id, msg_text, msg_date)
            for flag_name in msg_flags
              @mail_store.set_msg_flag(mbox_id, uid, flag_name, true)
            end

            mailbox_size_server_response_multicast_push(mbox_id)
            if (token) then
              folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
              folder.server_response_fetch{|untagged_response|
                res << untagged_response
                yield(res.flush) if res.full?
              }
            end

            res << "#{tag} OK [APPENDUID #{mbox_id} #{uid}] APPEND completed\r\n"
          else
            if (token) then
              folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
              folder.server_response_fetch{|untagged_response|
                res << untagged_response
                yield(res.flush) if res.full?
              }
            end
            res << "#{tag} NO [TRYCREATE] not found a mailbox\r\n"
          end
          yield(res.flush)
        end
        imap_command_authenticated :append, exclusive: true

        def check(token, tag)
          res = new_bulk_response
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
          end
          @mail_store.sync
          res << "#{tag} OK CHECK completed\r\n"
          yield(res.flush)
        end
        imap_command_selected :check, exclusive: true

        def close_no_response(token)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          close_folder(token) do |untagged_response|
            # IMAP CLOSE command may not send untagged EXPUNGE
            # responses, but notifies other connections of them.
            folder.server_response_multicast_push(untagged_response)
          end

          nil
        end
        private :close_no_response

        def close(token, tag)
          close_no_response(token)
          yield([ "#{tag} OK CLOSE completed\r\n" ])
        end
        imap_command_selected :close, exclusive: true

        def expunge(token, tag)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive
          return yield([ "#{tag} NO cannot expunge in read-only mode\r\n" ]) if folder.read_only?
          folder.reload if folder.updated?

          res = new_bulk_response
          folder.server_response_fetch{|untagged_response|
            res << untagged_response
            yield(res.flush) if res.full?
         }

          folder.expunge_mbox do |msg_num|
            untagged_response = "* #{msg_num} EXPUNGE\r\n"
            res << untagged_response
            yield(res.flush) if res.full?
            folder.server_response_multicast_push(untagged_response)
          end

          res << "#{tag} OK EXPUNGE completed\r\n"
          yield(res.flush)
        end
        imap_command_selected :expunge, exclusive: true

        def search(token, tag, *cond_args, uid: false)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive
          folder.reload if folder.updated?
          parser = SearchParser.new(@mail_store, folder,
                                    charset_aliases: @charset_aliases,
                                    charset_convert_options: @charset_convert_options)

          if (! cond_args.empty? && cond_args[0].upcase == 'CHARSET') then
            cond_args.shift
            charset_string = cond_args.shift or raise SyntaxError, 'need for a charset string of CHARSET'
            charset_string.is_a? String or raise SyntaxError, "CHARSET charset string expected as <String> but was <#{charset_string.class}>."
            begin
              parser.charset = charset_string
            rescue ArgumentError
              @logger.warn("unknown charset: #{charset_string}")
              return yield([ "#{tag} NO [BADCHARSET (#{Encoding.list.reject(&:dummy?).map(&:to_s).join(' ')})] unknown charset\r\n" ])
            end
          end

          if (cond_args.empty?) then
            raise SyntaxError, 'required search arguments.'
          end

          if (cond_args[0].upcase == 'UID' && cond_args.length >= 2) then
            begin
              msg_set = folder.parse_msg_set(cond_args[1], uid: true)
              msg_list = folder.msg_find_all(msg_set, uid: true)
              cond_args.shift(2)
            rescue MessageSetSyntaxError
              msg_list = folder.each_msg
            end
          else
            begin
              msg_set = folder.parse_msg_set(cond_args[0], uid: false)
              msg_list = folder.msg_find_all(msg_set, uid: false)
              cond_args.shift
            rescue MessageSetSyntaxError
              msg_list = folder.each_msg
            end
          end
          cond = parser.parse(cond_args)

          res = new_bulk_response
          folder.server_response_fetch{|untagged_response|
            res << untagged_response
            yield(res.flush) if res.full?
          }

          res << '* SEARCH'
          begin
            begin
              for msg in msg_list
                begin
                  if (cond.call(msg)) then
                    if (uid) then
                      res << " #{msg.uid}"
                    else
                      res << " #{msg.num}"
                    end
                    yield(res.flush) if res.full?
                  end
                rescue EncodingError
                  @logger.warn("encoding error at the message: uidvalidity(#{folder.mbox_id}) uid(#{msg.uid})")
                  @logger.warn("#{$!} (#{$!.class})")
                end
              end
            ensure
              res << "\r\n"
            end
          rescue
            yield(res.flush)
            raise
          end

          res << "#{tag} OK SEARCH completed\r\n"
          yield(res.flush)
        end
        imap_command_selected :search

        def fetch(token, tag, msg_set, data_item_group, uid: false)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive
          folder.reload if folder.updated?

          msg_set = folder.parse_msg_set(msg_set, uid: uid)
          msg_list = folder.msg_find_all(msg_set, uid: uid)

          unless ((data_item_group.is_a? Array) && data_item_group[0] == :group) then
            data_item_group = [ :group, data_item_group ]
          end
          if (uid) then
            unless (data_item_group.find{|i| (i.is_a? String) && (i.upcase == 'UID') }) then
              data_item_group = [ :group, 'UID' ] + data_item_group[1..-1]
            end
          end

          parser = FetchParser.new(@mail_store, folder, charset_aliases: @charset_aliases)
          fetch = parser.parse(data_item_group)

          res = new_bulk_response
          folder.server_response_fetch{|untagged_response|
            res << untagged_response
            yield(res.flush) if res.full?
          }

          for msg in msg_list
            res << ('* '.b << msg.num.to_s.b << ' FETCH '.b << fetch.call(msg) << "\r\n".b)
            yield(res.flush) if res.full?
          end

          res << "#{tag} OK FETCH completed\r\n"
          yield(res.flush)
        end
        imap_command_selected :fetch

        def store(token, tag, msg_set, data_item_name, data_item_value, uid: false)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive
          return yield([ "#{tag} NO cannot store in read-only mode\r\n" ]) if folder.read_only?
          folder.reload if folder.updated?

          msg_set = folder.parse_msg_set(msg_set, uid: uid)
          name, option = data_item_name.split(/\./, 2)

          case (name.upcase)
          when 'FLAGS'
            action = :flags_replace
          when '+FLAGS'
            action = :flags_add
          when '-FLAGS'
            action = :flags_del
          else
            raise SyntaxError, "unknown store action: #{name}"
          end

          case (option && option.upcase)
          when 'SILENT'
            is_silent = true
          when nil
            is_silent = false
          else
            raise SyntaxError, "unknown store option: #{option.inspect}"
          end

          if ((data_item_value.is_a? Array) && data_item_value[0] == :group) then
            flag_list = []
            for flag_atom in data_item_value[1..-1]
              case (flag_atom.upcase)
              when '\ANSWERED'
                flag_list << 'answered'
              when '\FLAGGED'
                flag_list << 'flagged'
              when '\DELETED'
                flag_list << 'deleted'
              when '\SEEN'
                flag_list << 'seen'
              when '\DRAFT'
                flag_list << 'draft'
              else
                raise SyntaxError, "invalid flag: #{flag_atom}"
              end
            end
            rest_flag_list = (MailStore::MSG_FLAG_NAMES - %w[ recent ]) - flag_list
          else
            raise SyntaxError, 'third arugment is not a group list.'
          end

          msg_list = folder.msg_find_all(msg_set, uid: uid)

          for msg in msg_list
            case (action)
            when :flags_replace
              for name in flag_list
                @mail_store.set_msg_flag(folder.mbox_id, msg.uid, name, true)
              end
              for name in rest_flag_list
                @mail_store.set_msg_flag(folder.mbox_id, msg.uid, name, false)
              end
            when :flags_add
              for name in flag_list
                @mail_store.set_msg_flag(folder.mbox_id, msg.uid, name, true)
              end
            when :flags_del
              for name in flag_list
                @mail_store.set_msg_flag(folder.mbox_id, msg.uid, name, false)
              end
            else
              raise "internal error: unknown action: #{action}"
            end
          end

          res = new_bulk_response
          folder.server_response_fetch{|untagged_response|
            res << untagged_response
            yield(res.flush) if res.full?
          }

          if (is_silent) then
            res << "#{tag} OK STORE completed\r\n"
            yield(res.flush)
          else
            for msg in msg_list
              flag_atom_list = nil

              if (@mail_store.msg_exist? folder.mbox_id, msg.uid) then
                flag_atom_list = []
                for name in MailStore::MSG_FLAG_NAMES
                  if (@mail_store.msg_flag(folder.mbox_id, msg.uid, name)) then
                    flag_atom_list << "\\#{name.capitalize}"
                  end
                end
              end

              if (flag_atom_list) then
                if (uid) then
                  res << "* #{msg.num} FETCH (UID #{msg.uid} FLAGS (#{flag_atom_list.join(' ')}))\r\n"
                else
                  res << "* #{msg.num} FETCH (FLAGS (#{flag_atom_list.join(' ')}))\r\n"
                end
                yield(res.flush) if res.full?
              else
                @logger.warn("not found a message and skipped: uidvalidity(#{folder.mbox_id}) uid(#{msg.uid})")
              end
            end

            res << "#{tag} OK STORE completed\r\n"
            yield(res.flush)
          end
        end
        imap_command_selected :store, exclusive: true

        def copy(token, tag, msg_set, mbox_name, uid: false)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive
          folder.reload if folder.updated?

          res = new_bulk_response
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          msg_set = folder.parse_msg_set(msg_set, uid: uid)

          if (mbox_id = @mail_store.mbox_id(mbox_name_utf8)) then
            msg_list = folder.msg_find_all(msg_set, uid: uid)

            src_uids = []
            dst_uids = []
            for msg in msg_list
              src_uids << msg.uid
              dst_uids << @mail_store.copy_msg(msg.uid, folder.mbox_id, mbox_id)
            end

            if (msg_list.size > 0) then
              mailbox_size_server_response_multicast_push(mbox_id)
              folder.server_response_fetch{|untagged_response|
                res << untagged_response
                yield(res.flush) if res.full?
              }
              res << "#{tag} OK [COPYUID #{mbox_id} #{src_uids.join(',')} #{dst_uids.join(',')}] COPY completed\r\n"
            else
              folder.server_response_fetch{|untagged_response|
                res << untagged_response
                yield(res.flush) if res.full?
              }
              res << "#{tag} OK COPY completed\r\n"
            end
          else
            folder.server_response_fetch{|untagged_response|
              res << untagged_response
              yield(res.flush) if res.full?
            }
            res << "#{tag} NO [TRYCREATE] not found a mailbox\r\n"
          end
          yield(res.flush)
        end
        imap_command_selected :copy, exclusive: true

        def idle(token, tag, client_input_gets, server_output_write, connection_timer)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive

          @logger.info('idle start...')
          server_output_write.call([ "+ continue\r\n" ])

          server_response_thread = Thread.new{
            res = new_bulk_response
            @logger.info('idle server response thread start...')
            folder.server_response_idle_wait{|server_response_list|
              for untagged_response in server_response_list
                @logger.debug("idle server response: #{untagged_response}") if @logger.debug?
                res << untagged_response
                server_output_write.call(res.flush) if res.full?
              end
              server_output_write.call(res.flush) unless res.empty?
            }
            @logger.info('idle server response thread terminated.')
          }

          begin
            connection_timer.command_wait or return
            line = client_input_gets.call
          ensure
            folder.server_response_idle_interrupt
            server_response_thread.join
          end

          last_res = []
          if (line) then
            line.chomp!("\n")
            line.chomp!("\r")
            if (line.upcase == "DONE") then
              @logger.info('idle terminated.')
              last_res << "#{tag} OK IDLE terminated\r\n"
            else
              @logger.warn('unexpected client response and idle terminated.')
              @logger.debug("unexpected client response data: #{line}") if @logger.debug?
              last_res << "#{tag} BAD unexpected client response\r\n"
            end
          else
            @logger.warn('unexpected client connection close and idle terminated.')
            last_res << "#{tag} BAD unexpected client connection close\r\n"
          end
          yield(last_res)
        end
        imap_command_selected :idle, exclusive: nil
      end

      def initialize(parent_decoder, engine, auth, logger)
        super(auth, logger)
        @parent_decoder = parent_decoder
        @engine = engine
        @token = nil
        @logger.debug("RIMS::Protocol::UserMailboxDecoder#initialize at #{self}") if @logger.debug?
      end

      def auth?
        ! @engine.nil?
      end

      def selected?
        ! @token.nil?
      end

      # `not_cleanup_parent' keyword argument is defined for MailDeliveryDecoder
      def cleanup(not_cleanup_parent: false)
        @logger.debug("RIMS::Protocol::UserMailboxDecoder#cleanup at #{self}") if @logger.debug?

        unless (@engine.nil?) then
          begin
            @engine.cleanup(@token)
          ensure
            @token = nil
          end
        end

        unless (not_cleanup_parent) then
          unless (@engine.nil?) then
            begin
              @engine.destroy
            ensure
              @engine = nil
            end
          end

          unless (@parent_decoder.nil?) then
            @parent_decoder.cleanup
            @parent_decoder = nil
          end
        end

        nil
      end

      def noop(tag)
        ret_val = nil
        @engine.noop(@token, tag) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :noop

      def logout(tag, &block)
        if (@token) then
          old_token = @token
          @token = nil
          @engine.cleanup(old_token)
        end

        @next_decoder = LogoutDecoder.new(self, @logger)
        make_logout_response(tag, &block)
      end
      imap_command :logout

      def select(tag, mbox_name)
        ret_val = nil
        old_token = @token
        @token = @engine.select(old_token, tag, mbox_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :select

      def examine(tag, mbox_name)
        ret_val = nil
        old_token = @token
        @token = @engine.examine(old_token, tag, mbox_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :examine

      def create(tag, mbox_name)
        ret_val = nil
        @engine.create(@token, tag, mbox_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :create

      def delete(tag, mbox_name)
        ret_val = nil
        @engine.delete(@token, tag, mbox_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :delete

      def rename(tag, src_name, dst_name)
        ret_val = nil
        @engine.rename(@token, tag, src_name, dst_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :rename

      def subscribe(tag, mbox_name)
        ret_val = nil
        @engine.subscribe(@token, tag, mbox_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name)
        ret_val = nil
        @engine.unsubscribe(@token, tag, mbox_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name)
        ret_val = nil
        @engine.list(@token, tag, ref_name, mbox_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name)
        ret_val = nil
        @engine.lsub(@token, tag, ref_name, mbox_name) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group)
        ret_val = nil
        @engine.status(@token, tag, mbox_name, data_item_group) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :status

      def append(tag, mbox_name, *opt_args, msg_text)
        ret_val = nil
        @engine.append(@token, tag, mbox_name, *opt_args, msg_text) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :append

      def check(tag)
        ret_val = nil
        @engine.check(@token, tag) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :check

      def close(tag)
        ret_val = nil
        old_token = @token
        @token = nil
        @engine.close(old_token, tag) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :close

      def expunge(tag)
        ret_val = nil
        @engine.expunge(@token, tag) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false)
        ret_val = nil
        @engine.search(@token, tag, *cond_args, uid: uid) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false)
        ret_val = nil
        @engine.fetch(@token, tag, msg_set, data_item_group, uid: uid) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        ret_val = nil
        @engine.store(@token, tag, msg_set, data_item_name, data_item_value, uid: uid) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false)
        ret_val = nil
        @engine.copy(@token, tag, msg_set, mbox_name, uid: uid) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :copy

      def idle(tag, client_input_gets, server_output_write, connection_timer)
        ret_val = nil
        @engine.idle(@token, tag, client_input_gets, server_output_write, connection_timer) {|res|
          for response in res
            ret_val = yield(response)
          end
        }

        ret_val
      end
      imap_command :idle
    end

    # alias
    Decoder::Engine       = UserMailboxDecoder::Engine
    Decoder::BulkResponse = UserMailboxDecoder::BulkResponse

    def Decoder.encode_delivery_target_mailbox(username, mbox_name)
      "b64user-mbox #{Protocol.encode_base64(username)} #{mbox_name}"
    end

    def Decoder.decode_delivery_target_mailbox(encoded_mbox_name)
      encode_type, base64_username, mbox_name = encoded_mbox_name.split(' ', 3)
      if (encode_type != 'b64user-mbox') then
        raise SyntaxError, "unknown mailbox encode type: #{encode_type}"
      end
      return Protocol.decode_base64(base64_username), mbox_name
    end

    class MailDeliveryDecoder < AuthenticatedDecoder
      def initialize(parent_decoder, drb_services, auth, logger)
        super(auth, logger)
        @parent_decoder = parent_decoder
        @drb_services = drb_services
        @auth = auth
        @last_user_cache_key_username = nil
        @last_user_cache_value_engine = nil
        @logger.debug("RIMS::Protocol::MailDeliveryDecoder#initialize at #{self}") if @logger.debug?
      end

      def engine_cached?(username)
        @last_user_cache_key_username == username
      end
      private :engine_cached?

      def engine_cache(username)
        unless (engine_cached? username) then
          raise "not cached: #{username}"
        end
        @last_user_cache_value_engine
      end
      private :engine_cache

      def store_engine_cache(username)
        if (engine_cached? username) then
          raise "already cached: #{username}"
        end

        release_engine_cache
        @last_user_cache_value_engine = yield
        @last_user_cache_key_username = username # success to store engine cache

        @last_user_cache_value_engine
      end
      private :store_engine_cache

      def release_engine_cache
        if (@last_user_cache_value_engine) then
          engine = @last_user_cache_value_engine
          @last_user_cache_key_username = nil
          @last_user_cache_value_engine = nil
          engine.destroy
        end
      end
      private :release_engine_cache

      def auth?
        @drb_services != nil
      end

      def selected?
        false
      end

      def cleanup
        @logger.debug("RIMS::Protocol::MailDeliveryDecoder#cleanup at #{self}") if @logger.debug?

        release_engine_cache
        @drb_services = nil unless @drb_services.nil?
        @auth = nil unless @auth.nil?

        unless (@parent_decoder.nil?) then
          @parent_decoder.cleanup
          @parent_decoder = nil
        end

        nil
      end

      def logout(tag, &block)
        @next_decoder = LogoutDecoder.new(self, @logger)
        make_logout_response(tag, &block)
      end
      imap_command :logout

      alias standard_capability _capability
      private :standard_capability

      def capability(tag)
        standard_capability(tag) {|response|
          if (response.start_with? '* CAPABILITY ') then
            yield(response.strip + " X-RIMS-MAIL-DELIVERY-USER\r\n")
          else
            yield(response)
          end
        }
      end
      imap_command :capability

      def make_not_allowed_command_response(tag)
        yield("#{tag} NO not allowed command on mail delivery user\r\n")
      end
      private :make_not_allowed_command_response

      def select(tag, mbox_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :select

      def examine(tag, mbox_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :examine

      def create(tag, mbox_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :create

      def delete(tag, mbox_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :delete

      def rename(tag, src_name, dst_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :rename

      def subscribe(tag, mbox_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :status

      def deliver_to_user(tag, username, mbox_name, opt_args, msg_text, engine)
        user_decoder = UserMailboxDecoder.new(self, engine, @auth, @logger)
        begin
          last_response = nil
          user_decoder.append(tag, mbox_name, *opt_args, msg_text) {|response|
            last_response = response
            yield(response)
          }
          if (last_response.split(' ', 3)[1] == 'OK') then
            @logger.info("message delivery: successed to deliver #{msg_text.bytesize} octets message.")
          else
            @logger.info("message delivery: failed to deliver message.")
          end
        ensure
          user_decoder.cleanup(not_cleanup_parent: true)
        end
      end
      private :deliver_to_user

      def append(tag, encoded_mbox_name, *opt_args, msg_text)
        username, mbox_name = self.class.decode_delivery_target_mailbox(encoded_mbox_name)
        @logger.info("message delivery: user #{username}, mailbox #{mbox_name}")

        if (@auth.user? username) then
          if (engine_cached? username) then
            engine = engine_cache(username)
            deliver_to_user(tag, username, mbox_name, opt_args, msg_text, engine) {|response|
              yield(response)
            }
          else
            engine = store_engine_cache(username) {
              self.class.make_engine_and_recovery_if_needed(@drb_services, username, logger: @logger) {|untagged_response|
                yield(untagged_response)
                yield(:flush)
              }
            }
            deliver_to_user(tag, username, mbox_name, opt_args, msg_text, engine) {|response|
              yield(response)
            }
          end
        else
          @logger.info('message delivery: not found a user.')
          yield("#{tag} NO not found a user and couldn't deliver a message to the user's mailbox\r\n")
        end
      end
      imap_command :append

      def check(tag, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :check

      def close(tag, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :close

      def expunge(tag, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :copy

      def idle(tag, client_input_gets, server_output_write, connection_timer, &block)
        make_not_allowed_command_response(tag, &block)
      end
      imap_command :idle
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
