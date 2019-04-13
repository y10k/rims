# -*- coding: utf-8 -*-

require 'logger'
require 'net/imap'
require 'time'

module RIMS
  module Protocol
    class Decoder
      def self.new_decoder(*args, **opts)
        InitialDecoder.new(*args, **opts)
      end

      def self.repl(decoder, input, output, logger)
        response_write = proc{|res|
          begin
            last_line = nil
            for data in res
              logger.debug("response data: #{Protocol.io_data_log(data)}") if logger.debug?
              output << data
              last_line = data
            end
            output.flush
            logger.info("server response: #{last_line.strip}")
          rescue
            logger.error('response write error.')
            logger.error($!)
            raise
          end
        }

        decoder.ok_greeting{|res| response_write.call(res) }

        request_reader = Protocol::RequestReader.new(input, output, logger)
        loop do
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
          logger.info("client command: #{tag} #{command}")
          if (logger.debug?) then
            case (command.upcase)
            when 'LOGIN'
              log_opt_args = opt_args.dup
              log_opt_args[-1] = '********'
            else
              log_opt_args = opt_args
            end
            logger.debug("client command parameter: #{log_opt_args.inspect}")
          end

          begin
            case (command.upcase)
            when 'CAPABILITY'
              decoder.capability(tag, *opt_args) {|res| response_write.call(res) }
            when 'NOOP'
              decoder.noop(tag, *opt_args) {|res| response_write.call(res) }
            when 'LOGOUT'
              decoder.logout(tag, *opt_args) {|res| response_write.call(res) }
            when 'AUTHENTICATE'
              decoder.authenticate(tag, input, output, *opt_args) {|res| response_write.call(res) }
            when 'LOGIN'
              decoder.login(tag, *opt_args) {|res| response_write.call(res) }
            when 'SELECT'
              decoder.select(tag, *opt_args) {|res| response_write.call(res) }
            when 'EXAMINE'
              decoder.examine(tag, *opt_args) {|res| response_write.call(res) }
            when 'CREATE'
              decoder.create(tag, *opt_args) {|res| response_write.call(res) }
            when 'DELETE'
              decoder.delete(tag, *opt_args) {|res| response_write.call(res) }
            when 'RENAME'
              decoder.rename(tag, *opt_args) {|res| response_write.call(res) }
            when 'SUBSCRIBE'
              decoder.subscribe(tag, *opt_args) {|res| response_write.call(res) }
            when 'UNSUBSCRIBE'
              decoder.unsubscribe(tag, *opt_args) {|res| response_write.call(res) }
            when 'LIST'
              decoder.list(tag, *opt_args) {|res| response_write.call(res) }
            when 'LSUB'
              decoder.lsub(tag, *opt_args) {|res| response_write.call(res) }
            when 'STATUS'
              decoder.status(tag, *opt_args) {|res| response_write.call(res) }
            when 'APPEND'
              decoder.append(tag, *opt_args) {|res| response_write.call(res) }
            when 'CHECK'
              decoder.check(tag, *opt_args) {|res| response_write.call(res) }
            when 'CLOSE'
              decoder.close(tag, *opt_args) {|res| response_write.call(res) }
            when 'EXPUNGE'
              decoder.expunge(tag, *opt_args) {|res| response_write.call(res) }
            when 'SEARCH'
              decoder.search(tag, *opt_args) {|res| response_write.call(res) }
            when 'FETCH'
              decoder.fetch(tag, *opt_args) {|res| response_write.call(res) }
            when 'STORE'
              decoder.store(tag, *opt_args) {|res| response_write.call(res) }
            when 'COPY'
              decoder.copy(tag, *opt_args) {|res| response_write.call(res) }
            when 'IDLE'
              decoder.idle(tag, input, output, *opt_args) {|res| response_write.call(res) }
            when 'UID'
              unless (opt_args.empty?) then
                uid_command, *uid_args = opt_args
                logger.info("uid command: #{uid_command}")
                logger.debug("uid parameter: #{uid_args}") if logger.debug?
                case (uid_command.upcase)
                when 'SEARCH'
                  decoder.search(tag, *uid_args, uid: true) {|res| response_write.call(res) }
                when 'FETCH'
                  decoder.fetch(tag, *uid_args, uid: true) {|res| response_write.call(res) }
                when 'STORE'
                  decoder.store(tag, *uid_args, uid: true) {|res| response_write.call(res) }
                when 'COPY'
                  decoder.copy(tag, *uid_args, uid: true) {|res| response_write.call(res) }
                else
                  logger.error("unknown uid command: #{uid_command}")
                  response_write.call([ "#{tag} BAD unknown uid command\r\n" ])
                end
              else
                logger.error('empty uid parameter.')
                response_write.call([ "#{tag} BAD empty uid parameter\r\n" ])
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

          if (command.upcase == 'LOGOUT') then
            break
          end

          decoder = decoder.next_decoder
        end

        nil
      ensure
        decoder.cleanup
      end

      def initialize(auth, logger)
        @auth = auth
        @logger = logger
      end

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

      def guard_error(tag, imap_command, *args, **name_args)
        begin
          if (name_args.empty?) then
            __send__(imap_command, tag, *args) {|res| yield(res) }
          else
            __send__(imap_command, tag, *args, **name_args) {|res| yield(res) }
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
        def imap_command(name)
          orig_name = "_#{name}".to_sym
          alias_method orig_name, name
          define_method name, lambda{|tag, *args, **name_args, &block|
            guard_error(tag, orig_name, *args, **name_args, &block)
          }
          name.to_sym
        end
        private :imap_command

        def fetch_mail_store_holder_and_on_demand_recovery(mail_store_pool, username,
                                                           write_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                                                           logger: Logger.new(STDOUT))
          unique_user_id = Authentication.unique_user_id(username)
          logger.debug("unique user ID: #{username} -> #{unique_user_id}") if logger.debug?

          mail_store_holder = mail_store_pool.get(unique_user_id) {
            logger.info("open mail store: #{unique_user_id} [ #{username} ]")
          }

          mail_store_holder.write_synchronize(write_lock_timeout_seconds) {
            if (mail_store_holder.mail_store.abort_transaction?) then
              logger.warn("user data recovery start: #{username}")
              yield("* OK [ALERT] start user data recovery.\r\n")
              mail_store_holder.mail_store.recovery_data(logger: logger).sync
              logger.warn("user data recovery end: #{username}")
              yield("* OK completed user data recovery.\r\n")
            end
          }

          mail_store_holder
        end
      end

      def ok_greeting
        yield([ "* OK RIMS v#{VERSION} IMAP4rev1 service ready.\r\n" ])
      end

      def capability(tag)
        capability_list = %w[ IMAP4rev1 UIDPLUS IDLE ]
        capability_list += @auth.capability.map{|auth_capability| "AUTH=#{auth_capability}" }
        res = []
        res << "* CAPABILITY #{capability_list.join(' ')}\r\n"
        res << "#{tag} OK CAPABILITY completed\r\n"
        yield(res)
      end
      imap_command :capability

      def next_decoder
        self
      end
    end

    class InitialDecoder < Decoder
      def initialize(mail_store_pool, auth, logger,
                     mail_delivery_user: Service::DEFAULT_CONFIG.mail_delivery_user,
                     write_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                     **next_decoder_optional)
        super(auth, logger)
        @next_decoder = self
        @mail_store_pool = mail_store_pool
        @folder = nil
        @auth = auth
        @mail_delivery_user = mail_delivery_user
        @write_lock_timeout_seconds = write_lock_timeout_seconds
        @next_decoder_optional = next_decoder_optional
      end

      attr_reader :next_decoder

      def auth?
        false
      end

      def selected?
        false
      end

      def cleanup
        nil
      end

      def not_authenticated_response(tag)
        [ "#{tag} NO not authenticated\r\n" ]
      end
      private :not_authenticated_response

      def noop(tag)
        yield([ "#{tag} OK NOOP completed\r\n" ])
      end
      imap_command :noop

      def logout(tag)
        cleanup
        res = []
        res << "* BYE server logout\r\n"
        res << "#{tag} OK LOGOUT completed\r\n"
        yield(res)
      end
      imap_command :logout

      def accept_authentication(username)
        cleanup

        case (username)
        when @mail_delivery_user
          @logger.info("mail delivery user: #{username}")
          MailDeliveryDecoder.new(@mail_store_pool, @auth, @logger,
                                  write_lock_timeout_seconds: @write_lock_timeout_seconds,
                                  **@next_decoder_optional)
        else
          mail_store_holder =
            self.class.fetch_mail_store_holder_and_on_demand_recovery(@mail_store_pool, username,
                                                                      write_lock_timeout_seconds: @write_lock_timeout_seconds,
                                                                      logger: @logger) {|msg| yield(msg) }
          UserMailboxDecoder.new(self, mail_store_holder, @auth, @logger,
                                 write_lock_timeout_seconds: @write_lock_timeout_seconds,
                                 **@next_decoder_optional)
        end
      end
      private :accept_authentication

      def authenticate(tag, client_response_input_stream, server_challenge_output_stream,
                       auth_type, inline_client_response_data_base64=nil)
        auth_reader = AuthenticationReader.new(@auth, client_response_input_stream, server_challenge_output_stream, @logger)
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
        yield(not_authenticated_response(tag))
      end
      imap_command :select

      def examine(tag, mbox_name)
        yield(not_authenticated_response(tag))
      end
      imap_command :examine

      def create(tag, mbox_name)
        yield(not_authenticated_response(tag))
      end
      imap_command :create

      def delete(tag, mbox_name)
        yield(not_authenticated_response(tag))
      end
      imap_command :delete

      def rename(tag, src_name, dst_name)
        yield(not_authenticated_response(tag))
      end
      imap_command :rename

      def subscribe(tag, mbox_name)
        yield(not_authenticated_response(tag))
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name)
        yield(not_authenticated_response(tag))
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name)
        yield(not_authenticated_response(tag))
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name)
        yield(not_authenticated_response(tag))
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group)
        yield(not_authenticated_response(tag))
      end
      imap_command :status

      def append(tag, mbox_name, *opt_args, msg_text)
        yield(not_authenticated_response(tag))
      end
      imap_command :append

      def check(tag)
        yield(not_authenticated_response(tag))
      end
      imap_command :check

      def close(tag)
        yield(not_authenticated_response(tag))
      end
      imap_command :close

      def expunge(tag)
        yield(not_authenticated_response(tag))
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false)
        yield(not_authenticated_response(tag))
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false)
        yield(not_authenticated_response(tag))
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        yield(not_authenticated_response(tag))
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false)
        yield(not_authenticated_response(tag))
      end
      imap_command :copy

      def idle(tag, client_input_stream, server_output_stream)
        yield(not_authenticated_response(tag))
      end
      imap_command :idle
    end

    class AuthenticatedDecoder < Decoder
      def authenticate(tag, client_response_input_stream, server_challenge_output_stream,
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
      def initialize(parent_decoder, mail_store_holder, auth, logger,
                     read_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                     write_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                     cleanup_write_lock_timeout_seconds: 1)
        super(auth, logger)
        @parent_decoder = parent_decoder
        @mail_store_holder = mail_store_holder
        @read_lock_timeout_seconds = read_lock_timeout_seconds
        @write_lock_timeout_seconds = write_lock_timeout_seconds
        @cleanup_write_lock_timeout_seconds = cleanup_write_lock_timeout_seconds
        @folder = nil
      end

      def get_mail_store
        @mail_store_holder.mail_store
      end
      private :get_mail_store

      def auth?
        @mail_store_holder != nil
      end

      def selected?
        @folder != nil
      end

      def alive_folder?
        get_mail_store.mbox_name(@folder.mbox_id) != nil
      end
      private :alive_folder?

      def close_folder(&block)
        if (auth? && selected? && alive_folder?) then
          @folder.reload if @folder.updated?
          @folder.close(&block)
          @folder = nil
        end

        nil
      end
      private :close_folder

      def cleanup
        unless (@mail_store_holder.nil?) then
          begin
            @mail_store_holder.write_synchronize(@cleanup_write_lock_timeout_seconds) {
              close_folder
              @mail_store_holder.mail_store.sync
            }
          rescue WriteLockTimeoutError
            @logger.warn("give up to close folder becaue of write-lock timeout over #{@write_lock_timeout_seconds} seconds")
            @folder = nil
          end
          tmp_mail_store_holder = @mail_store_holder
          ReadWriteLock.write_lock_timeout_detach(@cleanup_write_lock_timeout_seconds, @write_lock_timeout_seconds, logger: @logger) {|timeout_seconds|
            tmp_mail_store_holder.return_pool{
              @logger.info("close mail store: #{tmp_mail_store_holder.unique_user_id}")
            }
          }
          @mail_store_holder = nil
        end

        unless (@parent_decoder.nil?) then
          @parent_decoder.cleanup
          @parent_decoder = nil
        end

        nil
      end

      def should_be_alive_folder
        alive_folder? or raise "deleted folder: #{@folder.mbox_id}"
      end
      private :should_be_alive_folder

      def guard_authenticated(tag, imap_command, *args, exclusive: false, **name_args)
        if (auth?) then
          if (exclusive.nil?) then
            guard_error(tag, imap_command, *args, **name_args) {|res|
              yield(res)
            }
          else
            begin
              if (exclusive) then
                @mail_store_holder.write_synchronize(@write_lock_timeout_seconds) {
                  guard_authenticated(tag, imap_command, *args, exclusive: nil, **name_args) {|res|
                    yield(res)
                  }
                }
              else
                @mail_store_holder.read_synchronize(@read_lock_timeout_seconds){
                  guard_authenticated(tag, imap_command, *args, exclusive: nil, **name_args) {|res|
                    yield(res)
                  }
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
        else
          yield([ "#{tag} NO not authenticated\r\n" ])
        end
      end
      private :guard_authenticated

      def guard_selected(tag, imap_command, *args, **name_args)
        if (selected?) then
          guard_authenticated(tag, imap_command, *args, **name_args) {|res|
            yield(res)
          }
        else
          yield([ "#{tag} NO not selected\r\n" ])
        end
      end
      private :guard_selected

      class << self
        def imap_command_authenticated(name, **guard_optional)
          orig_name = "_#{name}".to_sym
          alias_method orig_name, name
          define_method name, lambda{|tag, *args, **name_args, &block|
            guard_authenticated(tag, orig_name, *args, **name_args.merge(guard_optional), &block)
          }
          name.to_sym
        end
        private :imap_command_authenticated

        def imap_command_selected(name, **guard_optional)
          orig_name = "_#{name}".to_sym
          alias_method orig_name, name
          define_method name, lambda{|tag, *args, **name_args, &block|
            guard_selected(tag, orig_name, *args, **name_args.merge(guard_optional), &block)
          }
          name.to_sym
        end
        private :imap_command_selected
      end

      def noop(tag)
        res = []
        if (auth? && selected?) then
          begin
            @mail_store_holder.read_synchronize(@read_lock_timeout_seconds) {
              @folder.server_response_fetch{|r| res << r } if @folder.server_response?
            }
          rescue ReadLockTimeoutError
            @logger.warn("give up to get folder status because of read-lock timeout over #{@read_lock_timeout_seconds} seconds")
          end
        end
        res << "#{tag} OK NOOP completed\r\n"
        yield(res)
      end
      imap_command :noop

      def logout(tag)
        cleanup
        res = []
        res << "* BYE server logout\r\n"
        res << "#{tag} OK LOGOUT completed\r\n"
        yield(res)
      end
      imap_command :logout

      def folder_open_msgs
        all_msgs = get_mail_store.mbox_msg_num(@folder.mbox_id)
        recent_msgs = get_mail_store.mbox_flag_num(@folder.mbox_id, 'recent')
        unseen_msgs = all_msgs - get_mail_store.mbox_flag_num(@folder.mbox_id, 'seen')
        yield("* #{all_msgs} EXISTS\r\n")
        yield("* #{recent_msgs} RECENT\r\n")
        yield("* OK [UNSEEN #{unseen_msgs}]\r\n")
        yield("* OK [UIDVALIDITY #{@folder.mbox_id}]\r\n")
        yield("* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n")
        nil
      end
      private :folder_open_msgs

      def select(tag, mbox_name)
        res = []
        @folder = nil
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
        if (id = get_mail_store.mbox_id(mbox_name_utf8)) then
          @folder = get_mail_store.select_mbox(id)
          folder_open_msgs do |msg|
            res << msg
          end
          res << "#{tag} OK [READ-WRITE] SELECT completed\r\n"
        else
          res << "#{tag} NO not found a mailbox\r\n"
        end
        yield(res)
      end
      imap_command_authenticated :select

      def examine(tag, mbox_name)
        res = []
        @folder = nil
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
        if (id = get_mail_store.mbox_id(mbox_name_utf8)) then
          @folder = get_mail_store.examine_mbox(id)
          folder_open_msgs do |msg|
            res << msg
          end
          res << "#{tag} OK [READ-ONLY] EXAMINE completed\r\n"
        else
          res << "#{tag} NO not found a mailbox\r\n"
        end
        yield(res)
      end
      imap_command_authenticated :examine

      def create(tag, mbox_name)
        res = []
        @folder.server_response_fetch{|r| res << r } if selected?
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
        if (get_mail_store.mbox_id(mbox_name_utf8)) then
          res << "#{tag} NO duplicated mailbox\r\n"
        else
          get_mail_store.add_mbox(mbox_name_utf8)
          res << "#{tag} OK CREATE completed\r\n"
        end
        yield(res)
      end
      imap_command_authenticated :create, exclusive: true

      def delete(tag, mbox_name)
        res = []
        @folder.server_response_fetch{|r| res << r } if selected?
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
        if (id = get_mail_store.mbox_id(mbox_name_utf8)) then
          if (id != get_mail_store.mbox_id('INBOX')) then
            get_mail_store.del_mbox(id)
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

      def rename(tag, src_name, dst_name)
        res = []
        @folder.server_response_fetch{|r| res << r } if selected?
        src_name_utf8 = Net::IMAP.decode_utf7(src_name)
        dst_name_utf8 = Net::IMAP.decode_utf7(dst_name)
        unless (id = get_mail_store.mbox_id(src_name_utf8)) then
          return yield(res << "#{tag} NO not found a mailbox\r\n")
        end
        if (id == get_mail_store.mbox_id('INBOX')) then
          return yield(res << "#{tag} NO not rename inbox\r\n")
        end
        if (get_mail_store.mbox_id(dst_name_utf8)) then
          return yield(res << "#{tag} NO duplicated mailbox\r\n")
        end
        get_mail_store.rename_mbox(id, dst_name_utf8)
        return yield(res << "#{tag} OK RENAME completed\r\n")
      end
      imap_command_authenticated :rename, exclusive: true

      def subscribe(tag, mbox_name)
        res = []
        @folder.server_response_fetch{|r| res << r } if selected?
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
        if (_mbox_id = get_mail_store.mbox_id(mbox_name_utf8)) then
          res << "#{tag} OK SUBSCRIBE completed\r\n"
        else
          res << "#{tag} NO not found a mailbox\r\n"
        end
        yield(res)
      end
      imap_command_authenticated :subscribe

      def unsubscribe(tag, mbox_name)
        res = []
        @folder.server_response_fetch{|r| res << r } if selected?
        if (_mbox_id = get_mail_store.mbox_id(mbox_name)) then
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
        mbox_list = get_mail_store.each_mbox_id.map{|id| [ id, get_mail_store.mbox_name(id) ] }
        mbox_list.keep_if{|id, name| name.start_with? ref_name_utf8 }
        mbox_list.keep_if{|id, name| name[(ref_name_utf8.length)..-1] =~ mbox_filter }

        for id, name_utf8 in mbox_list
          name = Net::IMAP.encode_utf7(name_utf8)
          attrs = '\Noinferiors'
          if (get_mail_store.mbox_flag_num(id, 'recent') > 0) then
            attrs << ' \Marked'
          else
            attrs << ' \Unmarked'
          end
          yield("(#{attrs}) NIL #{Protocol.quote(name)}")
        end

        nil
      end
      private :list_mbox

      def list(tag, ref_name, mbox_name)
        res = []
        @folder.server_response_fetch{|r| res << r } if selected?
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

      def lsub(tag, ref_name, mbox_name)
        res = []
        @folder.server_response_fetch{|r| res << r } if selected?
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

      def status(tag, mbox_name, data_item_group)
        res = []
        @folder.server_response_fetch{|r| res << r } if selected?
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
        if (id = get_mail_store.mbox_id(mbox_name_utf8)) then
          unless ((data_item_group.is_a? Array) && (data_item_group[0] == :group)) then
            raise SyntaxError, 'second arugment is not a group list.'
          end

          values = []
          for item in data_item_group[1..-1]
            case (item.upcase)
            when 'MESSAGES'
              values << 'MESSAGES' << get_mail_store.mbox_msg_num(id)
            when 'RECENT'
              values << 'RECENT' << get_mail_store.mbox_flag_num(id, 'recent')
            when 'UIDNEXT'
              values << 'UIDNEXT' << get_mail_store.uid(id)
            when 'UIDVALIDITY'
              values << 'UIDVALIDITY' << id
            when 'UNSEEN'
              unseen_flags = get_mail_store.mbox_msg_num(id) - get_mail_store.mbox_flag_num(id, 'seen')
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
        all_msgs = get_mail_store.mbox_msg_num(mbox_id)
        recent_msgs = get_mail_store.mbox_flag_num(mbox_id, 'recent')

        f = get_mail_store.examine_mbox(mbox_id)
        begin
          f.server_response_multicast_push("* #{all_msgs} EXISTS\r\n")
          f.server_response_multicast_push("* #{recent_msgs} RECENT\r\n")
        ensure
          f.close
        end

        nil
      end
      private :mailbox_size_server_response_multicast_push

      def append(tag, mbox_name, *opt_args, msg_text)
        res = []
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
        if (mbox_id = get_mail_store.mbox_id(mbox_name_utf8)) then
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

          uid = get_mail_store.add_msg(mbox_id, msg_text, msg_date)
          for flag_name in msg_flags
            get_mail_store.set_msg_flag(mbox_id, uid, flag_name, true)
          end
          mailbox_size_server_response_multicast_push(mbox_id)

          @folder.server_response_fetch{|r| res << r } if selected?
          res << "#{tag} OK [APPENDUID #{mbox_id} #{uid}] APPEND completed\r\n"
        else
          @folder.server_response_fetch{|r| res << r } if selected?
          res << "#{tag} NO [TRYCREATE] not found a mailbox\r\n"
        end
        yield(res)
      end
      imap_command_authenticated :append, exclusive: true

      def check(tag)
        res = []
        @folder.server_response_fetch{|r| res << r }
        get_mail_store.sync
        res << "#{tag} OK CHECK completed\r\n"
        yield(res)
      end
      imap_command_selected :check, exclusive: true

      def close(tag, &block)
        yield response_stream(tag) {|res|
          @folder.server_response_fetch{|r| res << r }
          close_folder do |msg_num|
            r = "* #{msg_num} EXPUNGE\r\n"
            res << r
            @folder.server_response_multicast_push(r)
          end
          get_mail_store.sync
          res << "#{tag} OK CLOSE completed\r\n"
        }
      end
      imap_command_selected :close, exclusive: true

      def expunge(tag)
        return yield([ "#{tag} NO cannot expunge in read-only mode\r\n" ]) if @folder.read_only?
        should_be_alive_folder
        @folder.reload if @folder.updated?

        yield response_stream(tag) {|res|
          @folder.server_response_fetch{|r| res << r }
          @folder.expunge_mbox do |msg_num|
            r = "* #{msg_num} EXPUNGE\r\n"
            res << r
            @folder.server_response_multicast_push(r)
          end
          res << "#{tag} OK EXPUNGE completed\r\n"
        }
      end
      imap_command_selected :expunge, exclusive: true

      def search(tag, *cond_args, uid: false)
        should_be_alive_folder
        @folder.reload if @folder.updated?
        parser = Protocol::SearchParser.new(get_mail_store, @folder)

        if (! cond_args.empty? && cond_args[0].upcase == 'CHARSET') then
          cond_args.shift
          charset_string = cond_args.shift or raise SyntaxError, 'need for a charset string of CHARSET'
          charset_string.is_a? String or raise SyntaxError, "CHARSET charset string expected as <String> but was <#{charset_string.class}>."
          parser.charset = charset_string
        end

        if (cond_args.empty?) then
          raise SyntaxError, 'required search arguments.'
        end

        if (cond_args[0].upcase == 'UID' && cond_args.length >= 2) then
          begin
            msg_set = @folder.parse_msg_set(cond_args[1], uid: true)
            msg_src = @folder.msg_find_all(msg_set, uid: true)
            cond_args.shift(2)
          rescue MessageSetSyntaxError
            msg_src = @folder.each_msg
          end
        else
          begin
            msg_set = @folder.parse_msg_set(cond_args[0], uid: false)
            msg_src = @folder.msg_find_all(msg_set, uid: false)
            cond_args.shift
          rescue MessageSetSyntaxError
            msg_src = @folder.each_msg
          end
        end
        cond = parser.parse(cond_args)

        yield response_stream(tag) {|res|
          @folder.server_response_fetch{|r| res << r }
          res << '* SEARCH'
          for msg in msg_src
            if (cond.call(msg)) then
              if (uid) then
                res << " #{msg.uid}"
              else
                res << " #{msg.num}"
              end
            end
          end
          res << "\r\n"
          res << "#{tag} OK SEARCH completed\r\n"
        }
      end
      imap_command_selected :search

      def fetch(tag, msg_set, data_item_group, uid: false)
        should_be_alive_folder
        @folder.reload if @folder.updated?

        msg_set = @folder.parse_msg_set(msg_set, uid: uid)
        msg_list = @folder.msg_find_all(msg_set, uid: uid)

        unless ((data_item_group.is_a? Array) && data_item_group[0] == :group) then
          data_item_group = [ :group, data_item_group ]
        end
        if (uid) then
          unless (data_item_group.find{|i| (i.is_a? String) && (i.upcase == 'UID') }) then
            data_item_group = [ :group, 'UID' ] + data_item_group[1..-1]
          end
        end

        parser = Protocol::FetchParser.new(get_mail_store, @folder)
        fetch = parser.parse(data_item_group)

        yield response_stream(tag) {|res|
          @folder.server_response_fetch{|r| res << r }
          for msg in msg_list
            res << ('* '.b << msg.num.to_s.b << ' FETCH '.b << fetch.call(msg) << "\r\n".b)
          end
          res << "#{tag} OK FETCH completed\r\n"
        }
      end
      imap_command_selected :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        return yield([ "#{tag} NO cannot store in read-only mode\r\n" ]) if @folder.read_only?
        should_be_alive_folder
        @folder.reload if @folder.updated?

        msg_set = @folder.parse_msg_set(msg_set, uid: uid)
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

        msg_list = @folder.msg_find_all(msg_set, uid: uid)

        for msg in msg_list
          case (action)
          when :flags_replace
            for name in flag_list
              get_mail_store.set_msg_flag(@folder.mbox_id, msg.uid, name, true)
            end
            for name in rest_flag_list
              get_mail_store.set_msg_flag(@folder.mbox_id, msg.uid, name, false)
            end
          when :flags_add
            for name in flag_list
              get_mail_store.set_msg_flag(@folder.mbox_id, msg.uid, name, true)
            end
          when :flags_del
            for name in flag_list
              get_mail_store.set_msg_flag(@folder.mbox_id, msg.uid, name, false)
            end
          else
            raise "internal error: unknown action: #{action}"
          end
        end

        if (is_silent) then
          silent_res = []
          @folder.server_response_fetch{|r| silent_res << r }
          silent_res << "#{tag} OK STORE completed\r\n"
          yield(silent_res)
        else
          yield response_stream(tag) {|res|
            @folder.server_response_fetch{|r| res << r }
            for msg in msg_list
              flag_atom_list = nil

              if (get_mail_store.msg_exist? @folder.mbox_id, msg.uid) then
                flag_atom_list = []
                for name in MailStore::MSG_FLAG_NAMES
                  if (get_mail_store.msg_flag(@folder.mbox_id, msg.uid, name)) then
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
              else
                @logger.warn("not found a message and skipped: uidvalidity(#{@folder.mbox_id}) uid(#{msg.uid})")
              end
            end
            res << "#{tag} OK STORE completed\r\n"
          }
        end
      end
      imap_command_selected :store, exclusive: true

      def copy(tag, msg_set, mbox_name, uid: false)
        should_be_alive_folder
        @folder.reload if @folder.updated?

        res = []
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
        msg_set = @folder.parse_msg_set(msg_set, uid: uid)

        if (mbox_id = get_mail_store.mbox_id(mbox_name_utf8)) then
          msg_list = @folder.msg_find_all(msg_set, uid: uid)

          src_uids = []
          dst_uids = []
          for msg in msg_list
            src_uids << msg.uid
            dst_uids << get_mail_store.copy_msg(msg.uid, @folder.mbox_id, mbox_id)
          end

          if msg_list.size > 0
            mailbox_size_server_response_multicast_push(mbox_id)
            @folder.server_response_fetch{|r| res << r }
            res << "#{tag} OK [COPYUID #{mbox_id} #{src_uids.join(',')} #{dst_uids.join(',')}] COPY completed\r\n"
          else
            @folder.server_response_fetch{|r| res << r }
            res << "#{tag} OK COPY completed\r\n"
          end
        else
          @folder.server_response_fetch{|r| res << r }
          res << "#{tag} NO [TRYCREATE] not found a mailbox\r\n"
        end
        yield(res)
      end
      imap_command_selected :copy, exclusive: true

      def idle(tag, client_input_stream, server_output_stream)
        @logger.info('idle start...')
        server_output_stream.write("+ continue\r\n")
        server_output_stream.flush

        server_response_thread = Thread.new{
          @logger.info('idle server response thread start... ')
          @folder.server_response_idle_wait{|server_response_list|
            for server_response in server_response_list
              @logger.debug("idle server response: #{server_response}") if @logger.debug?
              server_output_stream.write(server_response)
            end
            server_output_stream.flush
          }
          server_output_stream.flush
          @logger.info('idle server response thread terminated.')
        }

        begin
          line = client_input_stream.gets
        ensure
          @folder.server_response_idle_interrupt
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
            @logger.debug("unexpected client response data: #{line}")
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
      def initialize(mail_store_pool, auth, logger,
                     write_lock_timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS,
                     cleanup_write_lock_timeout_seconds: 1,
                     **mailbox_decoder_optional)
        super(auth, logger)
        @mail_store_pool = mail_store_pool
        @auth = auth
        @write_lock_timeout_seconds = write_lock_timeout_seconds
        @cleanup_write_lock_timeout_seconds = cleanup_write_lock_timeout_seconds
        @mailbox_decoder_optional = mailbox_decoder_optional
        @last_user_cache_key_username = nil
        @last_user_cache_value_mail_store_holder = nil
      end

      def user_mail_store_cached?(username)
        @last_user_cache_key_username == username
      end
      private :user_mail_store_cached?

      def fetch_user_mail_store_holder(username)
        unless (user_mail_store_cached? username) then
          release_user_mail_store_holder
          @last_user_cache_value_mail_store_holder = yield
          @last_user_cache_key_username = username
        end
        @last_user_cache_value_mail_store_holder
      end
      private :fetch_user_mail_store_holder

      def release_user_mail_store_holder
        if (@last_user_cache_value_mail_store_holder) then
          mail_store_holder = @last_user_cache_value_mail_store_holder
          @last_user_cache_key_username = nil
          @last_user_cache_value_mail_store_holder = nil
          ReadWriteLock.write_lock_timeout_detach(@cleanup_write_lock_timeout_seconds, @write_lock_timeout_seconds, logger: @logger) {|timeout_seconds|
            mail_store_holder.return_pool{
              @logger.info("close cached mail store to deliver message: #{mail_store_holder.unique_user_id}")
            }
          }
        end
      end
      private :release_user_mail_store_holder

      def auth?
        @mail_store_pool != nil
      end

      def selected?
        false
      end

      def cleanup
        release_user_mail_store_holder
        @mail_store_pool = nil unless @mail_store_pool.nil?
        @auth = nil unless @auth.nil?
        nil
      end

      def logout(tag)
        cleanup
        res = []
        res << "* BYE server logout\r\n"
        res << "#{tag} OK LOGOUT completed\r\n"
        yield(res)
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

      def not_allowed_command_response(tag)
        [ "#{tag} NO not allowed command on mail delivery user\r\n" ]
      end
      private :not_allowed_command_response

      def select(tag, mbox_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :select

      def examine(tag, mbox_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :examine

      def create(tag, mbox_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :create

      def delete(tag, mbox_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :delete

      def rename(tag, src_name, dst_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :rename

      def subscribe(tag, mbox_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :subscribe

      def unsubscribe(tag, mbox_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :unsubscribe

      def list(tag, ref_name, mbox_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :list

      def lsub(tag, ref_name, mbox_name)
        yield(not_allowed_command_response(tag))
      end
      imap_command :lsub

      def status(tag, mbox_name, data_item_group)
        yield(not_allowed_command_response(tag))
      end
      imap_command :status

      def deliver_to_user(tag, username, mbox_name, opt_args, msg_text, mail_store_holder, res)
        user_decoder = UserMailboxDecoder.new(self, mail_store_holder, @auth, @logger,
                                              write_lock_timeout_seconds: @write_lock_timeout_seconds,
                                              cleanup_write_lock_timeout_seconds: @cleanup_write_lock_timeout_seconds,
                                              **@mailbox_decoder_optional)
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
          if (user_mail_store_cached? username) then
            res = []
            mail_store_holder = fetch_user_mail_store_holder(username)
            deliver_to_user(tag, username, mbox_name, opt_args, msg_text, mail_store_holder, res)
          else
            res = Enumerator.new{|stream_res|
              mail_store_holder = fetch_user_mail_store_holder(username) {
                self.class.fetch_mail_store_holder_and_on_demand_recovery(@mail_store_pool, username,
                                                                          write_lock_timeout_seconds: @write_lock_timeout_seconds,
                                                                          logger: @logger) {|msg| stream_res << msg }
              }
              deliver_to_user(tag, username, mbox_name, opt_args, msg_text, mail_store_holder, stream_res)
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
        yield(not_allowed_command_response(tag))
      end
      imap_command :check

      def close(tag)
        yield(not_allowed_command_response(tag))
      end
      imap_command :close

      def expunge(tag)
        yield(not_allowed_command_response(tag))
      end
      imap_command :expunge

      def search(tag, *cond_args, uid: false)
        yield(not_allowed_command_response(tag))
      end
      imap_command :search

      def fetch(tag, msg_set, data_item_group, uid: false)
        yield(not_allowed_command_response(tag))
      end
      imap_command :fetch

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        yield(not_allowed_command_response(tag))
      end
      imap_command :store

      def copy(tag, msg_set, mbox_name, uid: false)
        yield(not_allowed_command_response(tag))
      end
      imap_command :copy

      def idle(tag, client_input_stream, server_output_stream)
        yield(not_allowed_command_response(tag))
      end
      imap_command :idle
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
