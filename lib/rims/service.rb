# -*- coding: utf-8 -*-

require 'etc'
require 'json'
require 'logger'
require 'logger/joint'
require 'pathname'
require 'riser'
require 'socket'
require 'yaml'

module RIMS
  class Service
    class Configuration
      class << self
        def stringify_symbol(collection)
          case (collection)
          when Hash
            Hash[collection.map{|key, value| [ stringify_symbol(key), stringify_symbol(value) ] }]
          when Array
            collection.map{|i| stringify_symbol(i) }
          else
            case (value = collection)
            when Symbol
              value.to_s
            else
              value
            end
          end
        end

        def update(dest, other)
          case (dest)
          when Hash
            unless (other.is_a? Hash) then
              raise ArgumentError, 'hash can only be updated with hash.'
            end
            for key, value in other
              dest[key] = update(dest[key], value)
            end
            dest
          when Array
            if (other.is_a? Array) then
              dest.concat(other)
            else
              other
            end
          else
            other
          end
        end

        def get_configuration(collection, base_dir)
          if ((collection.key? 'configuration') && (collection.key? 'configuration_file')) then
            raise KeyError, 'configuration conflict: configuration, configuraion_file'
          end

          if (collection.key? 'configuration') then
            collection['configuration']
          elsif (collection.key? 'configuration_file') then
            configuration_file_path = Pathname(collection['configuration_file'])
            if (configuration_file_path.relative?) then
              configuration_file_path = base_dir + configuration_file_path # expect base_dir to be Pathname
            end
            YAML.load_file(configuration_file_path.to_s)
          else
            {}
          end
        end
      end

      def initialize
        @config = {}
      end

      def load(config, load_path=nil)
        stringified_config = self.class.stringify_symbol(config)
        if (stringified_config.key? 'base_dir') then
          base_dir = Pathname(stringified_config['base_dir'])
          if (load_path && base_dir.relative?) then
            stringified_config['base_dir'] = Pathname(load_path) + base_dir
          else
            stringified_config['base_dir'] = base_dir
          end
        elsif (load_path) then
          stringified_config['base_dir'] = Pathname(load_path)
        end
        self.class.update(@config, stringified_config)

        self
      end

      # configuration example.
      #   required_features:
      #     - rims/qdbm
      #     - rims/passwd/ldap
      #   logging:
      #     file:
      #       path: rims.log
      #       shift_age: 10
      #       shift_size: 1048576
      #       level: debug
      #       datetime_format: %Y-%m-%d %H:%M:%S
      #       shift_period_suffix: %Y%m%d
      #     stdout:
      #       level: info
      #       datetime_format: %Y-%m-%d %H:%M:%S
      #     protocol:
      #       # default is not output.
      #       # to output, set the log level to info or less.
      #       path: protocol.log
      #       shift_age: 10
      #       shift_size: 1048576
      #       level: info
      #       datetime_format: %Y-%m-%d %H:%M:%S
      #       shift_period_suffix: %Y%m%d
      #   daemon:
      #     daemonize: true
      #     debug: false
      #     status_file: rims.pid
      #     server_polling_interval_seconds: 3
      #     server_privileged_user: nobody
      #     server_privileged_group: nouser
      #   server:
      #     listen_address:
      #       # see `Riser::SocketAddress.parse' for address format
      #       type: tcp
      #       host: 0.0.0.0
      #       port: 143
      #       backlog: 64
      #     accept_polling_timeout_seconds: 0.1
      #     thread_num: 20
      #     thread_queue_size: 20
      #     thread_queue_polling_timeout_seconds: 0.1
      #     send_buffer_limit_size: 16384
      #   openssl:
      #     use_ssl: true
      #     ssl_context: |
      #       # this entry is evaluated in an anonymous ruby ​​module
      #       # including OpenSSL to initialize the SSLContext used
      #       # for TLS connection.
      #       # SSLContext object is stored at `_'.
      #       # Pathname object is stored at `base_dir'.
      #       _.cert = X509::Certificate.new((base_dir / "tls_cert" / "server_default.cert").read)
      #       _.key = PKey.read((base_dir / "tls_secret" / "server.priv_key").read)
      #       sni_tbl = {
      #         "imap.example.com"  => SSLContext.new.tap{|c| c.key = _.key; c.cert = X509::Certificate.new((base_dir / "tls_cert" / "server_imap.cert").read) },
      #         "imap2.example.com" => SSLContext.new.tap{|c| c.key = _.key; c.cert = X509::Certificate.new((base_dir / "tls_cert" / "server_imap2.cert").read) },
      #         "imap3.example.com" => SSLContext.new.tap{|c| c.key = _.key; c.cert = X509::Certificate.new((base_dir / "tls_cert" / "server_imap3.cert").read) }
      #       }
      #       _.servername_cb = lambda{|ssl_socket, hostname| sni_tbl[hostname.downcase] }
      #   lock:
      #     read_lock_timeout_seconds: 30
      #     write_lock_timeout_seconds: 30
      #     cleanup_write_lock_timeout_seconds: 1
      #   storage:
      #     meta_key_value_store:
      #       type: qdbm_depot
      #       configuration:
      #         bnum 1200000
      #       use_checksum: true
      #     text_key_value_store:
      #       type: qdbm_curia
      #       configuration_file: text_kvs_config.yml
      #       use_checksum: true
      #   authentication:
      #     hostname: imap.example.com
      #     password_sources:
      #       - type: plain
      #         configuration:
      #           - user: alice
      #             pass: open sesame
      #           - user: bob
      #             pass: Z1ON0101
      #       - type: hash
      #         configuration_file: passwd_hash.yml
      #       - type: ldap
      #         configuration:
      #           ldap_uri: ldap://ldap.example.com/ou=user,o=example,dc=nodomain?uid?one?(memberOf=cn=imap,ou=group,o=example,dc=nodomain)
      #   authorization:
      #     mail_delivery_user: "#postman"
      def load_yaml(path)
        load(YAML.load_file(path), File.dirname(path))
        self
      end

      def require_features
        # built-in plug-in
        require 'rims/gdbm_kvs'
        require 'rims/passwd'

        if (feature_list = @config.dig('required_features')) then
          for feature in feature_list
            require(feature)
          end
        end

        nil
      end

      def get_required_features
        @config.dig('required_features') || []
      end

      def base_dir
        @config['base_dir'] or raise KeyError, 'not defined base_dir.'
      end

      def get_configuration(collection)
        self.class.get_configuration(collection, base_dir)
      end
      private :get_configuration

      # return parameters for Logger.new
      def make_file_logger_params
        log_path = Pathname(@config.dig('logging', 'file', 'path') || 'rims.log')
        if (log_path.relative?) then
          log_path = base_dir + log_path
        end
        logger_params = [ log_path.to_s ]

        shift_age = @config.dig('logging', 'file', 'shift_age')
        shift_size = @config.dig('logging', 'file', 'shift_size')
        if (shift_size) then
          logger_params << (shift_age || 0)
          logger_params << shift_size
        elsif (shift_age) then
          logger_params << shift_age
        end

        kw_args = {}
        kw_args[:level] = @config.dig('logging', 'file', 'level') || 'info'
        kw_args[:progname] = 'rims'
        if (datetime_format = @config.dig('logging', 'file', 'datetime_format')) then
          kw_args[:datetime_format] = datetime_format
        end
        if (shift_period_suffix = @config.dig('logging', 'file', 'shift_period_suffix')) then
          kw_args[:shift_period_suffix] = shift_period_suffix
        end
        logger_params << kw_args

        logger_params
      end

      # return parameters for Logger.new
      def make_stdout_logger_params
        logger_params = [ STDOUT ]

        kw_args = {}
        kw_args[:level] = @config.dig('logging', 'stdout', 'level') || 'info'
        kw_args[:progname] = 'rims'
        if (datetime_format = @config.dig('logging', 'stdout', 'datetime_format')) then
          kw_args[:datetime_format] = datetime_format
        end
        logger_params << kw_args

        logger_params
      end

      # return parameters for Logger.new
      def make_protocol_logger_params
        log_path = Pathname(@config.dig('logging', 'protocol', 'path') || 'protocol.log')
        if (log_path.relative?) then
          log_path = base_dir + log_path
        end
        logger_params = [ log_path.to_s ]

        shift_age = @config.dig('logging', 'protocol', 'shift_age')
        shift_size = @config.dig('logging', 'protocol', 'shift_size')
        if (shift_size) then
          logger_params << (shift_age || 0)
          logger_params << shift_size
        elsif (shift_age) then
          logger_params << shift_age
        end

        kw_args = {}
        kw_args[:level] = @config.dig('logging', 'protocol', 'level') || 'unknown'
        kw_args[:progname] = 'rims'
        if (datetime_format = @config.dig('logging', 'protocol', 'datetime_format')) then
          kw_args[:datetime_format] = datetime_format
        end
        if (shift_period_suffix = @config.dig('logging', 'protocol', 'shift_period_suffix')) then
          kw_args[:shift_period_suffix] = shift_period_suffix
        end
        logger_params << kw_args

        logger_params
      end

      def daemonize?
        daemon_config = @config['daemon'] || {}
        if (daemon_config.key? 'daemonize') then
          daemon_config['daemonize']
        else
          true
        end
      end

      def daemon_debug?
        daemon_config = @config['daemon'] || {}
        if (daemon_config.key? 'debug') then
          daemon_config['debug']
        else
          false
        end
      end

      def status_file
        file_path = @config.dig('daemon', 'status_file') || 'rims.pid'
        file_path = Pathname(file_path)
        if (file_path.relative?) then
          file_path = base_dir + file_path
        end
        file_path.to_path
      end

      def server_polling_interval_seconds
        @config.dig('daemon', 'server_polling_interval_seconds') || 3
      end

      def server_restart_overlap_seconds
        # to avoid resource conflict between the new server and the old server.
        0
      end

      def server_privileged_user
        @config.dig('daemon', 'server_privileged_user')
      end

      def server_privileged_group
        @config.dig('daemon', 'server_privileged_group')
      end

      def listen_address
        @config.dig('server', 'listen_address') || '0.0.0.0:1430'
      end

      def accept_polling_timeout_seconds
        @config.dig('server', 'accept_polling_timeout_seconds') || 0.1
      end

      def process_num
        # not yet supported multi-process server configuration.
        0
      end

      def process_queue_size
        20
      end

      def process_queue_polling_timeout_seconds
        0.1
      end

      def process_send_io_polling_timeout_seconds
        0.1
      end

      def thread_num
        @config.dig('server', 'thread_num') || 20
      end

      def thread_queue_size
        @config.dig('server', 'thread_queue_size') || 20
      end

      def thread_queue_polling_timeout_seconds
        @config.dig('server', 'thread_queue_polling_timeout_seconds') || 0.1
      end

      def send_buffer_limit_size
        @config.dig('server', 'send_buffer_limit_size') || 1024 * 16
      end

      module SSLContextConfigAttribute
        def ssl_context
          @__ssl_context__
        end

        def base_dir
          @__base_dir__
        end

        alias _ ssl_context

        class << self
          def new_module(ssl_context, base_dir)
            _module = Module.new
            _module.instance_variable_set(:@__ssl_context__, ssl_context)
            _module.instance_variable_set(:@__base_dir__, base_dir)
            _module.module_eval{
              include OpenSSL
              include OpenSSL::SSL
              extend SSLContextConfigAttribute
            }
            _module
          end

          # methodized to isolate local variable scope.
          def eval_config(_module, expr, filename='(eval_config)')
            _module.module_eval(expr, filename)
          end
        end
      end

      def ssl_context
        if (openssl_config = @config['openssl']) then
          if (openssl_config.key? 'use_ssl') then
            use_ssl = openssl_config['use_ssl']
          else
            use_ssl = openssl_config.key? 'ssl_context'
          end

          if (use_ssl) then
            ssl_context = OpenSSL::SSL::SSLContext.new
            if (ssl_config_expr = openssl_config['ssl_context']) then
              anon_mod = SSLContextConfigAttribute.new_module(ssl_context, base_dir)
              SSLContextConfigAttribute.eval_config(anon_mod, ssl_config_expr, 'ssl_context')
            end

            ssl_context
          end
        end
      end

      def read_lock_timeout_seconds
        @config.dig('lock', 'read_lock_timeout_seconds') || 30
      end

      def write_lock_timeout_seconds
        @config.dig('lock', 'write_lock_timeout_seconds') || 30
      end

      def cleanup_write_lock_timeout_seconds
        @config.dig('lock', 'cleanup_write_lock_timeout_seconds') || 1
      end

      KeyValueStoreFactoryBuilderParams = Struct.new(:origin_type, :origin_config, :middleware_list)
      class KeyValueStoreFactoryBuilderParams
        def build_factory
          builder = KeyValueStore::FactoryBuilder.new
          builder.open{|name| origin_type.open_with_conf(name, origin_config) }
          for middleware in middleware_list
            builder.use(middleware)
          end
          builder.factory
        end
      end

      def make_key_value_store_params(collection)
        kvs_params = KeyValueStoreFactoryBuilderParams.new
        kvs_params.origin_type = KeyValueStore::FactoryBuilder.get_plug_in(collection['type'] || 'gdbm')
        kvs_params.origin_config = get_configuration(collection)

        if (collection.key? 'use_checksum') then
          use_checksum = collection['use_checksum']
        else
          use_checksum = true   # default
        end

        kvs_params.middleware_list = []
        kvs_params.middleware_list << Checksum_KeyValueStore if use_checksum

        kvs_params
      end
      private :make_key_value_store_params

      def make_meta_key_value_store_params
        make_key_value_store_params(@config.dig('storage', 'meta_key_value_store') || {})
      end

      def make_text_key_value_store_params
        make_key_value_store_params(@config.dig('storage', 'text_key_value_store') || {})
      end

      def make_key_value_store_path(mailbox_data_structure_version, unique_user_id)
        if (mailbox_data_structure_version.empty?) then
          raise ArgumentError, 'too short mailbox data structure version.'
        end
        if (unique_user_id.length <= 2) then
          raise ArgumentError, 'too short unique user ID.'
        end

        bucket_dir_name = unique_user_id[0..1]
        store_dir_name = unique_user_id[2..-1]

        base_dir + mailbox_data_structure_version + bucket_dir_name + store_dir_name
      end

      def make_authentication
        hostname = @config.dig('authentication', 'hostname') || Socket.gethostname
        auth = Authentication.new(hostname: hostname)

        if (passwd_src_list = @config.dig('authentication', 'password_sources')) then
          for passwd_src_conf in passwd_src_list
            plug_in_name = passwd_src_conf['type'] or raise KeyError, 'not found a password source type.'
            plug_in_config = get_configuration(passwd_src_conf)
            passwd_src = Authentication.get_plug_in(plug_in_name, plug_in_config)
            auth.add_plug_in(passwd_src)
          end
        end

        auth
      end

      def mail_delivery_user
        @config.dig('authorization', 'mail_delivery_user') || '#postman'
      end
    end

    def initialize(config)
      @config = config
    end

    using Logger::JointPlus

    def setup(server)
      Riser.preload
      Riser.preload(RIMS)
      Riser.preload(RIMS::Protocol)

      @config.require_features

      file_logger_params = @config.make_file_logger_params
      logger = Logger.new(*file_logger_params)

      stdout_logger_params = @config.make_stdout_logger_params
      logger += Logger.new(*stdout_logger_params)

      server.accept_polling_timeout_seconds          = @config.accept_polling_timeout_seconds
      server.process_num                             = @config.process_num
      server.process_queue_size                      = @config.process_queue_size
      server.process_queue_polling_timeout_seconds   = @config.process_queue_polling_timeout_seconds
      server.process_send_io_polling_timeout_seconds = @config.process_send_io_polling_timeout_seconds
      server.thread_num                              = @config.thread_num
      server.thread_queue_size                       = @config.thread_queue_size
      server.thread_queue_polling_timeout_seconds    = @config.thread_queue_polling_timeout_seconds

      ssl_context = @config.ssl_context

      make_kvs_factory = lambda{|kvs_params, kvs_type|
        kvs_factory = kvs_params.build_factory
        return lambda{|mailbox_data_structure_version, unique_user_id, db_name|
          kvs_path = @config.make_key_value_store_path(mailbox_data_structure_version, unique_user_id)
          unless (kvs_path.directory?) then
            logger.debug("make a directory: #{kvs_path}") if logger.debug?
            kvs_path.mkpath
          end
          db_path = kvs_path + db_name
          logger.debug("#{kvs_type} data key-value sotre path: #{db_path}") if logger.debug?
          kvs_factory.call(db_path.to_s)
        }, lambda{
          logger.info("#{kvs_type} key-value store parameter: type=#{kvs_params.origin_type}")
          logger.info("#{kvs_type} key-value store parameter: config=#{kvs_params.origin_config.to_json}")
          kvs_params.middleware_list.each_with_index do |middleware, i|
            logger.info("#{kvs_type} key-value store parameter: middleware[#{i}]=#{middleware}")
          end
        }
      }

      kvs_meta_open, kvs_meta_log = make_kvs_factory.call(@config.make_meta_key_value_store_params, 'meta')
      kvs_text_open, kvs_text_log = make_kvs_factory.call(@config.make_text_key_value_store_params, 'text')
      auth = @config.make_authentication
      mail_store_pool = MailStore.build_pool(kvs_meta_open, kvs_text_open)

      server.before_start{|server_socket|
        logger.info('start server.')
        for feature in @config.get_required_features
          logger.info("required feature: #{feature}")
        end
        logger.info("file logging parameter: path=#{file_logger_params[0]}")
        file_logger_params[1..-2].each_with_index do |value, i|
          logger.info("file logging parameter: shift_args[#{i}]=#{value}")
        end
        for name, value in file_logger_params[-1]
          logger.info("file logging parameter: #{name}=#{value}")
        end
        for name, value in stdout_logger_params[-1]
          logger.info("stdout logging parameter: #{name}=#{value}")
        end
        logger.info("listen address: #{server_socket.local_address.inspect_sockaddr}")
        privileged_user = Etc.getpwuid(Process.euid).name rescue ''
        logger.info("server privileged user: #{privileged_user}(#{Process.euid})")
        privileged_group = Etc.getgrgid(Process.egid).name rescue ''
        logger.info("server privileged group: #{privileged_group}(#{Process.egid})")
        logger.info("server parameter: accept_polling_timeout_seconds=#{server.accept_polling_timeout_seconds}")
        logger.info("server parameter: process_num=#{server.process_num}")
        logger.info("server parameter: process_queue_size=#{server.process_queue_size}")
        logger.info("server parameter: process_queue_polling_timeout_seconds=#{server.process_queue_polling_timeout_seconds}")
        logger.info("server parameter: process_send_io_polling_timeout_seconds=#{server.process_send_io_polling_timeout_seconds}")
        logger.info("server parameter: thread_num=#{server.thread_num}")
        logger.info("server parameter: thread_queue_size=#{server.thread_queue_size}")
        logger.info("server parameter: thread_queue_polling_timeout_seconds=#{server.thread_queue_polling_timeout_seconds}")
        logger.info("server parameter: send_buffer_limit_size=#{@config.send_buffer_limit_size}")
        if (ssl_context) then
          Array(ssl_context.alpn_protocols).each_with_index do |protocol, i|
            logger.info("openssl parameter: alpn_protocols[#{i}]=#{protocol}")
          end
          logger.info("openssl parameter: alpn_select_cb=#{ssl_context.alpn_select_cb.inspect}") if ssl_context.alpn_select_cb
          logger.info("openssl parameter: ca_file=#{ssl_context.ca_file}") if ssl_context.ca_file
          logger.info("openssl parameter: ca_path=#{ssl_context.ca_path}") if ssl_context.ca_path
          if (ssl_context.cert) then
            ssl_context.cert.to_text.each_line do |line|
              logger.info("openssl parameter: [cert] #{line.chomp}")
            end
          else
            logger.warn('openssl parameter: not defined cert attribute.')
          end
          logger.info("openssl parameter: cert_store=#{ssl_context.cert_store.inspect}") if ssl_context.cert_store
          Array(ssl_context.ciphers).each_with_index do |cipher, i|
            logger.info("openssl parameter: ciphers[#{i}]=#{cipher.join(',')}")
          end
          Array(ssl_context.client_ca).each_with_index do |cert, i|
            cert.to_text.each_line do |line|
              logger.info("openssl parameter: client_ca[#{i}]: #{line.chomp}")
            end
          end
          logger.info("openssl parameter: client_cert_cb=#{ssl_context.client_cert_cb.inspect}") if ssl_context.client_cert_cb
          Array(ssl_context.extra_chain_cert).each_with_index do |cert, i|
            cert.to_text.each_line do |line|
              logger.info("openssl parameter: extra_chain_cert[#{i}]: #{line.chomp}")
            end
          end
          if (ssl_context.key) then
            logger.info("openssl parameter: key=#{ssl_context.key.inspect}")
            if (logger.debug?) then
              ssl_context.key.to_text.each_line do |line|
                logger.debug("openssl parameter: [key] #{line.chomp}")
              end
            end
          else
            logger.warn('openssl parameter: not defined key attribute.')
          end
          Array(ssl_context.npn_protocols).each_with_index do |protocol, i|
            logger.info("openssl parameter: npn_protocols[#{i}]=#{protocol}")
          end
          logger.info("openssl parameter: npn_select_cb=#{ssl_context.npn_select_cb.inspect}") if ssl_context.npn_select_cb
          logger.info("openssl parameter: options=0x#{'%08x' % ssl_context.options}") if ssl_context.options
          logger.info("openssl parameter: renegotiation_cb=#{ssl_context.renegotiation_cb.inspect}") if ssl_context.renegotiation_cb
          logger.info("openssl parameter: security_level=#{ssl_context.security_level}")
          logger.info("openssl parameter: servername_cb=#{ssl_context.servername_cb.inspect}") if ssl_context.servername_cb
          logger.info("openssl parameter: session_cache_mode=0x#{'%08x' % ssl_context.session_cache_mode}")
          logger.info("openssl parameter: session_cache_size=#{ssl_context.session_cache_size }")
          logger.info("openssl parameter: session_get_cb=#{ssl_context.session_get_cb.inspect}") if ssl_context.session_get_cb
          logger.info("openssl parameter: session_id_context=#{ssl_context.session_id_context}") if ssl_context.session_id_context
          logger.info("openssl parameter: session_new_cb=#{ssl_context.session_new_cb.inspect}") if ssl_context.session_new_cb
          logger.info("openssl parameter: session_remove_cb=#{ssl_context.session_remove_cb}") if ssl_context.session_remove_cb
          logger.info("openssl parameter: ssl_timeout=#{ssl_context.ssl_timeout}") if ssl_context.ssl_timeout
          logger.info("openssl parameter: tmp_dh_callback=#{ssl_context.tmp_dh_callback}") if ssl_context.tmp_dh_callback
          logger.info("openssl parameter: verify_callback=#{ssl_context.verify_callback}") if ssl_context.verify_callback
          logger.info("openssl parameter: verify_depth=#{ssl_context.verify_depth}") if ssl_context.verify_depth
          logger.info("openssl parameter: verify_hostname=#{ssl_context.verify_hostname}") if ssl_context.verify_hostname
          logger.info("openssl parameter: verify_mode=0x#{'%08x' % ssl_context.verify_mode}") if ssl_context.verify_mode
        end
        logger.info("lock parameter: read_lock_timeout_seconds=#{@config.read_lock_timeout_seconds}")
        logger.info("lock parameter: write_lock_timeout_seconds=#{@config.write_lock_timeout_seconds}")
        logger.info("lock parameter: cleanup_write_lock_timeout_seconds=#{@config.cleanup_write_lock_timeout_seconds}")
        kvs_meta_log.call
        kvs_text_log.call
        logger.info("authentication parameter: hostname=#{auth.hostname}")
        logger.info("authorization parameter: mail_delivery_user=#{@config.mail_delivery_user}")
      }
      # server.at_fork{}
      # server.at_stop{}
      server.at_stat{|info|
        logger.info("stat: #{info.to_json}")
      }
      server.preprocess{
        auth.start_plug_in(logger)
      }
      server.dispatch{|socket|
        begin
          logger.info("accept connection: #{socket.remote_address.inspect_sockaddr}")
          if (ssl_context) then
            ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
            logger.info("start tls: #{ssl_socket.state}")
            ssl_socket.accept
            logger.info("accept tls: #{ssl_socket.state}")
            ssl_socket.sync = true
            input = ssl_socket
            output = Riser::WriteBufferStream.new(ssl_socket, @config.send_buffer_limit_size)
          else
            input = socket
            output = Riser::WriteBufferStream.new(socket, @config.send_buffer_limit_size)
          end
          decoder = Protocol::Decoder.new_decoder(mail_store_pool, auth, logger,
                                                  mail_delivery_user: @config.mail_delivery_user,
                                                  read_lock_timeout_seconds: @config.read_lock_timeout_seconds,
                                                  write_lock_timeout_seconds: @config.write_lock_timeout_seconds,
                                                  cleanup_write_lock_timeout_seconds: @config.cleanup_write_lock_timeout_seconds)
          Protocol::Decoder.repl(decoder, input, output, logger)
        rescue
          logger.error('interrupt connection with unexpected error.')
          logger.error($!)
        ensure
          Error.suppress_2nd_error_at_resource_closing(logger: logger) {
            output.flush
          }
          if (ssl_context) then
            Error.suppress_2nd_error_at_resource_closing(logger: logger) {
              ssl_socket.close
              logger.info("close tls: #{ssl_socket.state}")
            }
          end
          Error.suppress_2nd_error_at_resource_closing(logger: logger) {
            remote_address = socket.remote_address
            socket.close
            logger.info("close connection: #{remote_address.inspect_sockaddr}")
          }
        end
      }
      server.postprocess{
        auth.stop_plug_in(logger)
      }
      server.after_stop{
        logger.info('stop server.')
      }

      nil
    end
  end
end

if ($0 == __FILE__) then
  require 'pp' if $DEBUG
  require 'rims'

  if (ARGV.length != 1) then
    STDERR.puts "usage: #{$0} config.yml"
    exit(1)
  end

  config = RIMS::Service::Configuration.new
  config.load_yaml(ARGV[0])
  pp config if $DEBUG

  server = Riser::SocketServer.new
  service = RIMS::Service.new(config)
  service.setup(server)

  Signal.trap(:INT) { server.signal_stop_forced }
  Signal.trap(:TERM) { server.signal_stop_graceful }

  listen_address = Riser::SocketAddress.parse(config.listen_address)
  server.start(listen_address.open_server)
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
