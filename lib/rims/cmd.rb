# -*- coding: utf-8 -*-

require 'json'
require 'net/imap'
require 'optparse'
require 'pp'if $DEBUG
require 'riser'
require 'yaml'

OptionParser.accept(JSON) do |json_data, *_|
  begin
    JSON.load(json_data)
  rescue
    raise OptionParser::InvalidArgument, json_data
  end
end

module RIMS
  module Cmd
    CMDs = {}

    def self.command_function(method_name, description)
      module_function(method_name)
      method_name = method_name.to_s
      unless (method_name =~ /\A cmd_/x) then
        raise "invalid command function name: #{method_name}"
      end
      cmd_name = $'.gsub(/_/, '-')
      CMDs[cmd_name] = { function: method_name.to_sym, description: description }
    end

    def run_cmd(args)
      options = OptionParser.new
      if (args.empty?) then
        cmd_help(options, args)
        return 1
      end

      cmd_name = args.shift
      pp cmd_name if $DEBUG
      pp args if $DEBUG

      cmd_entry = CMDs[cmd_name] or raise "unknown command: #{cmd_name}. Run `#{options.program_name} help'."
      options.program_name += " #{cmd_name}"
      send(cmd_entry[:function], options, args)
    end
    module_function :run_cmd

    def cmd_help(options, args)
      show_debug_command = false
      options.on('--show-debug-command', 'Show command for debug in help message. At default, debug command is hidden.') do
        show_debug_command = true
      end
      options.parse!(args)

      puts "usage: #{File.basename($0)} command options"
      puts ""
      puts "commands:"
      w = CMDs.keys.map{|k| k.length }.max + 4
      fmt = "    %- #{w}s%s"
      CMDs.sort_by{|cmd_name, _| cmd_name }.each do |cmd_name, cmd_entry|
        if ((! show_debug_command) && (cmd_name =~ /\A debug/x)) then
          next
        end
        puts format(fmt, cmd_name, cmd_entry[:description])
      end
      puts ""
      puts "command help options:"
      puts "    -h, --help"
      0
    end
    command_function :cmd_help, "Show this message."

    def cmd_version(options, args)
      options.parse!(args)
      puts RIMS::VERSION
      0
    end
    command_function :cmd_version, 'Show software version.'

    class ServiceConfigChainBuilder
      def initialize
        @build = proc{ Service::Configuration.new }
      end

      def chain(&block)
        parent = @build
        @build = proc{ block.call(parent.call) }
        self
      end

      def call
        @build.call
      end
    end

    def make_service_config(options)
      build = ServiceConfigChainBuilder.new
      build.chain{|c| c.load(base_dir: Dir.getwd) }

      options.summary_width = 37
      log_level_list = %w[ debug info warn error fatal unknown ]

      options.on('-h', '--help', 'Show this message.') do
        puts options
        exit
      end
      options.on('-f', '--config-yaml=CONFIG_FILE',
                 String,
                 "Load optional parameters from CONFIG_FILE."
                ) do |path|
        build.chain{|c| c.load_yaml(path) }
      end
      options.on('-r', '--required-feature=FEATURE',
                 String,
                 "Add required feature."
                ) do |feature|
        require(feature)
        build.chain{|c| c.load(required_features: [ feature ]) }
      end
      options.on('-d', '--base-dir=DIR',
                 String,
                 "Directory that places log file, mailbox database, etc. default is current directory."
                ) do |path|
        build.chain{|c| c.load(base_dir: path) }
      end
      options.on('--log-file=FILE',
                 String,
                 "Name of log file. default is `#{Service::DEFAULT_CONFIG.make_file_logger_params[0]}'."
                ) do |path|
        build.chain{|c|
          c.load(logger: {
                   file: {
                     path: path
                   }
                 })
        }
      end
      options.on('-l', '--log-level=LEVEL',
                 log_level_list,
                 "Logging level (#{log_level_list.join(' ')}). default is `" +
                 Service::DEFAULT_CONFIG.make_file_logger_params[-1][:level] +
                 "'."
                ) do |level|
        build.chain{|c|
          c.load(logging: {
                   file: {
                     level: level
                   }
                 })
        }
      end
      options.on('--log-shift-age=NUMBER',
                 Integer,
                 'Number of old log files to keep.'
                ) do |num|
        build.chain{|c|
          c.load(logging: {
                   file: {
                     shift_age: num
                   }
                 })
        }
      end
      options.on('--log-shift-age-daily',
                 'Frequency of daily log rotation.'
                ) do
        build.chain{|c|
          c.load(logger: {
                   file: {
                     shift_age: 'daily'
                   }
                 })
        }
      end
      options.on('--log-shift-age-weekly',
                 'Frequency of weekly log rotation.'
                ) do
        build.chain{|c|
          c.load(logger: {
                   file: {
                     shift_age: 'weekly'
                   }
                 })
        }
      end
      options.on('--log-shift-age-monthly',
                 'Frequency of monthly log rotation.'
                ) do
        build.chain{|c|
          c.load(logger: {
                   file: {
                     shift_age: 'monthly'
                   }
                 })
        }
      end
      options.on('--log-shift-size=SIZE',
                 Integer,
                 'Maximum logfile size.'
                ) do |size|
        build.chain{|c|
          c.load(logger: {
                   file: {
                     shift_size: size
                   }
                 })
        }
      end
      options.on('-v', '--log-stdout=LEVEL',
                 log_level_list + %w[  quiet ],
                 "Stdout logging level (#{(log_level_list + %w[ quiet ]).join(' ')}). default is `" +
                 Service::DEFAULT_CONFIG.make_stdout_logger_params[-1][:level] +
                 "'."
                ) do |level|
        if (level == 'quiet') then
          level = 'unknown'
        end
        build.chain{|c|
          c.load(logging: {
                   stdout: {
                     level: level
                   }
                 })
        }
      end
      options.on('--protocol-log-file=FILE',
                 String,
                 "Name of log file. default is `#{Service::DEFAULT_CONFIG.make_protocol_logger_params[0]}'."
                ) do |path|
        build.chain{|c|
          c.load(logger: {
                   protocol: {
                     path: path
                   }
                 })
        }
      end
      options.on('-p', '--protocol-log-level=LEVEL',
                 log_level_list,
                 "Logging level (#{log_level_list.join(' ')}). default is `" +
                 Service::DEFAULT_CONFIG.make_protocol_logger_params[-1][:level] +
                 "'."
                ) do |level|
        build.chain{|c|
          c.load(logging: {
                   protocol: {
                     level: level
                   }
                 })
        }
      end
      options.on('--protocol-log-shift-age=NUMBER',
                 Integer,
                 'Number of old log files to keep.'
                ) do |num|
        build.chain{|c|
          c.load(logging: {
                   protocol: {
                     shift_age: num
                   }
                 })
        }
      end
      options.on('--protocol-log-shift-age-daily',
                 'Frequency of daily log rotation.'
                ) do
        build.chain{|c|
          c.load(logger: {
                   protocol: {
                     shift_age: 'daily'
                   }
                 })
        }
      end
      options.on('--protocol-log-shift-age-weekly',
                 'Frequency of weekly log rotation.'
                ) do
        build.chain{|c|
          c.load(logger: {
                   protocol: {
                     shift_age: 'weekly'
                   }
                 })
        }
      end
      options.on('--protocol-log-shift-age-monthly',
                 'Frequency of monthly log rotation.'
                ) do
        build.chain{|c|
          c.load(logger: {
                   protocol: {
                     shift_age: 'monthly'
                   }
                 })
        }
      end
      options.on('--protocol-log-shift-size=SIZE',
                 Integer,
                 'Maximum logfile size.'
                ) do |size|
        build.chain{|c|
          c.load(logger: {
                   protocol: {
                     shift_size: size
                   }
                 })
        }
      end
      options.on('--[no-]daemonize',
                 "Daemonize server process. effective only with daemon command."
                ) do |daemonize|
        build.chain{|c|
          c.load(daemon: {
                   daemonize: daemonize
                 })
        }
      end
      options.on('--[no-]daemon-debug',
                 "Debug daemon. effective only with daemon command."
                ) do |debug|
        build.chain{|c|
          c.load(daemon: {
                   debug: debug
                 })
        }
      end
      options.on('--daemon-umask=UMASK',
                 Integer,
                 "Umask(2). effective only with daemon command. default is `#{'%04o' % Service::DEFAULT_CONFIG.daemon_umask}'."
                ) do |umask|
        build.chain{|c|
          c.load(daemon: {
                   umask: umask
                 })
        }
      end
      options.on('--status-file=FILE',
                 String,
                 "Name of status file. effective only with daemon command. default is `#{Service::DEFAULT_CONFIG.status_file}'."
                ) do |path|
        build.chain{|c|
          c.load(daemon: {
                   status_file: path
                 })
        }
      end
      options.on('--privilege-user=USER',
                 String,
                 "Privilege user name or ID for server process. effective only with daemon command."
                ) do |user|
        build.chain{|c|
          c.load(daemon: {
                   server_privileged_user: user
                 })
        }
      end
      options.on('--privilege-group=GROUP',
                 String,
                 "Privilege group name or ID for server process. effective only with daemon command."
                ) do |group|
        build.chain{|c|
          c.load(daemon: {
                   server_privileged_group: group
                 })
        }
      end
      options.on('-s', '--listen=HOST_PORT',
                 String,
                 "Listen socket address. default is `#{Service::DEFAULT_CONFIG.listen_address}'"
                ) do |host_port|
        build.chain{|c|
          c.load(server: {
                   listen_address: host_port
                 })
        }
      end
      options.on('--accept-polling-timeout=SECONDS',
                 Float
                ) do |seconds|
        build.chain{|c|
          c.load(server: {
                   accept_polling_timeout_seconds: seconds
                 })
        }
      end
      options.on('--process-num=NUMBER',
                 Integer
                ) do |num|
        build.chain{|c|
          c.load(server: {
                   process_num: num
                 })
        }
      end
      options.on('--process-queue-size=SIZE',
                 Integer
                ) do |size|
        build.chain{|c|
          c.load(server: {
                   process_queue_size: size
                 })
        }
      end
      options.on('--process-queue-polling-timeout=SECONDS',
                 Float) do |seconds|
        build.chain{|c|
          c.load(server: {
                   process_queue_polling_timeout_seconds: seconds
                 })
        }
      end
      options.on('--process-send-io-polling-timeout=SECONDS',
                 Float) do |seconds|
        build.chain{|c|
          c.load(server: {
                   process_send_io_polling_timeout_seconds: seconds
                 })
        }
      end
      options.on('--thread-num=NUMBER',
                 Integer
                ) do |num|
        build.chain{|c|
          c.load(server: {
                   thread_num: num
                 })
        }
      end
      options.on('--thread-queue-size=SIZE',
                 Integer
                ) do |size|
        build.chain{|c|
          c.load(server: {
                   thread_queue_size: size
                 })
        }
      end
      options.on('--thread-queue-polling-timeout=SECONDS',
                 Float
                ) do |seconds|
        build.chain{|c|
          c.load(server: {
                   thread_queue_polling_timeout_seconds: seconds
                 })
        }
      end
      options.on('--send-buffer-limit=SIZE',
                 Integer
                ) do |size|
        build.chain{|c|
          c.load(connection: {
                   send_buffer_limit_size: size
                 })
        }
      end
      options.on('--read-polling-interval=SECONDS',
                 Float
                ) do |seconds|
        build.chain{|c|
          c.load(connection: {
                   read_polling_interval_seconds: seconds
                 })
        }
      end
      options.on('--command-wait-timeout=SECONDS',
                 Float
                ) do |seconds|
        build.chain{|c|
          c.load(connection: {
                   command_wait_timeout_seconds: seconds
                 })
        }
      end
      options.on('--line-length-limit=SIZE',
                 Integer
                ) do |size|
        build.chain{|c|
          c.load(protocol: {
                   line_length_limit: size
                 })
        }
      end
      options.on('--literal-size-limit=SIZE',
                 Integer
                ) do |size|
        build.chain{|c|
          c.load(protocol: {
                   literal_size_limit: size
                 })
        }
      end
      options.on('--command-size-limit=SIZE',
                 Integer
                ) do |size|
        build.chain{|c|
          c.load(protocol: {
                   command_size_limit: size
                 })
        }
      end
      options.on('--[no-]use-default-charset-aliases'
                ) do |use_default_aliases|
        build.chain{|c|
          c.load(charset: {
                   use_default_aliases: use_default_aliases
                 })
        }
      end
      options.on('--add-charset-alias=NAME_TO_ENCODING',
                 /\A \S+,\S+ \z/x,
                 "Set the alias name and encoding separated with comma (,)."
                ) do |name_to_encoding|
        name, encoding = name_to_encoding.split(',', 2)
        build.chain{|c|
          c.load(charset: {
                   aliases: [
                     { name: name, encoding: encoding }
                   ]
                 })
        }
      end
      options.on('--[no-]replace-charset-invalid'
                ) do |replace|
        build.chain{|c|
          c.load(charset: {
                   convert_options: {
                     replace_invalid_byte_sequence: replace
                   }
                 })
        }
      end
      options.on('--[no-]replace-charset-undef'
                ) do |replace|
        build.chain{|c|
          c.load(charset: {
                   convert_options: {
                     replace_undefined_character: replace
                   }
                 })
        }
      end
      options.on('--charset-replaced-mark=MARK',
                 String
                ) do |mark|
        build.chain{|c|
          c.load(charset: {
                   convert_options: {
                     replaced_mark: mark
                   }
                 })
        }
      end
      options.on('--drb-process-num=NUMBER',
                 Integer
                ) do |num|
        build.chain{|c|
          c.load(drb_services: {
                   process_num: num
                 })
        }
      end
      options.on('--drb-load-limit=SIZE',
                 Integer
                ) do |size|
        build.chain{|c|
          c.load(drb_services: {
                   load_limit: size
                 })
        }
      end
      options.on('--bulk-response-count=COUNT',
                 Integer) do |count|
        build.chain{|c|
          c.load(drb_services: {
                   engine: {
                     bulk_response_count: count
                   }
                 })
        }
      end
      options.on('--bulk-response-size=SIZE',
                 Integer) do |size|
        build.chain{|c|
          c.load(drb_services: {
                   engine: {
                     bulk_response_size: size
                   }
                 })
        }
      end
      options.on('--read-lock-timeout=SECONDS',
                 Float
                ) do |seconds|
        build.chain{|c|
          c.load(drb_services: {
                   engine: {
                     read_lock_timeout_seconds: seconds
                   }
                 })
        }
      end
      options.on('--write-lock-timeout=SECONDS',
                 Float
                ) do |seconds|
        build.chain{|c|
          c.load(drb_services: {
                   engine: {
                     write_lock_timeout_seconds: seconds
                   }
                 })
        }
      end
      options.on('--cleanup-write-lock-timeout=SECONDS',
                 Float
                ) do |seconds|
        build.chain{|c|
          c.load(drb_services: {
                   engine: {
                     cleanup_write_lock_timeout_seconds: seconds
                   }
                 })
        }
      end
      options.on('--meta-kvs-type=TYPE',
                 "Choose key-value store type of mailbox meta-data database. default is `" +
                 KeyValueStore::FactoryBuilder.plug_in_names[0] +
                 "'."
                ) do |kvs_type|
        build.chain{|c|
          c.load(storage: {
                   meta_key_value_store: {
                     type: kvs_type
                   }
                 })
        }
      end
      options.on('--meta-kvs-config=JSON_DATA',
                 JSON,
                 "Configuration for key-value store of mailbox meta-data database."
                ) do |json_data|
        build.chain{|c|
          c.load(storage: {
                   meta_key_value_store: {
                     configuration: json_data
                   }
                 })
        }
      end
      options.on('--[no-]use-meta-kvs-checksum',
                 "Enable/disable data checksum at key-value store of mailbox meta-data database. default is " +
                 if (Service::DEFAULT_CONFIG.make_meta_key_value_store_params.middleware_list.include? Checksum_KeyValueStore) then
                   'enabled'
                 else
                   'disbled'
                 end +
                 "."
                ) do |use_checksum|
        build.chain{|c|
          c.load(storage: {
                   meta_key_value_store: {
                     use_checksum: use_checksum
                   }
                 })
        }
      end
      options.on('--text-kvs-type=TYPE',
                 "Choose key-value store type of mailbox text-data database. default is `" +
                 KeyValueStore::FactoryBuilder.plug_in_names[0] +
                 "'."
                ) do |kvs_type|
        build.chain{|c|
          c.load(storage: {
                   text_key_value_store: {
                     type: kvs_type
                   }
                 })
        }
      end
      options.on('--text-kvs-config=JSON_DATA',
                 JSON,
                 "Configuration for key-value store of mailbox text-data database."
                ) do |json_data|
        build.chain{|c|
          c.load(storage: {
                   text_key_value_store: {
                     configuration: json_data
                   }
                 })
        }
      end
      options.on('--[no-]use-text-kvs-checksum',
                 "Enable/disable data checksum at key-value store of mailbox text-data database. default is " +
                 if (Service::DEFAULT_CONFIG.make_text_key_value_store_params.middleware_list.include? Checksum_KeyValueStore) then
                   'enabled'
                 else
                   'disbled'
                 end +
                 "."
                ) do |use_checksum|
        build.chain{|c|
          c.load(storage: {
                   text_key_value_store: {
                     use_checksum: use_checksum
                   }
                 })
        }
      end
      options.on('--auth-hostname=HOSTNAME',
                 String,
                 "Hostname to authenticate with cram-md5. default is `#{Service::DEFAULT_CONFIG.make_authentication.hostname}'."
                ) do |hostname|
        build.chain{|c|
          c.load(authentication: {
                   hostname: hostname
                 })
        }
      end
      options.on('--passwd-config=TYPE_JSONDATA',
                 /([^:]+)(?::(.*))?/,
                 "Password source type and configuration. format is `[type]:[json_data]'."
                ) do |_, type, json_data|
        build.chain{|c|
          c.load(authentication: {
                   password_sources: [
                     { type: type,
                       configuration: JSON.load(json_data)
                     }
                   ]
                 })
        }
      end
      options.on('--passwd-file=TYPE_FILE',
                 /([^:]+):(.+)/,
                 "Password source type and configuration file. format is `[type]:[file]'."
                ) do |_, type, path|
        build.chain{|c|
          c.load(authentication: {
                   password_sources: [
                     { type: type,
                       configuration_file: path
                     }
                   ]
                 })
        }
      end
      options.on('--mail-delivery-user=USERNAME',
                 String,
                 "Username authorized to deliver messages to any mailbox. default is `#{Service::DEFAULT_CONFIG.mail_delivery_user}'"
                ) do |username|
        build.chain{|c|
          c.load(authorization: {
                   mail_delivery_user: username
                 })
        }
      end

      options.on('--imap-host=HOSTNAME',
                 String,
                 'Deplicated.'
                ) do |host|
        warn("warning: `--imap-host=HOSTNAME' is deplicated option and should use `--listen=HOST_PORT'.")
        build.chain{|c| c.load(imap_host: host) }
      end
      options.on('--imap-port=PORT',
                 String,
                 'Deplicated.'
                ) do |value|
        warn("warning: `--imap-port=PORT' is deplicated option and should use `--listen=HOST_PORT'.")
        if (value =~ /\A \d+ \z/x) then
          port_number = value.to_i
          build.chain{|c| c.load(imap_port: port_number) }
        else
          service_name = value
          build.chain{|c| c.load(imap_port: service_name) }
        end
      end
      options.on('--ip-addr=IP_ADDR',
                 String,
                 'Deplicated.'
                ) do |ip_addr|
        warn("warning: `--ip-addr=IP_ADDR' is deplicated option and should use `--listen=HOST_PORT'.")
        build.chain{|c| c.load(ip_addr: ip_addr) }
      end
      options.on('--ip-port=PORT',
                 Integer,
                 'Deplicated.'
                ) do |port|
        warn("warning: `--ip-port=PORT' is deplicated option and should use `--listen=HOST_PORT'.")
        build.chain{|c| c.load(ip_port: port) }
      end
      options.on('--kvs-type=TYPE',
                 'Deplicated.'
                ) do |kvs_type|
        warn("warning: `--kvs-type=TYPE' is deplicated option and should use `--meta-kvs-type=TYPE' or `--text-kvs-type=TYPE'.")
        build.chain{|c| c.load(key_value_store_type: kvs_type) }
      end
      options.on('--[no-]use-kvs-cksum',
                 'Deplicated.'
                ) do |use_checksum|
        warn("warning: `--[no-]use-kvs-cksum' is deplicated option and should use `--[no-]use-meta-kvs-checksum' or `--[no-]use-text-kvs-checksum'.")
        build.chain{|c| c.load(use_key_value_store_checksum: use_checksum) }
      end
      options.on('-u', '--username=NAME',
                 String,
                 'Deplicated.'
                ) do |name|
        warn("warning: `--username=NAME' is deplicated option and should use `--passwd-config=TYPE_JSONDATA' or `--passwd-file=TYPE_FILE'.")
        build.chain{|c| c.load(username: name) }
      end
      options.on('-w', '--password=PASS',
                 String,
                 'Deplicated.'
                ) do |pass|
        warn("warning: `--password=PASS' is deplicated option and should use `--passwd-config=TYPE_JSONDATA' or `--passwd-file=TYPE_FILE'.")
        build.chain{|c| c.load(password: pass) }
      end

      build
    end
    module_function :make_service_config

    def cmd_server(options, args)
      build = make_service_config(options)
      options.parse!(args)

      config = build.call
      server = Riser::SocketServer.new
      service = RIMS::Service.new(config)
      service.setup(server)

      Signal.trap(:INT) { server.signal_stop_forced }
      Signal.trap(:TERM) { server.signal_stop_graceful }

      listen_address = Riser::SocketAddress.parse(config.listen_address)
      server.start(listen_address.open_server)

      0
    end
    command_function :cmd_server, "Run IMAP server."

    def imap_res2str(imap_response)
      "#{imap_response.name} #{imap_response.data.text}"
    end
    module_function :imap_res2str

    class Config
      def imap_res2str(imap_response)
        Cmd.imap_res2str(imap_response)
      end
      private :imap_res2str

      IMAP_AUTH_TYPE_LIST  = %w[ login plain cram-md5 ]
      MAIL_DATE_PLACE_LIST = [ :servertime, :localtime, :filetime, :mailheader ]

      VERBOSE_OPTION_LIST = [
        [ :verbose, false, '-v', '--[no-]verbose', "Enable verbose messages. default is no verbose." ]
      ]

      def self.make_imap_connect_option_list(imap_host: 'localhost', imap_port: 143, imap_ssl: false, auth_type: 'login', username: nil)
        [ [ :imap_host,  imap_host, '-n', '--host=HOSTNAME',                  "Hostname or IP address to connect IMAP server. default is `#{imap_host}'." ],
          [ :imap_port,  imap_port, '-o', '--port=PORT', Integer,             "Server port number or service name to connect IMAP server. default is #{imap_port}." ],
          [ :imap_ssl,   imap_ssl,  '-s', '--[no-]use-ssl',                   "Enable SSL/TLS connection. default is #{imap_ssl ? 'enabled' : 'disabled'}." ],
          [ :ca_cert,    nil,              '--ca-cert=PATH',                  "CA cert file or directory." ],
          [ :ssl_params, {},               '--ssl-params=JSON_DATA', JSON,    "SSLContext#set_params as parameters." ],
          [ :username,   username,  '-u', '--username=NAME',                  "Username to login IMAP server. " +
                                                                              (username ? "default is `#{username}'." : "required parameter to connect server.") ],
          [ :password,  nil,       '-w', '--password=PASS',                   "Password to login IMAP server. required parameter to connect server." ],
          [ :auth_type, auth_type, '--auth-type=METHOD', IMAP_AUTH_TYPE_LIST, "Choose authentication method type (#{IMAP_AUTH_TYPE_LIST.join(' ')}). " +
                                                                              "default is `#{auth_type}'." ]
        ]
      end

      IMAP_CONNECT_OPTION_LIST      = make_imap_connect_option_list
      POST_MAIL_CONNECT_OPTION_LIST = make_imap_connect_option_list(imap_port: Riser::SocketAddress.parse(Service::DEFAULT_CONFIG.listen_address).port,
                                                                    username: Service::DEFAULT_CONFIG.mail_delivery_user)

      IMAP_MAILBOX_OPTION_LIST = [
        [ :mailbox, 'INBOX', '-m', '--mailbox=NAME', String, "Set mailbox name to append messages. default is `INBOX'." ]
      ]

      IMAP_STORE_FLAG_OPTION_LIST = [
        [ :store_flag_answered, false, '--[no-]store-flag-answered', "Store answered flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_flagged,  false, '--[no-]store-flag-flagged',  "Store flagged flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_deleted,  false, '--[no-]store-flag-deleted',  "Store deleted flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_seen,     false, '--[no-]store-flag-seen',     "Store seen flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_draft,    false, '--[no-]store-flag-draft',    "Store draft flag on appending messages to mailbox. default is no flag." ]
      ]

      MAIL_DATE_OPTION_LIST = [
        [ :look_for_date, :servertime, '--look-for-date=PLACE', MAIL_DATE_PLACE_LIST,
          "Choose the place (#{MAIL_DATE_PLACE_LIST.join(' ')}) to look for the date that as internaldate is appended with message. default is `servertime'."
        ]
      ]

      def self.symbolize_string_key(collection)
        case (collection)
        when Hash
          Hash[collection.map{|key, value|
                 [ symbolize_string_key(key),
                   case (value)
                   when Hash, Array
                     symbolize_string_key(value)
                   else
                     value
                   end
                 ]
               }]
        when Array
          collection.map{|value|
            case (value)
            when Hash, Array
              symbolize_string_key(value)
            else
              value
            end
          }
        else
          case (value = collection)
          when String
            value.to_sym
          else
            value
          end
        end
      end

      def initialize(options, option_list)
        @options = options
        @option_list = option_list
        @conf = {}
        for key, value, *_option_description in option_list
          @conf[key] = value
        end
      end

      def [](key)
        @conf[key]
      end

      def setup_option_list
        @option_list.each do |key, value, *option_description|
          @options.on(*option_description) do |v|
            @conf[key] = v
          end
        end

        self
      end

      def help_option(add_banner: nil)
        @options.banner += add_banner if add_banner
        @options.on('-h', '--help', 'Show this message.') do
          puts @options
          exit
        end

        self
      end

      def quiet_option(default_verbose: true)
        @conf[:verbose] = default_verbose
        @options.on('-v', '--[no-]verbose', 'Enable verbose messages. default is verbose.') do |verbose|
          @conf[:verbose] = verbose
        end
        @options.on('-q', '--[no-]quiet', 'Disable verbose messages. default is verbose.') do |quiet|
          @conf[:verbose] = ! quiet
        end

        self
      end

      def load_config_option
        @options.on('-f', '--config-yaml=CONFIG_FILE',
                    String,
                    "Load optional parameters from CONFIG_FILE.") do |path|
          config = YAML.load_file(path)
          symbolized_config = self.class.symbolize_string_key(config)
          @conf.update(symbolized_config)
        end

        self
      end

      def required_feature_option
        @options.on('-r', '--required-feature=FEATURE', String, 'Add required feature.') do |feature|
          require(feature)
        end
        @options.on('--load-library=LIBRARY', String, 'Deplicated.') do |library|
          warn("warning: `--load-library=LIBRARY' is deplicated option and should use `--required-feature=FEATURE'.")
          require(library)
        end

        self
      end

      def key_value_store_option
        @conf[:key_value_store_type] = GDBM_KeyValueStore
        @options.on('--kvs-type=TYPE',
                    "Choose key-value store type of mailbox database. default is `" +
                    KeyValueStore::FactoryBuilder.plug_in_names[0] +
                    "'."
                   ) do |kvs_type|
          @conf[:key_value_store_type] = KeyValueStore::FactoryBuilder.get_plug_in(kvs_type)
        end

        @conf[:use_key_value_store_checksum] = true
        @options.on('--[no-]use-kvs-checksum', 'Enable/disable data checksum at key-value store. default is enabled.') do |use_checksum|
          @conf[:use_key_value_store_checksum] = use_checksum
        end
        @options.on('--[no-]use-kvs-cksum', 'Deplicated.') do |use_checksum|
          warn("warning: `--[no-]use-kvs-cksum' is deplicated option and should use `--[no-]use-kvs-checksum'.")
          @conf[:use_key_value_store_checksum] = use_checksum
        end

        self
      end

      def parse_options!(args, order: false)
        if (order) then
          @options.order!(args)
        else
          @options.parse!(args)
        end
        pp @conf if $DEBUG

        self
      end

      def imap_debug_option
        @options.on('--[no-]imap-debug',
                    "Set the debug flag of Net::IMAP class. default is false.") do |v|
          Net::IMAP.debug = v
        end

        self
      end

      def imap_connect
        unless (@conf[:username] && @conf[:password]) then
          raise 'need for username and password.'
        end

        args = [ @conf[:imap_host] ]
        if (@conf[:imap_ssl]) then
          if (@conf[:ssl_params].empty?) then
            args << @conf[:imap_port]
            args << @conf[:imap_ssl]
            args << @conf[:ca_cert]
          else
            kw_args = {
              port: @conf[:imap_port],
              ssl: @conf[:ssl_params]
            }
            args << kw_args
          end
        else
          args << @conf[:imap_port]
        end

        imap = Net::IMAP.new(*args)
        begin
          if (@conf[:verbose]) then
            puts "server greeting: #{imap_res2str(imap.greeting)}"
            puts "server capability: #{imap.capability.join(' ')}"
          end

          case (@conf[:auth_type])
          when 'login'
            res = imap.login(@conf[:username], @conf[:password])
            puts "login: #{imap_res2str(res)}" if @conf[:verbose]
          when 'plain', 'cram-md5'
            res = imap.authenticate(@conf[:auth_type], @conf[:username], @conf[:password])
            puts "authenticate: #{imap_res2str(res)}" if @conf[:verbose]
          else
            raise "unknown authentication type: #{@conf[:auth_type]}"
          end

          yield(imap)
        ensure
          imap.logout
        end
      end

      def make_imap_store_flags
        store_flags = []
        [ [ :store_flag_answered, :Answered ],
          [ :store_flag_flagged, :Flagged ],
          [ :store_flag_deleted, :Deleted ],
          [ :store_flag_seen, :Seen ],
          [ :store_flag_draft, :Draft ]
        ].each do |key, flag|
          if (@conf[key]) then
            store_flags << flag
          end
        end
        puts "store flags: (#{store_flags.join(' ')})" if @conf[:verbose]

        store_flags
      end

      def look_for_date(message_text, path=nil)
        case (@conf[:look_for_date])
        when :servertime
          nil
        when :localtime
          Time.now
        when :filetime
          if (path) then
            File.stat(path).mtime
          end
        when :mailheader
          RFC822::Message.new(message_text).date
        else
          raise "failed to look for date: #{place}"
        end
      end

      def make_kvs_factory
        builder = KeyValueStore::FactoryBuilder.new
        builder.open{|name| @conf[:key_value_store_type].open_with_conf(name, {}) }
        if (@conf[:use_key_value_store_checksum]) then
          builder.use(Checksum_KeyValueStore)
        end
        builder.factory
      end
    end

    def cmd_daemon(options, args)
      conf = Config.new(options,
                        [ [ :use_status_code,
                            true,
                            '--[no-]status-code',
                            "Return the result of `status' operation as an exit code."
                          ],
                          [ :is_daemon,
                            nil,
                            '--[no-]daemon',
                            'Obsoleted.'
                          ],
                          [ :is_syslog,
                            nil,
                            '--[no-]syslog',
                            'Obsoleted.'
                          ]
                        ])
      conf.help_option(add_banner: ' start/stop/restart/status [server options]')
      conf.quiet_option
      conf.setup_option_list
      conf.parse_options!(args, order: true)
      pp args if $DEBUG

      operation = args.shift or raise 'need for daemon operation.'
      server_options = OptionParser.new
      build = make_service_config(server_options)
      server_options.parse!(args)

      unless (conf[:is_daemon].nil?) then
        warn("warning: `--[no-]daemon' is obsoleted option and no effect. use server option `--[no-]daemonize'.")
      end
      unless (conf[:is_syslog].nil?) then
        warn("warning: `--[no-]syslog' is obsoleted option and no effect.")
      end

      svc_conf = build.call
      pp svc_conf if $DEBUG

      status_file_locked = lambda{
        begin
          File.open(svc_conf.status_file, File::WRONLY) {|lock_file|
            ! lock_file.flock(File::LOCK_EX | File::LOCK_NB)
          }
        rescue Errno::ENOENT
          false
        end
      }

      start_daemon = lambda{
        Riser::Daemon.start_daemon(daemonize: svc_conf.daemonize?,
                                   daemon_name: svc_conf.daemon_name,
                                   daemon_debug: svc_conf.daemon_debug?,
                                   daemon_umask: svc_conf.daemon_umask,
                                   status_file: svc_conf.status_file,
                                   listen_address: proc{
                                     # to reload on server restart
                                     build.call.listen_address
                                   },
                                   server_polling_interval_seconds: svc_conf.server_polling_interval_seconds,
                                   server_restart_overlap_seconds: svc_conf.server_restart_overlap_seconds,
                                   server_privileged_user: svc_conf.server_privileged_user,
                                   server_privileged_group: svc_conf.server_privileged_group
                                  ) {|server|
          c = build.call        # to reload on server restart
          service = RIMS::Service.new(c)
          service.setup(server, daemon: true)
        }
      }

      case (operation)
      when 'start'
        start_daemon.call
      when 'stop'
        if (status_file_locked.call) then
          pid = YAML.load(IO.read(svc_conf.status_file))['pid']
          Process.kill(Riser::Daemon::SIGNAL_STOP_GRACEFUL, pid)
        else
          abort('No daemon.')
        end
      when 'restart'
        if (status_file_locked.call) then
          pid = YAML.load(IO.read(svc_conf.status_file))['pid']
          Process.kill(Riser::Daemon::SIGNAL_RESTART_GRACEFUL, pid)
        else
          start_daemon.call
        end
      when 'status'
        if (status_file_locked.call) then
          puts 'daemon is running.' if conf[:verbose]
          return 0 if conf[:use_status_code]
        else
          puts 'daemon is stopped.' if conf[:verbose]
          return 1 if conf[:use_status_code]
        end
      else
        raise "unknown daemon operation: #{operation}"
      end

      0
    end
    command_function :cmd_daemon, "Daemon start/stop/status tool."

    def cmd_environment(options, args)
      format = {
        yaml: lambda{|env|
          YAML.dump(env)
        },
        json: lambda{|env|
          JSON.pretty_generate(env)
        }
      }

      conf = Config.new(options,
                        [ [ :format_type,
                            format.keys.first,
                            '--format=FORMAT',
                            format.keys,
                            "Choose display format (#{format.keys.join(' ')})."
                          ]
                        ])
      conf.required_feature_option
      conf.setup_option_list
      conf.parse_options!(args)

      env = {
        'RIMS Environment' => [
          { 'RUBY VERSION' => RUBY_DESCRIPTION },
          { 'RIMS VERSION' => RIMS::VERSION },
          { 'AUTHENTICATION PLUG-IN' => Authentication.plug_in_names },
          { 'KEY-VALUE STORE PLUG-IN' => KeyValueStore::FactoryBuilder.plug_in_names }
        ]
      }

      formatter = format[conf[:format_type]]
      puts formatter.call(env)

      0
    end
    command_function :cmd_environment, 'Show rims environment.'

    def imap_append(imap, mailbox, message, store_flags: [], date_time: nil, verbose: false)
      puts "message date: #{date_time}" if (verbose && date_time)
      store_flags = nil if store_flags.empty?
      res = imap.append(mailbox, message, store_flags, date_time)
      puts "append: #{imap_res2str(res)}" if verbose
      nil
    end
    module_function :imap_append

    def each_message(args, verbose: false)
      if (args.empty?) then
        msg_txt = STDIN.read
        yield(msg_txt, nil)
        return 0
      else
        error_count = 0
        args.each_with_index do |filename, i|
          puts "progress: #{i + 1}/#{args.length}" if verbose
          begin
            msg_txt = IO.read(filename, mode: 'rb', encoding: 'ascii-8bit')
            yield(msg_txt, filename)
          rescue
            error_count += 1
            puts "failed to append message: #{filename}"
            Error.trace_error_chain($!) do |exception|
              puts "error: #{exception}"
              if ($DEBUG) then
                for frame in exception.backtrace
                  puts frame
                end
              end
            end
          end
        end

        if (error_count > 0) then
          puts "#{error_count} errors!"
          return 1
        else
          return 0
        end
      end
    end
    module_function :each_message

    def cmd_post_mail(options, args)
      STDIN.set_encoding(Encoding::ASCII_8BIT)

      option_list =
        Config::VERBOSE_OPTION_LIST +
        Config::POST_MAIL_CONNECT_OPTION_LIST +
        Config::IMAP_MAILBOX_OPTION_LIST +
        Config::IMAP_STORE_FLAG_OPTION_LIST +
        Config::MAIL_DATE_OPTION_LIST

      conf = Config.new(options, option_list)
      conf.help_option(add_banner: ' [POST USER] [MESSAGE_FILEs]')
      conf.load_config_option
      conf.setup_option_list
      conf.imap_debug_option
      conf.parse_options!(args)

      post_user = args.shift or raise 'need for post user.'

      store_flags = conf.make_imap_store_flags
      conf.imap_connect{|imap|
        unless (imap.capability.find{|c| c == 'X-RIMS-MAIL-DELIVERY-USER' }) then
          warn('warning: This IMAP server might not support RIMS mail delivery protocol.')
        end
        each_message(args) do |msg_txt, filename|
          t = conf.look_for_date(msg_txt, filename)
          encoded_mbox_name = Protocol::Decoder.encode_delivery_target_mailbox(post_user, conf[:mailbox])
          imap_append(imap, encoded_mbox_name, msg_txt, store_flags: store_flags, date_time: t, verbose: conf[:verbose])
        end
      }
    end
    command_function :cmd_post_mail, "Post mail to any user."

    def cmd_imap_append(options, args)
      STDIN.set_encoding(Encoding::ASCII_8BIT)

      option_list =
        Config::VERBOSE_OPTION_LIST +
        Config::IMAP_CONNECT_OPTION_LIST +
        Config::IMAP_MAILBOX_OPTION_LIST +
        Config::IMAP_STORE_FLAG_OPTION_LIST +
        Config::MAIL_DATE_OPTION_LIST

      conf = Config.new(options, option_list)
      conf.help_option(add_banner: ' [MESSAGE_FILEs]')
      conf.load_config_option
      conf.setup_option_list
      conf.imap_debug_option
      conf.parse_options!(args)

      store_flags = conf.make_imap_store_flags
      conf.imap_connect{|imap|
        each_message(args) do |msg_txt, filename|
          t = conf.look_for_date(msg_txt, filename)
          imap_append(imap, conf[:mailbox], msg_txt, store_flags: store_flags, date_time: t, verbose: conf[:verbose])
        end
      }
    end
    command_function :cmd_imap_append, "Append message to IMAP mailbox."

    def cmd_mbox_dirty_flag(options, args)
      option_list = [
        [ :return_flag_exit_code, true, '--[no-]return-flag-exit-code', 'Dirty flag value is returned to exit code. default is true.' ]
      ]

      conf = Config.new(options, option_list)
      conf.required_feature_option
      conf.key_value_store_option
      conf.help_option(add_banner: ' [mailbox directory]')
      conf.quiet_option
      conf.setup_option_list

      write_dirty_flag = nil
      options.on('--enable-dirty-flag', 'Enable mailbox dirty flag.') { write_dirty_flag = true }
      options.on('--disable-dirty-flag', 'Disable mailbox dirty flag.') { write_dirty_flag = false }

      conf.parse_options!(args)
      pp conf if $DEBUG

      mbox_dir = args.shift or raise 'need for mailbox directory.'
      meta_db_path = File.join(mbox_dir, 'meta')
      unless (conf[:key_value_store_type].exist? meta_db_path) then
        raise "not found a mailbox meta DB: #{meta_db_path}"
      end

      kvs_factory = conf.make_kvs_factory
      meta_db = DB::Meta.new(kvs_factory.call(File.join(mbox_dir, 'meta')))
      begin
        unless (write_dirty_flag.nil?) then
          meta_db.dirty = write_dirty_flag
        end

        if (conf[:verbose]) then
          puts "dirty flag is #{meta_db.dirty?}."
        end

        if (conf[:return_flag_exit_code]) then
          if (meta_db.dirty?) then
            1
          else
            0
          end
        else
          0
        end
      ensure
        meta_db.close
      end
    end
    command_function :cmd_mbox_dirty_flag, 'Show/enable/disable dirty flag of mailbox database.'

    def cmd_unique_user_id(options, args)
      options.banner += ' [username]'
      options.parse!(args)

      if (args.length != 1) then
        raise 'need for a username.'
      end
      username = args.shift

      puts Authentication.unique_user_id(username)

      0
    end
    command_function :cmd_unique_user_id, 'Show unique user ID from username.'

    def cmd_show_user_mbox(options, args)
      svc_conf = RIMS::Service::Configuration.new
      load_service_config = false

      options.banner += ' [base directory] [username] OR -f [config.yml path] [username]'
      options.on('-f', '--config-yaml=CONFIG_FILE',
                 String,
                 'Load optional parameters from CONFIG_FILE.') do |path|
        svc_conf.load_yaml(path)
        load_service_config = true
      end
      options.parse!(args)

      unless (load_service_config) then
        base_dir = args.shift or raise 'need for base directory.'
        svc_conf.load(base_dir: base_dir)
      end

      username = args.shift or raise 'need for a username.'
      unique_user_id = Authentication.unique_user_id(username)
      puts svc_conf.make_key_value_store_path(MAILBOX_DATA_STRUCTURE_VERSION, unique_user_id)

      0
    end
    command_function :cmd_show_user_mbox, "Show the path in which user's mailbox data is stored."

    def cmd_pass_hash(options, args)
      option_list = [
        [ :hash_type, 'SHA256', '--hash-type=DIGEST', String, 'Password hash type (ex SHA256, MD5, etc). default is SHA256.' ],
        [ :stretch_count, 10000, '--stretch-count=COUNT', Integer, 'Count to stretch password hash. default is 10000.' ],
        [ :salt_size, 16, '--salt-size=OCTETS', Integer, 'Size of salt string. default is 16 octets.' ]
      ]

      conf = Config.new(options, option_list)
      conf.help_option(add_banner: <<-'EOF'.chomp)
 passwd_plain.yml
Example
  $ cat passwd_plain.yml
  - { user: foo, pass: open_sesame }
  - { user: "#postman", pass: "#postman" }
  $ rims pass-hash passwd_plain.yml >passwd_hash.yml
  $ cat passwd_hash.yml
  ---
  - user: foo
    hash: SHA256:10000:YkslZucwN2QJ7LOft59Pgw==:d5dca9109cc787220eba65810e40165079ce3292407e74e8fbd5c6a8a9b12204
  - user: "#postman"
    hash: SHA256:10000:6Qj/wAYmb7NUGdOy0N35qg==:e967e46b8e0d9df6324e66c7e42da64911a8715e06a123fe5abf7af4ca45a386
Options:
      EOF
      conf.setup_option_list
      conf.parse_options!(args)
      pp conf if $DEBUG

      case (args.length)
      when 0
        passwd, *_optional = YAML.load_stream(STDIN)
      when 1
        passwd, *_optional = File.open(args[0]) {|f| YAML.load_stream(f) }
      else
        raise ArgumentError, 'too many input files.'
      end

      digest_factory = Password::HashSource.search_digest_factory(conf[:hash_type])
      salt_generator = Password::HashSource.make_salt_generator(conf[:salt_size])

      for entry in passwd
        pass = entry.delete('pass') or raise "not found a `pass' entry."
        entry['hash'] = Password::HashSource.make_entry(digest_factory, conf[:stretch_count], salt_generator.call, pass).to_s
      end

      puts passwd.to_yaml

      0
    end
    command_function :cmd_pass_hash, 'Make hash password configuration file from plain password configuration file.'

    def cmd_debug_dump_kvs(options, args)
      option_list = [
        [ :match_key, nil, '--match-key=REGEXP', Regexp, 'Show keys matching regular expression.' ],
        [ :dump_size, true, '--[no-]dump-size', 'Dump size of value with key.' ],
        [ :dump_value, true, '--[no-]dump-value', 'Dump value with key.' ],
        [ :marshal_restore, true, '--[no-]marshal-restore', 'Restore serialized object.' ]
      ]

      conf = Config.new(options, option_list)
      conf.required_feature_option
      conf.key_value_store_option
      conf.help_option(add_banner: ' [DB_NAME]')
      conf.setup_option_list
      conf.parse_options!(args)
      pp conf if $DEBUG

      name = args.shift or raise 'need for DB name.'
      unless (conf[:key_value_store_type].exist? name) then
        raise "not found a key-value store: #{name}"
      end

      factory = conf.make_kvs_factory
      db = factory.call(name)
      begin
        db.each_key do |key|
          if (conf[:match_key] && (key !~ conf[:match_key])) then
            next
          end

          entry = key.inspect
          if (conf[:dump_size]) then
            size = db[key].bytesize
            entry += ": #{size} bytes"
          end
          if (conf[:dump_value]) then
            v = db[key]
            if (conf[:marshal_restore]) then
              begin
                v = Marshal.restore(v)
              rescue
                # not marshal object!
              end
            end
            entry += ": #{v.inspect}"
          end

          puts entry
        end
      ensure
        db.close
      end

      0
    end
    command_function :cmd_debug_dump_kvs, "Dump key-value store contents."
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
