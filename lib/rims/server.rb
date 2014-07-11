# -*- coding: utf-8 -*-

require 'fileutils'
require 'logger'
require 'socket'
require 'yaml'

module RIMS
  class Config
    def initialize
      @config = {}
    end

    def load(config)
      @config.update(config)
      self
    end

    def load_config_yaml(path)
      for name, value in YAML.load_file(path)
        @config[name.to_sym] = value
      end
      self
    end

    # configuration entries.
    # * <tt>:base_dir</tt>
    #
    def base_dir
      @config[:base_dir] or raise 'not defined configuration entry: base_dir'
    end
    private :base_dir

    def through_server_params
      params = @config.dup
      params.delete(:base_dir)
      params
    end

    # configuration entries.
    # * <tt>:log_file</tt>
    # * <tt>:log_level</tt>
    # * <tt>:log_shift_age</tt>
    # * <tt>:log_shift_size</tt>
    #
    def logging_params
      log_file = @config.delete(:log_file) || 'imap.log'
      log_file = File.join(base_dir, File.basename(log_file))

      log_level = @config.delete(:log_level) || 'INFO'
      log_level = log_level.upcase
      %w[ DEBUG INFO WARN ERROR FATAL ].include? log_level or raise "unknown log level: #{log_level}"
      log_level = Logger.const_get(log_level)

      log_opt_args = []
      if (@config.key? :log_shift_age) then
        log_opt_args << @config.delete(:log_shift_age)
        log_opt_args << @config.delete(:log_shift_size) if (@config.key? :log_shift_size)
      else
        log_opt_args << 1 <<  @config.delete(:log_shift_size) if (@config.key? :log_shift_size)
      end

      { log_file: log_file,
        log_level: log_level,
        log_opt_args: log_opt_args
      }
    end

    def build_logger
      c = logging_params
      logger = Logger.new(c[:log_file], *c[:log_opt_args])
      logger.level = c[:log_level]
      logger
    end

    # configuration entries.
    # * <tt>:key_value_store_type</tt>
    # * <tt>:use_key_value_store_checksum</tt>
    #
    def key_value_store_params
      kvs_type = (@config.delete(:key_value_store_type) || 'GDBM').upcase
      case (kvs_type)
      when 'GDBM'
        origin_key_value_store = GDBM_KeyValueStore
      else
        raise "unknown key-value store type: #{kvs_type}"
      end

      middleware_key_value_store_list = []
      if ((@config.key? :use_key_value_store_checksum) ? @config.delete(:use_key_value_store_checksum) : true) then
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

    # configuration entries of following are defined at this method.
    # * <tt>:base_dir</tt>
    # * <tt>:log_file</tt>
    # * <tt>:log_level</tt>
    # * <tt>:key_value_store_type</tt>
    # * <tt>:username</tt>
    # * <tt>:password</tt>
    #
    # other configuration entries are defined as named parameter at RIMS::Server.new.
    #
    def setup
      base_dir = @config.delete(:base_dir) or raise 'not defined configuration entry: base_dir'

      log_file = @config.delete(:log_file) || 'imap.log'
      log_file = File.basename(log_file)
      log_level = @config.delete(:log_level) || 'INFO'
      log_level = log_level.upcase
      %w[ DEBUG INFO WARN ERROR FATAL ].include? log_level or raise "unknown log level: #{log_level}"
      log_level = Logger.const_get(log_level)
      log_opt_args = []
      if (@config.key? :log_shift_age) then
        log_opt_args << @config.delete(:log_shift_age)
        log_opt_args << @config.delete(:log_shift_size) if (@config.key? :log_shift_size)
      else
        log_opt_args << 1 <<  @config.delete(:log_shift_size) if (@config.key? :log_shift_size)
      end
      @config[:logger] = Logger.new(File.join(base_dir, log_file), *log_opt_args)
      @config[:logger].level = log_level

      builder = KeyValueStore::FactoryBuilder.new
      kvs_type = (@config.delete(:key_value_store_type) || 'GDBM').upcase
      case (kvs_type)
      when 'GDBM'
        builder.open{|name| GDBM_KeyValueStore.open(name) }
      else
        raise "unknown key-value store type: #{kvs_type}"
      end
      if ((@config.key? :use_key_value_store_checksum) ? @config.delete(:use_key_value_store_checksum) : true) then
        builder.use(Checksum_KeyValueStore)
      end
      kvs_factory = builder.factory

      @config[:kvs_meta_open] = proc{|user_prefix, name|
        kvs_path = make_kvs_path(base_dir, user_prefix, name)
        @config[:logger].debug("meta key-value store path: #{kvs_path}") if @config[:logger].debug?
        kvs_factory.call(kvs_path)
      }
      @config[:kvs_text_open] = proc{|user_prefix, name|
        kvs_path = make_kvs_path(base_dir, user_prefix, name)
        @config[:logger].debug("text key-value store path: #{kvs_path}") if @config[:logger].debug?
        kvs_factory.call(kvs_path)
      }

      hostname = @config.delete(:hostname) || Socket.gethostname
      username = @config.delete(:username) or raise 'not defined configuration entry: username'
      password = @config.delete(:password) or raise 'not defined configuration entry: password'
      auth = Authentication.new(hostname: hostname)
      auth.entry(username, password)
      @config[:authentication] = auth

      self
    end

    def make_kvs_path(base_dir, user_prefix, name)
      parent_dir = File.join(base_dir, user_prefix)
      FileUtils.mkdir(parent_dir) unless (File.directory? parent_dir)
      File.join(parent_dir, name)
    end
    private :make_kvs_path

    attr_reader :config
  end

  class Server
    def initialize(kvs_meta_open: nil,
                   kvs_text_open: nil,
                   authentication: nil,
                   ip_addr: '0.0.0.0',
                   ip_port: 1430,
                   logger: Logger.new(STDOUT))
      begin
        @kvs_meta_open = kvs_meta_open
        @kvs_text_open = kvs_text_open
        @authentication = authentication
        @ip_addr = ip_addr
        @ip_port = ip_port
        @logger = logger

        @mail_store_pool = MailStorePool.new(@kvs_meta_open, @kvs_text_open, proc{|name| 'mailbox.1' })
      rescue
        logger.fatal($!) rescue StandardError
        raise
      end
    end

    def start
      @logger.info("open server: #{@ip_addr}:#{@ip_port}")
      sv_sock = TCPServer.new(@ip_addr, @ip_port)

      loop do
        Thread.start(sv_sock.accept) {|cl_sock|
          begin
            @logger.info("accept client: #{cl_sock.peeraddr[1..2].reverse.join(':')}")
            decoder = Protocol::Decoder.new(@mail_store_pool, @authentication, @logger)
            begin
              Protocol::Decoder.repl(decoder, cl_sock, cl_sock, @logger)
            ensure
              Error.suppress_2nd_error_at_resource_closing(logger: @logger) { decoder.cleanup }
            end
          ensure
            Error.suppress_2nd_error_at_resource_closing(logger: @logger) { cl_sock.close }
          end
        }
      end

      self
    rescue
      @logger.error($!)
      raise
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
