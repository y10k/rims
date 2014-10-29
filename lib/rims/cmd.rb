# -*- coding: utf-8 -*-

require 'net/imap'
require 'optparse'
require 'pp'if $DEBUG
require 'yaml'

module RIMS
  module Cmd
    CMDs = {}

    def self.command_function(method_name, description)
      module_function(method_name)
      method_name = method_name.to_s
      unless (method_name =~ /^cmd_/) then
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

      STDERR.puts "usage: #{File.basename($0)} command options"
      STDERR.puts ""
      STDERR.puts "commands:"
      w = CMDs.keys.map{|k| k.length }.max + 4
      fmt = "    %- #{w}s%s"
      CMDs.each do |cmd_name, cmd_entry|
        if ((! show_debug_command) && (cmd_name =~ /^debug/)) then
          next
        end
        STDERR.puts format(fmt, cmd_name, cmd_entry[:description])
      end
      STDERR.puts ""
      STDERR.puts "command help options:"
      STDERR.puts "    -h, --help"
      0
    end
    command_function :cmd_help, "Show this message."

    def cmd_version(options, args)
      options.parse!(args)
      puts RIMS::VERSION
      0
    end
    command_function :cmd_version, 'Show software version.'

    def cmd_server(options, args)
      conf = RIMS::Config.new
      conf.load(base_dir: Dir.getwd)

      options.on('-h', '--help', 'Show this message.') do
        puts options
        exit
      end
      options.on('-f', '--config-yaml=CONFIG_FILE',
                 "Load optional parameters from CONFIG_FILE.") do |path|
        conf.load_config_yaml(path)
      end
      options.on('-d', '--base-dir=DIR',
                 "Directory that places log file, mailbox database, etc. default is current directory.") do |path|
        conf.load(base_dir: path)
      end
      options.on('--log-file=FILE',
                 "Name of log file. the directory part preceding file name is ignored. default is `imap.log'.") do |path|
        conf.load(log_file: path)
      end
      level_list = %w[ debug info warn error fatal ]
      options.on('-l', '--log-level=LEVEL', level_list,
                 "Logging level (#{level_list.join(' ')}). default is `info'.") do |level|
        conf.load(log_level: level)
      end
      options.on('--log-shift-age=NUMBER', Integer, 'Number of old log files to keep.') do |num|
        conf.load(log_shift_age: num)
      end
      options.on('--log-shift-age-daily', 'Frequency of daily log rotation.') do
        conf.load(log_shift_age: 'daily')
      end
      options.on('--log-shift-age-weekly', 'Frequency of weekly log rotation.') do
        conf.load(log_shift_age: 'weekly')
      end
      options.on('--log-shift-age-monthly', 'Frequency of monthly log rotation.') do
        conf.load(log_shift_age: 'monthly')
      end
      options.on('--log-shift-size=SIZE', Integer, 'Maximum logfile size.') do |size|
        conf.load(log_shift_size: size)
      end
      options.on('--kvs-type=TYPE', %w[ gdbm ],
                 "Choose the key-value store type of mailbox database. only GDBM can be chosen now.") do |type|
        conf.load(key_value_store_type: type)
      end
      options.on('--[no-]use-kvs-cksum',
                 "Enable/disable data checksum at key-value store. default is enabled.") do |use|
        conf.load(use_key_value_store_checksum: use)
      end
      options.on('-u', '--username=NAME',
                 "Username to login IMAP server. required parameter to start server.") do |name|
        conf.load(username: name)
      end
      options.on('-w', '--password=PASS',
                 "Password to login IMAP server. required parameter to start server.") do |pass|
        conf.load(password: pass)
      end
      options.on('--ip-addr=IP_ADDR',
                 "Local IP address or hostname for the server to bind. default is `0.0.0.0'.") do |ip_addr|
        conf.load(ip_addr: ip_addr)
      end
      options.on('--ip-port=PORT', Integer,
                 "Local port number or service name for the server to listen. default is 1430.") do |port|
        conf.load(ip_port: port)
      end
      options.parse!(args)

      server = conf.build_server
      server.start

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

      IMAP_AUTH_TYPE_LIST = %w[ login plain cram-md5 ]
      MAIL_DATE_PLACE_LIST = [ :servertime, :localtime, :filetime, :mailheader ]

      VERBOSE_OPTION_LIST = [
        [ :verbose, false, '-v', '--[no-]verbose', "Enable verbose messages. default is no verbose." ]
      ]

      def self.make_imap_connect_option_list(imap_host: 'localhost', imap_port: 143, imap_ssl: false, auth_type: 'login', username: nil)
        [ [ :imap_host, imap_host, '-n', '--host=HOSTNAME', "Hostname or IP address to connect IMAP server. default is `#{imap_host}'." ],
          [ :imap_port, imap_port, '-o', '--port=PORT', Integer, "Server port number or service name to connect IMAP server. default is #{imap_port}." ],
          [ :imap_ssl, imap_ssl, '-s', '--[no-]use-ssl', "Enable SSL/TLS connection. default is #{imap_ssl ? 'enabled' : 'disabled'}." ],
          [ :username, username, '-u', '--username=NAME',
            "Username to login IMAP server. " + if (username) then
                                                  "default is `#{username}'."
                                                else
                                                  "required parameter to connect server."
                                                end ],
          [ :password, nil, '-w', '--password=PASS', "Password to login IMAP server. required parameter to connect server." ],
          [ :auth_type, auth_type, '--auth-type=METHOD', IMAP_AUTH_TYPE_LIST,
            "Choose authentication method type (#{IMAP_AUTH_TYPE_LIST.join(' ')}). default is `#{auth_type}'." ]
        ]
      end

      IMAP_CONNECT_OPTION_LIST = self.make_imap_connect_option_list
      POST_MAIL_CONNECT_OPTION_LIST = self.make_imap_connect_option_list(imap_port: Server::DEFAULT[:ip_port],
                                                                         username: Server::DEFAULT[:mail_delivery_user])

      IMAP_MAILBOX_OPTION_LIST = [
        [ :mailbox, 'INBOX', '-m', '--mailbox=NAME', "Set mailbox name to append messages. default is `INBOX'." ]
      ]

      IMAP_STORE_FLAG_OPTION_LIST = [
        [ :store_flag_answered, false, '--[no-]store-flag-answered', "Store answered flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_flagged, false, '--[no-]store-flag-flagged', "Store flagged flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_deleted, false, '--[no-]store-flag-deleted', "Store deleted flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_seen, false, '--[no-]store-flag-seen', "Store seen flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_draft, false, '--[no-]store-flag-draft', "Store draft flag on appending messages to mailbox. default is no flag." ]
      ]

      MAIL_DATE_OPTION_LIST = [
        [ :look_for_date, :servertime, '--look-for-date=PLACE', MAIL_DATE_PLACE_LIST,
          "Choose the place (#{MAIL_DATE_PLACE_LIST.join(' ')}) to look for the date that as internaldate is appended with message. default is `servertime'."
        ]
      ]

      KVS_STORE_OPTION_LIST = [
        [ :key_value_store_type, 'gdbm', '--kvs-type=TYPE', %w[ gdbm ], "Choose the key-value store type. only gdbm can be chosen now." ],
        [ :use_key_value_store_checksum, true, '--[no-]use-kvs-cksum', "Enable/disable data checksum at key-value store. default is enabled." ]
      ]

      def initialize(options, option_list)
        @options = options
        @option_list = option_list
        @conf = {}
        for key, value, *option_description in option_list
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
                    "Load optional parameters from CONFIG_FILE.") do |path|
          for name, value in YAML.load_file(path)
            @conf[name.to_sym] = value
          end
        end

        self
      end

      def parse_options!(args)
        @options.parse!(args)
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

        imap = Net::IMAP.new(@conf[:imap_host], port: @conf[:imap_port], ssl: @conf[:imap_ssl])
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
          Error.suppress_2nd_error_at_resource_closing{ imap.logout }
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

      def make_kvs_factory(read_only: false)
        builder = KeyValueStore::FactoryBuilder.new
        case (@conf[:key_value_store_type].upcase)
        when 'GDBM'
          if (read_only) then
            builder.open{|name| GDBM_KeyValueStore.open(name, 0666, GDBM::READER) }
          else
            builder.open{|name| GDBM_KeyValueStore.open(name, 0666, GDBM::WRITER) }
          end
        else
          raise "unknown key-value store type: #{@conf[:key_value_store_type]}"
        end
        if (@conf[:use_key_value_store_checksum]) then
          builder.use(Checksum_KeyValueStore)
        end

        builder.factory
      end
    end

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
        yield(msg_txt)
        return 0
      else
        error_count = 0
        args.each_with_index do |filename, i|
          puts "progress: #{i + 1}/#{args.length}" if verbose
          begin
            msg_txt = IO.read(filename, mode: 'rb', encoding: 'ascii-8bit')
            yield(msg_txt)
          rescue
            error_count += 1
            puts "failed to append message: #{filename}"
            puts "error: #{$!}"
            if ($DEBUG) then
              for frame in $!.backtrace
                puts frame
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
        each_message(args) do |msg_txt|
          t = conf.look_for_date(msg_txt)
          encoded_mbox_name = Protocol::MailDeliveryDecoder.encode_user_mailbox(post_user, conf[:mailbox])
          imap_append(imap, encoded_mbox_name, msg_txt, store_flags: store_flags, date_time: t, verbose: conf[:verbose])
        end
      }
    end
    command_function :cmd_post_mail, "Post mail to any user."

    def cmd_imap_append(options, args)
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
        each_message(args) do |msg_txt|
          t = conf.look_for_date(msg_txt)
          imap_append(imap, conf[:mailbox], msg_txt, store_flags: store_flags, date_time: t, verbose: conf[:verbose])
        end
      }
    end
    command_function :cmd_imap_append, "Append message to IMAP mailbox."

    def cmd_mbox_dirty_flag(options, args)
      option_list = Config::KVS_STORE_OPTION_LIST
      option_list += [
        [ :return_flag_exit_code, true, '--[no-]return-flag-exit-code', 'Dirty flag value is returned to exit code. default is true.' ]
      ]

      conf = Config.new(options, option_list)
      write_dirty_flag = nil

      conf.help_option(add_banner: ' [mailbox directory]')
      conf.quiet_option
      conf.setup_option_list
      options.on('--enable-dirty-flag', 'Enable mailbox dirty flag.') { write_dirty_flag = true }
      options.on('--disable-dirty-flag', 'Disable mailbox dirty flag.') { write_dirty_flag = false }
      conf.parse_options!(args)
      pp conf, write_dirty_flag if $DEBUG

      mbox_dir = args.shift or raise 'need for mailbox directory.'
      kvs_factory = conf.make_kvs_factory(read_only: write_dirty_flag.nil?)
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
        Error.suppress_2nd_error_at_resource_closing{ meta_db.close }
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
      conf = RIMS::Config.new
      load_server_config = false

      options.banner += ' [base directory] [username] OR -f [config.yml path] [username]'
      options.on('-f', '--config-yaml=CONFIG_FILE',
                 'Load optional parameters from CONFIG_FILE.') do |path|
        conf.load_config_yaml(path)
        load_server_config = true
      end
      options.parse!(args)

      unless (load_server_config) then
        base_dir = args.shift or raise 'need for base directory.'
        conf.load(base_dir: base_dir)
      end

      username = args.shift or raise 'need for a username.'
      unique_user_id = Authentication.unique_user_id(username)
      puts conf.make_key_value_store_path_from_base_dir(MAILBOX_DATA_STRUCTURE_VERSION, unique_user_id)

      0
    end
    command_function :cmd_show_user_mbox, "Show the path in which user's mailbox data is stored."

    def cmd_debug_dump_kvs(options, args)
      option_list = Config::KVS_STORE_OPTION_LIST
      option_list += [
        [ :match_key, nil, '--match-key=REGEXP', Regexp, 'Show keys matching regular expression.' ],
        [ :dump_size, true, '--[no-]dump-size', 'Dump size of value with key.' ],
        [ :dump_value, true, '--[no-]dump-value', 'Dump value with key.' ],
        [ :marshal_restore, true, '--[no-]marshal-restore', 'Restore serialized object.' ]
      ]

      conf = Config.new(options, option_list)
      conf.help_option(add_banner: ' [DB_NAME]')
      conf.setup_option_list
      conf.parse_options!(args)
      pp conf if $DEBUG

      name = args.shift or raise 'need for DB name.'
      factory = conf.make_kvs_factory(read_only: true)
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
        Error.suppress_2nd_error_at_resource_closing{ db.close }
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
