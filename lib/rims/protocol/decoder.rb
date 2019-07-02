# -*- coding: utf-8 -*-

require 'logger'
require 'net/imap'
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

      def self.repl(decoder, limits, input, output, logger)
        input_gets = input.method(:gets)
        output_write = lambda{|res|
          last_line = nil
          for data in res
            if (data == :flush) then
              output.flush
            else
              logger.debug("response data: #{Protocol.io_data_log(data)}") if logger.debug?
              output << data
              last_line = data
            end
          end
          output.flush

          last_line
        }
        response_write = proc{|res|
          begin
            last_line = output_write.call(res)
            logger.info("server response: #{last_line.strip}")
          rescue
            logger.error('response write error.')
            logger.error($!)
            raise
          end
        }

        decoder.ok_greeting{|res| response_write.call(res) }

        conn_timer = ConnectionTimer.new(limits, input.to_io)
        request_reader = RequestReader.new(input, output, logger)

        until (conn_timer.command_wait_timeout?)
          conn_timer.command_wait or break

          begin
            atom_list = request_reader.read_command
          rescue
            logger.error('invalid client command.')
            Error.trace_error_chain($!) do |exception|
              logger.error(exception)
            end
            response_write.call([ "* BAD client command syntax error\r\n" ])
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
                    decoder.__send__(uid_name, tag, *uid_args, uid: true) {|res| response_write.call(res) }
                  else
                    logger.error("unknown uid command: #{uid_command}")
                    response_write.call([ "#{tag} BAD unknown uid command\r\n" ])
                  end
                else
                  logger.error('empty uid parameter.')
                  response_write.call([ "#{tag} BAD empty uid parameter\r\n" ])
                end
              when :authenticate
                decoder.authenticate(tag, input_gets, output_write, *opt_args) {|res| response_write.call(res) }
              when :idle
                decoder.idle(tag, input_gets, output_write, conn_timer, *opt_args) {|res| response_write.call(res) }
              else
                decoder.__send__(name, tag, *opt_args) {|res| response_write.call(res) }
              end
            else
              logger.error("unknown command: #{command}")
              response_write.call([ "#{tag} BAD unknown command\r\n" ])
            end
          rescue
            logger.error('unexpected error.')
            Error.trace_error_chain($!) do |exception|
              logger.error(exception)
            end
            response_write.call([ "#{tag} BAD unexpected error\r\n" ])
          end

          if (normalized_command == 'LOGOUT') then
            break
          end

          decoder = decoder.next_decoder
        end

        if (conn_timer.command_wait_timeout?) then
          if (limits.command_wait_timeout_seconds > 0) then
            response_write.call([ "* BYE server autologout: idle for too long\r\n" ])
          else
            response_write.call([ "* BYE server autologout: shutdown\r\n" ])
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

      def response_stream(tag)
        Enumerator.new{|res|
          begin
            yield(res)
          rescue SyntaxError
            @logger.error('client command syntax error.')
            @logger.error($!)
            res << "#{tag} BAD client command syntax error\r\n"
          rescue
            raise if ($!.class.name =~ /AssertionFailedError/)
            @logger.error('internal server error.')
            Error.trace_error_chain($!) do |exception|
              @logger.error(exception)
            end
            res << "#{tag} BAD internal server error\r\n"
          end
        }
      end
      private :response_stream

      def guard_error(imap_command, tag, *args, **kw_args, &block)
        begin
          if (kw_args.empty?) then
            __send__(imap_command, tag, *args, &block)
          else
            __send__(imap_command, tag, *args, **kw_args, &block)
          end
        rescue SyntaxError
          @logger.error('client command syntax error.')
          @logger.error($!)
          yield([ "#{tag} BAD client command syntax error\r\n" ])
        rescue ArgumentError
          @logger.error('invalid command parameter.')
          @logger.error($!)
          yield([ "#{tag} BAD invalid command parameter\r\n" ])
        rescue
          raise if ($!.class.name =~ /AssertionFailedError/)
          @logger.error('internal server error.')
          Error.trace_error_chain($!) do |exception|
            @logger.error(exception)
          end
          yield([ "#{tag} BAD internal server error\r\n" ])
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

        def make_engine_and_recovery_if_needed(drb_services, username,
                                               logger: Logger.new(STDOUT))
          unique_user_id = Authentication.unique_user_id(username)
          logger.debug("unique user ID: #{username} -> #{unique_user_id}") if logger.debug?

          logger.info("open mail store: #{unique_user_id} [ #{username} ]")
          engine = drb_services[:engine, unique_user_id]

          begin
            engine.recovery_if_needed(username) {|msg| yield(msg) }
          rescue
            engine.destroy
            raise
          end

          engine
        end
      end

      def make_logout_response(tag)
        [ "* BYE server logout\r\n",
          "#{tag} OK LOGOUT completed\r\n"
        ]
      end
      private :make_logout_response

      def ok_greeting
        yield([ "* OK RIMS v#{VERSION} IMAP4rev1 service ready.\r\n" ])
      end

      # common IMAP command
      IMAP_CMDs['CAPABILITY'] = :capability

      def capability(tag)
        capability_list = %w[ IMAP4rev1 UIDPLUS IDLE ]
        capability_list += @auth.capability.map{|auth_capability| "AUTH=#{auth_capability}" }
        res = []
        res << "* CAPABILITY #{capability_list.join(' ')}\r\n"
        res << "#{tag} OK CAPABILITY completed\r\n"
        yield(res)
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
                     mail_delivery_user: Service::DEFAULT_CONFIG.mail_delivery_user)
        super(auth, logger)
        @drb_services = drb_services
        @mail_delivery_user = mail_delivery_user
      end

      def auth?
        false
      end

      def selected?
        false
      end

      def cleanup
        nil
      end

      def make_not_authenticated_response(tag)
        [ "#{tag} NO not authenticated\r\n" ]
      end
      private :make_not_authenticated_response

      def noop(tag)
        yield([ "#{tag} OK NOOP completed\r\n" ])
      end
      imap_command :noop

      def logout(tag)
        @next_decoder = LogoutDecoder.new(self)
        yield(make_logout_response(tag))
      end
      imap_command :logout

      def accept_authentication(username)
        case (username)
        when @mail_delivery_user
          @logger.info("mail delivery user: #{username}")
          MailDeliveryDecoder.new(self, @drb_services, @auth, @logger)
        else
          engine = self.class.make_engine_and_recovery_if_needed(@drb_services, username, logger: @logger) {|msg| yield(msg) }
          UserMailboxDecoder.new(self, engine, @auth, @logger)
        end
      end
      private :accept_authentication

      def authenticate(tag, client_response_input_gets, server_challenge_output_write,
                       auth_type, inline_client_response_data_base64=nil)
        auth_reader = AuthenticationReader.new(@auth, client_response_input_gets, server_challenge_output_write, @logger)
        if (username = auth_reader.authenticate_client(auth_type, inline_client_response_data_base64)) then
          if (username != :*) then
            yield response_stream(tag) {|res|
              @logger.info("authentication OK: #{username}")
              @next_decoder = accept_authentication(username) {|msg| res << msg }
              res << "#{tag} OK AUTHENTICATE #{auth_type} success\r\n"
            }
          else
            @logger.info('bad authentication.')
            yield([ "#{tag} BAD AUTHENTICATE failed\r\n" ])
          end
        else
          yield([ "#{tag} NO authentication failed\r\n" ])
        end
      end
      imap_command :authenticate

      def login(tag, username, password)
        if (@auth.authenticate_login(username, password)) then
          yield response_stream(tag) {|res|
            @logger.info("login authentication OK: #{username}")
            @next_decoder = accept_authentication(username) {|msg| res << msg }
            res << "#{tag} OK LOGIN completed\r\n"
          }
        else
          yield([ "#{tag} NO failed to login\r\n" ])
        end
      end
      imap_command :login

      def select(tag, mbox_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :select

      def examine(tag, mbox_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :examine

      def create(tag, mbox_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :create

      def delete(tag, mbox_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :delete

      def rename(tag, src_name, dst_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :rename

      def subscribe(tag, mbox_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :status

      def append(tag, mbox_name, *opt_args, msg_text)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :append

      def check(tag)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :check

      def close(tag)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :close

      def expunge(tag)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :copy

      def idle(tag, client_input_gets, server_output_write, connection_timer)
        yield(make_not_authenticated_response(tag))
      end
      imap_command :idle
    end

    class LogoutDecoder < Decoder
      def initialize(parent_decoder)
        @parent_decoder = parent_decoder
      end

      def next_decoder
        self
      end

      def auth?
        false
      end

      def selected?
        false
      end

      def cleanup
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
        yield([ "#{tag} NO duplicated authentication\r\n" ])
      end
      imap_command :authenticate

      def login(tag, username, password, &block)
        yield([ "#{tag} NO duplicated login\r\n" ])
      end
      imap_command :login
    end

    class UserMailboxDecoder < AuthenticatedDecoder
      class Engine
        def initialize(unique_user_id, mail_store, logger,
                       bulk_response_count: 100,
                       read_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                       write_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                       cleanup_write_lock_timeout_seconds: 1)
          @unique_user_id = unique_user_id
          @mail_store = mail_store
          @logger = logger
          @bulk_response_count = bulk_response_count
          @read_lock_timeout_seconds = read_lock_timeout_seconds
          @write_lock_timeout_seconds = write_lock_timeout_seconds
          @cleanup_write_lock_timeout_seconds = cleanup_write_lock_timeout_seconds
          @folders = {}
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

          token
        end
        private :open_folder

        def close_folder(token)
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
          tmp_mail_store = @mail_store
          ReadWriteLock.write_lock_timeout_detach(@cleanup_write_lock_timeout_seconds, @write_lock_timeout_seconds, logger: @logger) {|timeout_seconds|
            @mail_store.write_synchronize(timeout_seconds) {
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
            orig_name = "_#{name}".to_sym
            alias_method orig_name, name
            define_method name, lambda{|token, tag, *args, **kw_args, &block|
              guard_authenticated(orig_name, token, tag, *args, **kw_args, **guard_optional, &block)
            }
            name.to_sym
          end
          private :imap_command_authenticated

          def imap_command_selected(name, **guard_optional)
            orig_name = "_#{name}".to_sym
            alias_method orig_name, name
            define_method name, lambda{|token, tag, *args, **kw_args, &block|
              guard_selected(orig_name, token, tag, *args, **kw_args, **guard_optional, &block)
            }
            name.to_sym
          end
          private :imap_command_selected
        end

        def noop(token, tag)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            begin
              @mail_store.read_synchronize(@read_lock_timeout_seconds) {
                folder.server_response_fetch{|r| res << r } if folder.server_response?
              }
            rescue ReadLockTimeoutError
              @logger.warn("give up to get folder status because of read-lock timeout over #{@read_lock_timeout_seconds} seconds")
            end
          end
          res << "#{tag} OK NOOP completed\r\n"
          yield(res)
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

          res = []
          new_token = nil
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)

          if (id = @mail_store.mbox_id(mbox_name_utf8)) then
            new_token = open_folder(id)
            folder_open_msgs(new_token) do |msg|
              res << msg
            end
            res << "#{tag} OK [READ-WRITE] SELECT completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res)

          new_token
        end
        imap_command_authenticated :select

        def examine(token, tag, mbox_name)
          if (token) then
            close_no_response(token)
          end

          res = []
          new_token = nil
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)

          if (id = @mail_store.mbox_id(mbox_name_utf8)) then
            new_token = open_folder(id, read_only: true)
            folder_open_msgs(new_token) do |msg|
              res << msg
            end
            res << "#{tag} OK [READ-ONLY] EXAMINE completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res)

          new_token
        end
        imap_command_authenticated :examine

        def create(token, tag, mbox_name)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
          end
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (@mail_store.mbox_id(mbox_name_utf8)) then
            res << "#{tag} NO duplicated mailbox\r\n"
          else
            @mail_store.add_mbox(mbox_name_utf8)
            res << "#{tag} OK CREATE completed\r\n"
          end
          yield(res)
        end
        imap_command_authenticated :create, exclusive: true

        def delete(token, tag, mbox_name)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
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
          yield(res)
        end
        imap_command_authenticated :delete, exclusive: true

        def rename(token, tag, src_name, dst_name)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
          end
          src_name_utf8 = Net::IMAP.decode_utf7(src_name)
          dst_name_utf8 = Net::IMAP.decode_utf7(dst_name)
          unless (id = @mail_store.mbox_id(src_name_utf8)) then
            return yield(res << "#{tag} NO not found a mailbox\r\n")
          end
          if (id == @mail_store.mbox_id('INBOX')) then
            return yield(res << "#{tag} NO not rename inbox\r\n")
          end
          if (@mail_store.mbox_id(dst_name_utf8)) then
            return yield(res << "#{tag} NO duplicated mailbox\r\n")
          end
          @mail_store.rename_mbox(id, dst_name_utf8)
          res << "#{tag} OK RENAME completed\r\n"
          yield(res)
        end
        imap_command_authenticated :rename, exclusive: true

        def subscribe(token, tag, mbox_name)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
          end
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (@mail_store.mbox_id(mbox_name_utf8)) then
            res << "#{tag} OK SUBSCRIBE completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res)
        end
        imap_command_authenticated :subscribe

        def unsubscribe(token, tag, mbox_name)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
          end
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (@mail_store.mbox_id(mbox_name_utf8)) then
            res << "#{tag} NO not implemented subscribe/unsbscribe command\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
          yield(res)
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
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
          end
          if (mbox_name.empty?) then
            res << "* LIST (\\Noselect) NIL \"\"\r\n"
          else
            list_mbox(ref_name, mbox_name) do |mbox_entry|
              res << "* LIST #{mbox_entry}\r\n"
            end
          end
          res << "#{tag} OK LIST completed\r\n"
          yield(res)
        end
        imap_command_authenticated :list

        def lsub(token, tag, ref_name, mbox_name)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
          end
          if (mbox_name.empty?) then
            res << "* LSUB (\\Noselect) NIL \"\"\r\n"
          else
            list_mbox(ref_name, mbox_name) do |mbox_entry|
              res << "* LSUB #{mbox_entry}\r\n"
            end
          end
          res << "#{tag} OK LSUB completed\r\n"
          yield(res)
        end
        imap_command_authenticated :lsub

        def status(token, tag, mbox_name, data_item_group)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
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
          yield(res)
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
          res = []
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
              folder.server_response_fetch{|r| res << r }
            end

            res << "#{tag} OK [APPENDUID #{mbox_id} #{uid}] APPEND completed\r\n"
          else
            if (token) then
              folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
              folder.server_response_fetch{|r| res << r }
            end
            res << "#{tag} NO [TRYCREATE] not found a mailbox\r\n"
          end
          yield(res)
        end
        imap_command_authenticated :append, exclusive: true

        def check(token, tag)
          res = []
          if (token) then
            folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
            folder.server_response_fetch{|r| res << r }
          end
          @mail_store.sync
          res << "#{tag} OK CHECK completed\r\n"
          yield(res)
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

          res = []
          folder.server_response_fetch{|r|
            res << r
            if (res.length >= @bulk_response_count) then
              yield(res)
              res = []
            end
          }

          folder.expunge_mbox do |msg_num|
            r = "* #{msg_num} EXPUNGE\r\n"
            res << r
            if (res.length >= @bulk_response_count) then
              yield(res)
              res = []
            end
            folder.server_response_multicast_push(r)
          end

          res << "#{tag} OK EXPUNGE completed\r\n"
          yield(res)
        end
        imap_command_selected :expunge, exclusive: true

        def search(token, tag, *cond_args, uid: false)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive
          folder.reload if folder.updated?
          parser = SearchParser.new(@mail_store, folder)

          if (! cond_args.empty? && cond_args[0].upcase == 'CHARSET') then
            cond_args.shift
            charset_string = cond_args.shift or raise SyntaxError, 'need for a charset string of CHARSET'
            charset_string.is_a? String or raise SyntaxError, "CHARSET charset string expected as <String> but was <#{charset_string.class}>."
            begin
              parser.charset = charset_string
            rescue ArgumentError
              @logger.warn("unknown charset: #{charset_string}")
              return yield([ "#{tag} NO [BADCHARSET (#{Encoding.list.map(&:to_s).join(' ')})] unknown charset\r\n" ])
            end
          end

          if (cond_args.empty?) then
            raise SyntaxError, 'required search arguments.'
          end

          if (cond_args[0].upcase == 'UID' && cond_args.length >= 2) then
            begin
              msg_set = folder.parse_msg_set(cond_args[1], uid: true)
              msg_src = folder.msg_find_all(msg_set, uid: true)
              cond_args.shift(2)
            rescue MessageSetSyntaxError
              msg_src = folder.each_msg
            end
          else
            begin
              msg_set = folder.parse_msg_set(cond_args[0], uid: false)
              msg_src = folder.msg_find_all(msg_set, uid: false)
              cond_args.shift
            rescue MessageSetSyntaxError
              msg_src = folder.each_msg
            end
          end
          cond = parser.parse(cond_args)

          res = []
          folder.server_response_fetch{|r|
            res << r
            if (res.length >= @bulk_response_count) then
              yield(res)
              res = []
            end
          }

          res << '* SEARCH'
          begin
            begin
              for msg in msg_src
                begin
                  if (cond.call(msg)) then
                    if (uid) then
                      res << " #{msg.uid}"
                    else
                      res << " #{msg.num}"
                    end
                    if (res.length >= @bulk_response_count) then
                      yield(res)
                      res = []
                    end
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
            # flush bulk response
            yield(res)
            res = []
            raise
          end

          res << "#{tag} OK SEARCH completed\r\n"
          yield(res)
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

          parser = FetchParser.new(@mail_store, folder)
          fetch = parser.parse(data_item_group)

          res = []
          folder.server_response_fetch{|r|
            res << r
            if (res.length >= @bulk_response_count) then
              yield(res)
              res = []
            end
          }

          for msg in msg_list
            res << ('* '.b << msg.num.to_s.b << ' FETCH '.b << fetch.call(msg) << "\r\n".b)
            if (res.length >= @bulk_response_count) then
              yield(res)
              res = []
            end
          end

          res << "#{tag} OK FETCH completed\r\n"
          yield(res)
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

          res = []
          folder.server_response_fetch{|r|
            res << r
            if (res.length >= @bulk_response_count) then
              yield(res)
              res = []
            end
          }

          if (is_silent) then
            res << "#{tag} OK STORE completed\r\n"
            yield(res)
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
                if (res.length >= @bulk_response_count) then
                  yield(res)
                  res = []
                end
              else
                @logger.warn("not found a message and skipped: uidvalidity(#{folder.mbox_id}) uid(#{msg.uid})")
              end
            end

            res << "#{tag} OK STORE completed\r\n"
            yield(res)
          end
        end
        imap_command_selected :store, exclusive: true

        def copy(token, tag, msg_set, mbox_name, uid: false)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive
          folder.reload if folder.updated?

          res = []
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
              folder.server_response_fetch{|r| res << r }
              res << "#{tag} OK [COPYUID #{mbox_id} #{src_uids.join(',')} #{dst_uids.join(',')}] COPY completed\r\n"
            else
              folder.server_response_fetch{|r| res << r }
              res << "#{tag} OK COPY completed\r\n"
            end
          else
            folder.server_response_fetch{|r| res << r }
            res << "#{tag} NO [TRYCREATE] not found a mailbox\r\n"
          end
          yield(res)
        end
        imap_command_selected :copy, exclusive: true

        def idle(token, tag, client_input_gets, server_output_write, connection_timer)
          folder = @folders[token] or raise KeyError.new("undefined folder token: #{token}", key: token, receiver: self)
          folder.should_be_alive

          @logger.info('idle start...')
          server_output_write.call([ "+ continue\r\n" ])

          server_response_thread = Thread.new{
            @logger.info('idle server response thread start... ')
            folder.server_response_idle_wait{|server_response_list|
              for server_response in server_response_list
                @logger.debug("idle server response: #{server_response}") if @logger.debug?
              end
              server_output_write.call(server_response_list)
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

          res = []
          if (line) then
            line.chomp!("\n")
            line.chomp!("\r")
            if (line.upcase == "DONE") then
              @logger.info('idle terminated.')
              res << "#{tag} OK IDLE terminated\r\n"
            else
              @logger.warn('unexpected client response and idle terminated.')
              @logger.debug("unexpected client response data: #{line}") if @logger.debug?
              res << "#{tag} BAD unexpected client response\r\n"
            end
          else
            @logger.warn('unexpected client connection close and idle terminated.')
            res << "#{tag} BAD unexpected client connection close\r\n"
          end
          yield(res)
        end
        imap_command_selected :idle, exclusive: nil
      end

      def initialize(parent_decoder, engine, auth, logger)
        super(auth, logger)
        @parent_decoder = parent_decoder
        @engine = engine
        @token = nil
      end

      def auth?
        ! @engine.nil?
      end

      def selected?
        ! @token.nil?
      end

      def cleanup
        unless (@engine.nil?) then
          begin
            @engine.cleanup(@token)
          ensure
            @token = nil
          end

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

        nil
      end

      def noop(tag, &block)
        @engine.noop(@token, tag, &block)
      end
      imap_command :noop

      def logout(tag)
        if (@token) then
          old_token = @token
          @token = nil
          @engine.cleanup(old_token)
        end

        @next_decoder = LogoutDecoder.new(self)
        yield(make_logout_response(tag))
      end
      imap_command :logout

      def select(tag, mbox_name)
        ret_val = nil
        old_token = @token
        @token = @engine.select(old_token, tag, mbox_name) {|res|
          ret_val = yield(res)
        }

        ret_val
      end
      imap_command :select

      def examine(tag, mbox_name)
        ret_val = nil
        old_token = @token
        @token = @engine.examine(old_token, tag, mbox_name) {|res|
          ret_val = yield(res)
        }

        ret_val
      end
      imap_command :examine

      def create(tag, mbox_name, &block)
        @engine.create(@token, tag, mbox_name, &block)
      end
      imap_command :create

      def delete(tag, mbox_name, &block)
        @engine.delete(@token, tag, mbox_name, &block)
      end
      imap_command :delete

      def rename(tag, src_name, dst_name, &block)
        @engine.rename(@token, tag, src_name, dst_name, &block)
      end
      imap_command :rename

      def subscribe(tag, mbox_name, &block)
        @engine.subscribe(@token, tag, mbox_name, &block)
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name, &block)
        @engine.unsubscribe(@token, tag, mbox_name, &block)
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name, &block)
        @engine.list(@token, tag, ref_name, mbox_name, &block)
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name, &block)
        @engine.lsub(@token, tag, ref_name, mbox_name, &block)
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group, &block)
        @engine.status(@token, tag, mbox_name, data_item_group, &block)
      end
      imap_command :status

      def append(tag, mbox_name, *opt_args, msg_text, &block)
        @engine.append(@token, tag, mbox_name, *opt_args, msg_text, &block)
      end
      imap_command :append

      def check(tag, &block)
        @engine.check(@token, tag, &block)
      end
      imap_command :check

      def close(tag, &block)
        old_token = @token
        @token = nil

        yield response_stream(tag) {|res|
          @engine.close(old_token, tag) {|bulk_res|
            for r in bulk_res
              res << r
            end
          }
        }
      end
      imap_command :close

      def expunge(tag)
        yield response_stream(tag) {|res|
          @engine.expunge(@token, tag) {|bulk_res|
            for r in bulk_res
              res << r
            end
          }
        }
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false)
        yield response_stream(tag) {|res|
          @engine.search(@token, tag, *cond_args, uid: uid) {|bulk_res|
            for r in bulk_res
              res << r
            end
          }
        }
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false)
        yield response_stream(tag) {|res|
          @engine.fetch(@token, tag, msg_set, data_item_group, uid: uid) {|bulk_res|
            for r in bulk_res
              res << r
            end
          }
        }
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        yield response_stream(tag) {|res|
          @engine.store(@token, tag, msg_set, data_item_name, data_item_value, uid: uid) {|bulk_res|
            for r in bulk_res
              res << r
            end
          }
        }
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false, &block)
        @engine.copy(@token, tag, msg_set, mbox_name, uid: uid, &block)
      end
      imap_command :copy

      def idle(tag, client_input_gets, server_output_write, connection_timer, &block)
        @engine.idle(@token, tag, client_input_gets, server_output_write, connection_timer, &block)
      end
      imap_command :idle
    end

    # alias
    Decoder::Engine = UserMailboxDecoder::Engine

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
        release_engine_cache
        @drb_services = nil unless @drb_services.nil?
        @auth = nil unless @auth.nil?

        unless (@parent_decoder.nil?) then
          @parent_decoder.cleanup
          @parent_decoder = nil
        end

        nil
      end

      def logout(tag)
        @next_decoder = LogoutDecoder.new(self)
        yield(make_logout_response(tag))
      end
      imap_command :logout

      alias standard_capability _capability
      private :standard_capability

      def capability(tag)
        standard_capability(tag) {|res|
          yield res.map{|line|
            if (line.start_with? '* CAPABILITY ') then
              line.strip + " X-RIMS-MAIL-DELIVERY-USER\r\n"
            else
              line
            end
          }
        }
      end
      imap_command :capability

      def make_not_allowed_command_response(tag)
        [ "#{tag} NO not allowed command on mail delivery user\r\n" ]
      end
      private :make_not_allowed_command_response

      def select(tag, mbox_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :select

      def examine(tag, mbox_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :examine

      def create(tag, mbox_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :create

      def delete(tag, mbox_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :delete

      def rename(tag, src_name, dst_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :rename

      def subscribe(tag, mbox_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :status

      def deliver_to_user(tag, username, mbox_name, opt_args, msg_text, engine, res)
        user_decoder = UserMailboxDecoder.new(self, engine, @auth, @logger)
        user_decoder.append(tag, mbox_name, *opt_args, msg_text) {|append_response|
          if (append_response.last.split(' ', 3)[1] == 'OK') then
            @logger.info("message delivery: successed to deliver #{msg_text.bytesize} octets message.")
          else
            @logger.info("message delivery: failed to deliver message.")
          end
          for response_data in append_response
            res << response_data
          end
        }
      end
      private :deliver_to_user

      def append(tag, encoded_mbox_name, *opt_args, msg_text)
        username, mbox_name = self.class.decode_delivery_target_mailbox(encoded_mbox_name)
        @logger.info("message delivery: user #{username}, mailbox #{mbox_name}")

        if (@auth.user? username) then
          if (engine_cached? username) then
            res = []
            engine = engine_cache(username)
            deliver_to_user(tag, username, mbox_name, opt_args, msg_text, engine, res)
          else
            res = response_stream(tag) {|stream_res|
              engine = store_engine_cache(username) {
                self.class.make_engine_and_recovery_if_needed(@drb_services, username, logger: @logger) {|msg| stream_res << msg }
              }
              deliver_to_user(tag, username, mbox_name, opt_args, msg_text, engine, stream_res)
            }
          end
          yield(res)
        else
          @logger.info('message delivery: not found a user.')
          yield([ "#{tag} NO not found a user and couldn't deliver a message to the user's mailbox\r\n" ])
        end
      end
      imap_command :append

      def check(tag)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :check

      def close(tag)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :close

      def expunge(tag)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :copy

      def idle(tag, client_input_gets, server_output_write, connection_timer)
        yield(make_not_allowed_command_response(tag))
      end
      imap_command :idle
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
