# -*- coding: utf-8 -*-

require 'etc'
require 'forwardable'
require 'logger'
require 'pathname'
require 'socket'
require 'yaml'

module RIMS
  class Multiplexor
    def initialize
      @obj_list = []
    end

    def add(object)
      @obj_list << object
      self
    end

    def method_missing(id, *args)
      for object in @obj_list
        r = object.__send__(id, *args)
      end
      r
    end
  end

  class Config
    extend Forwardable

    def self.relative_path?(path)
      Pathname.new(path).relative?
    end

    def_delegator 'self.class', :relative_path?
    private :relative_path?

    def initialize
      @config = {}
    end

    def load(config)
      @config.update(config)
      self
    end

    def load_config_yaml(path)
      load_config_from_base_dir(YAML.load_file(path), File.dirname(path))
    end

    def load_config_from_base_dir(config, base_dir)
      @config[:base_dir] = base_dir
      for name, value in config
        case (key_sym = name.to_sym)
        when :base_dir
          if (relative_path? value) then
            @config[:base_dir] = File.join(base_dir, value)
          else
            @config[:base_dir] = value
          end
        else
          @config[key_sym] = value
        end
      end
      self
    end

    # configuration entries.
    # * <tt>:base_dir</tt>
    #
    def base_dir
      @config[:base_dir] or raise 'not defined configuration entry: base_dir'
    end

    def through_server_params
      params = @config.dup
      params.delete(:base_dir)
      params
    end

    def setup_backward_compatibility
      [ [ :imap_host, :ip_addr ],
        [ :imap_port, :ip_port ]
      ].each do |new_namme, old_name|
        unless (@config.key? new_namme) then
          if (@config.key? old_name) then
            warn("warning: `#{old_name}' is obsoleted server configuration parameter and should be replaced to new parameter of `#{new_namme}'.")
            @config[new_namme] = @config.delete(old_name)
          end
        end
      end

      self
    end

    # configuration entry.
    # * <tt>load_libraries</tt>
    def setup_load_libraries
      lib_list = @config.delete(:load_libraries) || []
      for lib in lib_list
        require(lib)
      end
    end

    # configuration entries.
    # * <tt>:log_file</tt>
    # * <tt>:log_level</tt>
    # * <tt>:log_shift_age</tt>
    # * <tt>:log_shift_size</tt>
    # * <tt>:log_stdout</tt>
    #
    def logging_params
      log_file = @config.delete(:log_file) || Server::DEFAULT[:log_file]
      if (relative_path? log_file) then
        log_file_path = File.join(base_dir, log_file)
      else
        log_file_path = log_file
      end

      log_level = @config.delete(:log_level) || Server::DEFAULT[:log_level]
      log_level = log_level.upcase
      case (log_level)
      when 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'
        log_level = Logger.const_get(log_level)
      else
        raise "unknown log level of logfile: #{log_level}"
      end

      log_stdout = @config.delete(:log_stdout) || Server::DEFAULT[:log_stdout]
      log_stdout = log_stdout.upcase
      case (log_stdout)
      when 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'
        log_stdout = Logger.const_get(log_stdout)
      when 'QUIET'
        log_stdout = nil
      else
        raise "unknown log level of stdout: #{log_stdout}"
      end

      log_opt_args = []
      if (@config.key? :log_shift_age) then
        log_opt_args << @config.delete(:log_shift_age)
        log_opt_args << @config.delete(:log_shift_size) if (@config.key? :log_shift_size)
      else
        log_opt_args << 1 <<  @config.delete(:log_shift_size) if (@config.key? :log_shift_size)
      end

      { log_file: log_file_path,
        log_level: log_level,
        log_opt_args: log_opt_args,
        log_stdout: log_stdout
      }
    end

    def build_logger
      c = logging_params
      logger = Multiplexor.new

      if (c[:log_stdout]) then
        stdout_logger = Logger.new(STDOUT)
        stdout_logger.level = c[:log_stdout]
        logger.add(stdout_logger)
      end

      file_logger = Logger.new(c[:log_file], *c[:log_opt_args])
      file_logger.level = c[:log_level]
      logger.add(file_logger)

      logger
    end

    # configuration entries.
    # * <tt>:key_value_store_type</tt>
    # * <tt>:use_key_value_store_checksum</tt>
    #
    def key_value_store_params
      kvs_type = (@config.delete(:key_value_store_type) || Server::DEFAULT[:key_value_store_type]).upcase
      case (kvs_type)
      when 'GDBM'
        origin_key_value_store = GDBM_KeyValueStore
      else
        raise "unknown key-value store type: #{kvs_type}"
      end

      middleware_key_value_store_list = []
      if ((@config.key? :use_key_value_store_checksum) ? @config.delete(:use_key_value_store_checksum) : Server::DEFAULT[:use_key_value_store_checksum]) then
        middleware_key_value_store_list << Checksum_KeyValueStore
      end

      { origin_key_value_store: origin_key_value_store,
        middleware_key_value_store_list: middleware_key_value_store_list
      }
    end

    def build_key_value_store_factory
      c = key_value_store_params
      builder = KeyValueStore::FactoryBuilder.new
      builder.open{|name| c[:origin_key_value_store].open(name) }
      for middleware_key_value_store in c[:middleware_key_value_store_list]
        builder.use(middleware_key_value_store)
      end
      builder.factory
    end

    class << self
      def mkdir_from_base_dir(base_dir, path_name_list)
        unless (File.directory? base_dir) then
          raise "not found a base directory: #{base_dir}"
        end

        mkdir_count = 0
        make_path_list = [ base_dir ]

        for path_name in path_name_list
          make_path_list << path_name
          make_path = File.join(*make_path_list)
          begin
            Dir.mkdir(make_path)
            mkdir_count += 1
          rescue Errno::EEXIST
            unless (File.directory? make_path) then
              raise "not a directory: #{make_path}"
            end
          end
        end

        make_path if (mkdir_count > 0)
      end

      def make_key_value_store_path_name_list(mailbox_data_structure_version, unique_user_id, db_name: nil)
        if (mailbox_data_structure_version.empty?) then
          raise ArgumentError, 'too short mailbox data structure version.'
        end
        if (unique_user_id.length <= 2) then
          raise ArgumentError, 'too short unique user ID.'
        end

        bucket_dir_name = unique_user_id[0..1]
        store_dir_name = unique_user_id[2..-1]
        path_name_list = [ mailbox_data_structure_version, bucket_dir_name, store_dir_name ]
        path_name_list << db_name if db_name

        path_name_list
      end

      def make_key_value_store_path_from_base_dir(base_dir, mailbox_data_structure_version, unique_user_id, db_name: nil)
        path_name_list = [ base_dir ]
        path_name_list += make_key_value_store_path_name_list(mailbox_data_structure_version, unique_user_id, db_name: db_name)
        File.join(*path_name_list)
      end

      def make_key_value_store_parent_dir_from_base_dir(base_dir, mailbox_data_structure_version, unique_user_id)
        mkdir_from_base_dir(base_dir, make_key_value_store_path_name_list(mailbox_data_structure_version, unique_user_id))
      end
    end

    def make_key_value_store_path_from_base_dir(mailbox_data_structure_version, unique_user_id, db_name: nil)
      self.class.make_key_value_store_path_from_base_dir(base_dir, mailbox_data_structure_version, unique_user_id, db_name: db_name)
    end

    def make_key_value_store_parent_dir_from_base_dir(mailbox_data_structure_version, unique_user_id)
      self.class.make_key_value_store_parent_dir_from_base_dir(base_dir, mailbox_data_structure_version, unique_user_id)
    end

    # configuration entries.
    # * <tt>:hostname</tt>
    # * <tt>:username</tt>
    # * <tt>:password</tt>
    # * <tt>:user_list => [ { 'user' => 'username 1', 'pass' => 'password 1'}, { 'user' => 'username 2', 'pass' => 'password 2' } ]</tt>
    # * <tt>:authentication</tt>
    #
    def build_authentication
      hostname = @config.delete(:hostname) || Socket.gethostname
      auth = Authentication.new(hostname: hostname)

      user_list = []
      if (username = @config.delete(:username)) then
        password = @config.delete(:password) or raise 'not defined configuration entry: password'
        user_list << { 'user' => username, 'pass' => password }
      end
      if (@config.key? :user_list) then
        user_list += @config.delete(:user_list)
      end
      for user_entry in user_list
        auth.entry(user_entry['user'], user_entry['pass'])
      end

      if (auth_plug_in_list = @config.delete(:authentication)) then
        for auth_plug_in_entry in auth_plug_in_list
          name = auth_plug_in_entry['plug_in'] or raise 'undefined plug-in name.'

          if ((auth_plug_in_entry.key? 'configuration') && (auth_plug_in_entry.key? 'configuraion_file')) then
            raise 'authentication configuration conflict: configuration, configuraion_file'
          end
          if (auth_plug_in_entry.key? 'configuration') then
            config = auth_plug_in_entry['configuration']
          elsif (auth_plug_in_entry.key? 'configuration_file') then
            config_file = auth_plug_in_entry['configuration_file']
            if (relative_path? config_file) then
              config_path = File.join(base_dir, config_file)
            else
              config_path = config_file
            end
            config = YAML.load_file(config_path)
          else
            raise "not found an authentication configuration for: #{name}"
          end

          passwd_src = Authentication.get_plug_in(name, config)
          auth.add_plug_in(passwd_src)
        end
      end

      auth
    end

    def privilege_name2id(name)
      case (name)
      when Integer
        name
      when String
        begin
          yield(name)
        rescue
          if (name =~ /\A\d+\z/) then
            name.to_i
          else
            raise
          end
        end
      else
        raise TypeError, "not a process privilege name: #{name}"
      end
    end
    private :privilege_name2id

    # configuration entries.
    # * <tt>:process_privilege_user</tt>
    # * <tt>:process_privilege_group</tt>
    #
    def setup_privilege_params
      user = @config.delete(:process_privilege_user) || Server::DEFAULT[:process_privilege_uid]
      group = @config.delete(:process_privilege_group) || Server::DEFAULT[:process_privilege_gid]

      @config[:process_privilege_uid] = privilege_name2id(user) {|name| Etc.getpwnam(name).uid }
      @config[:process_privilege_gid] = privilege_name2id(group) {|name| Etc.getgrnam(name).gid }

      self
    end

    def build_server
      setup_backward_compatibility

      setup_load_libraries
      logger = build_logger
      kvs_factory = build_key_value_store_factory
      auth = build_authentication
      setup_privilege_params

      make_parent_dir_and_logging = proc{|mailbox_data_structure_version, unique_user_id|
        if (make_dir_path = make_key_value_store_parent_dir_from_base_dir(mailbox_data_structure_version, unique_user_id)) then
          logger.debug("make a directory: #{make_dir_path}") if logger.debug?
        end
      }

      Server.new(kvs_meta_open: proc{|mailbox_data_structure_version, unique_user_id, db_name|
                   make_parent_dir_and_logging.call(mailbox_data_structure_version, unique_user_id)
                   kvs_path = make_key_value_store_path_from_base_dir(mailbox_data_structure_version, unique_user_id, db_name: db_name)
                   logger.debug("meta data key-value store path: #{kvs_path}") if logger.debug?
                   kvs_factory.call(kvs_path)
                 },
                 kvs_text_open: proc{|mailbox_data_structure_version, unique_user_id, db_name|
                   make_parent_dir_and_logging.call(mailbox_data_structure_version, unique_user_id)
                   kvs_path = make_key_value_store_path_from_base_dir(mailbox_data_structure_version, unique_user_id, db_name: db_name)
                   logger.debug("message data key-value store path: #{kvs_path}") if logger.debug?
                   kvs_factory.call(kvs_path)
                 },
                 authentication: auth,
                 logger: logger,
                 **through_server_params)
    end
  end

  class Server
    DEFAULT = {
      key_value_store_type: 'GDBM'.freeze,
      use_key_value_store_checksum: true,
      imap_host: '0.0.0.0'.freeze,
      imap_port: 1430,
      mail_delivery_user: '#postman'.freeze,
      process_privilege_uid: 65534,
      process_privilege_gid: 65534,
      log_file: 'imap.log'.freeze,
      log_level: 'INFO',
      log_stdout: 'INFO'
    }.freeze

    def initialize(kvs_meta_open: nil,
                   kvs_text_open: nil,
                   authentication: nil,
                   imap_host: DEFAULT[:imap_host],
                   imap_port: DEFAULT[:imap_port],
                   mail_delivery_user: DEFAULT[:mail_delivery_user],
                   process_privilege_uid: DEFAULT[:process_privilege_uid],
                   process_privilege_gid: DEFAULT[:process_privilege_gid],
                   logger: Logger.new(STDOUT))
      begin
        kvs_meta_open or raise ArgumentError, 'need for a keyword argument: kvs_meta_open'
        kvs_text_open or raise ArgumentError, 'need for a keyword argument: kvs_text_open'
        @authentication = authentication or raise ArgumentError, 'need for a keyword argument: authentication'

        @imap_host = imap_host
        @imap_port = imap_port
        @logger = logger
        @mail_delivery_user = mail_delivery_user

        @process_privilege_uid = process_privilege_uid
        @process_privilege_gid = process_privilege_gid

        @mail_store_pool = MailStorePool.new(kvs_meta_open, kvs_text_open)
      rescue
        logger.fatal($!) rescue StandardError
        raise
      end
    end

    def ipaddr_log(addr_list)
      addr_list.map{|i| "[#{i}]" }.join('')
    end
    private :ipaddr_log

    def start
      @logger.info('start server.')
      @authentication.start_plug_in(@logger)
      @logger.info("open socket: #{@imap_host}:#{@imap_port}")
      sv_sock = TCPServer.new(@imap_host, @imap_port)

      begin
        @logger.info("opened: #{ipaddr_log(sv_sock.addr)}")

        if (Process.euid == 0) then
          Process::Sys.setgid(@process_privilege_gid)
          Process::Sys.setuid(@process_privilege_uid)
        end

        @logger.info("process ID: #{$$}")
        process_user = Etc.getpwuid(Process.euid).name rescue ''
        @logger.info("process privilege user: #{process_user}(#{Process.euid})")
        process_group = Etc.getgrgid(Process.egid).name rescue ''
        @logger.info("process privilege group: #{process_group}(#{Process.egid})")

        loop do
          Thread.start(sv_sock.accept) {|cl_sock|
            begin
              @logger.info("accept client: #{ipaddr_log(cl_sock.peeraddr(false))}")
              decoder = Protocol::Decoder.new_decoder(@mail_store_pool, @authentication, @logger, mail_delivery_user: @mail_delivery_user)
              Protocol::Decoder.repl(decoder, cl_sock, cl_sock, @logger)
            ensure
              Error.suppress_2nd_error_at_resource_closing(logger: @logger) { cl_sock.close }
            end
          }
        end
      ensure
        @logger.info("close socket: #{ipaddr_log(sv_sock.addr)}")
        sv_sock.close
        @authentication.stop_plug_in(@logger)
      end

      self
    rescue
      @logger.error($!)
      raise
    ensure
      @logger.info('stop sever.')
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

  c = RIMS::Config.new
  c.load_config_yaml(ARGV[0])
  c.setup
  pp c.config if $DEBUG

  server = RIMS::Server.new(**c.config)
  server.start
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
