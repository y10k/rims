# -*- coding: utf-8 -*-

require 'mail'
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
      cmd_name = method_name.sub(/^cmd_/, '').gsub(/_/, '-')
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
      STDERR.puts "usage: #{File.basename($0)} command options"
      STDERR.puts ""
      STDERR.puts "commands:"
      w = CMDs.keys.map{|k| k.length }.max + 4
      fmt = "    %- #{w}s%s"
      CMDs.each do |cmd_name, cmd_entry|
        STDERR.puts format(fmt, cmd_name, cmd_entry[:description])
      end
      STDERR.puts ""
      STDERR.puts "command help options:"
      STDERR.puts "    -h, --help"
      0
    end
    command_function :cmd_help, "Show this message."

    def cmd_server(options, args)
      conf = Config.new
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
      options.on('--kvs-type=TYPE', %w[ gdbm ],
                 "Choose the key-value store type of mailbox database. only GDBM can be chosen now.") do |type|
        conf.load(key_value_store_type: type)
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

      pp conf.config if $DEBUG
      conf.setup
      pp conf.config if $DEBUG

      server = RIMS::Server.new(**conf.config)
      server.start

      0
    end
    command_function :cmd_server, "Run IMAP server."

    def cmd_imap_append(options, args)
      date_place_list = [ :servertime, :localtime, :filetime, :mailheader ]
      option_list = [
        [ :verbose, false, '-v', '--[no-]verbose', "Enable verbose messages. default is no verbose." ],
        [ :imap_host, 'localhost', '-n', '--host=HOSTNAME', "Hostname or IP address to connect IMAP server. default is `localhost'." ],
        [ :imap_port, 143, '-o', '--port=PORT', Integer, "Server port number or service name to connect IMAP server. default is 143." ],
        [ :imap_ssl, false, '-s', '--[no-]use-ssl', "Enable SSL/TLS connection. default is disabled." ],
        [ :username, nil, '-u', '--username=NAME', "Username to login IMAP server. required parameter to connect server." ],
        [ :password, nil, '-w', '--password=PASS', "Password to login IMAP server. required parameter to connect server." ],
        [ :mailbox, 'INBOX', '-m', '--mailbox=NAME', "Set mailbox name to append messages. default is `INBOX'." ],
        [ :store_flag_answered, false, '--[no-]store-flag-answered', "Store answered flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_flagged, false, '--[no-]store-flag-flagged', "Store flagged flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_deleted, false, '--[no-]store-flag-deleted', "Store deleted flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_seen, false, '--[no-]store-flag-seen', "Store seen flag on appending messages to mailbox. default is no flag." ],
        [ :store_flag_draft, false, '--[no-]store-flag-draft', "Store draft flag on appending messages to mailbox. default is no flag." ],
        [ :look_for_date, :servertime, '--look-for-date=PLACE', date_place_list,
          "Choose the place (#{date_place_list.join(' ')}) to look for the date that as internaldate is appended with message. default is `servertime'." ]
      ]

      conf = {}
      for key, value, *option_description in option_list
        conf[key] = value
      end

      options.banner += ' [MESSAGE_FILEs]'
      options.on('-h', '--help', 'Show this message.')do
        puts options
        exit
      end
      options.on('-f', '--config-yaml=CONFIG_FILE',
                 "Load optional parameters from CONFIG_FILE.") do |path|
        for name, value in YAML.load_file(path)
          conf[name.to_sym] = value
        end
      end
      option_list.each do |key, value, *option_description|
        options.on(*option_description) do |v|
          conf[key] = v
        end
      end
      options.on('--[no-]imap-debug',
                 "Set the debug flag of Net::IMAP class. default is false.") do |v|
        Net::IMAP.debug = v
      end
      options.parse!(args)
      pp conf if $DEBUG

      unless (conf[:username] && conf[:password]) then
        raise 'need for username and password.'
      end

      store_flags = []
      [ [ :store_flag_answered, :Answered ],
        [ :store_flag_flagged, :Flagged ],
        [ :store_flag_deleted, :Deleted ],
        [ :store_flag_seen, :Seen ],
        [ :store_flag_draft, :Draft ]
      ].each do |key, flag|
        if (conf[key]) then
          store_flags << flag
        end
      end
      puts "store flags: (#{store_flags.join(' ')})" if conf[:verbose]

      imap = Net::IMAP.new(conf[:imap_host], port: conf[:imap_port], ssl: conf[:imap_ssl])
      begin
        if (conf[:verbose]) then
          puts "server greeting: #{imap_res2str(imap.greeting)}"
          puts "server capability: #{imap.capability.join(' ')}"
        end

        res = imap.login(conf[:username], conf[:password])
        puts "login: #{imap_res2str(res)}" if conf[:verbose]
        if (args.empty?) then
          msg = STDIN.read
          t = look_for_date(conf[:look_for_date], msg)
          imap_append(imap, conf[:mailbox], msg, store_flags: store_flags, date_time: t, verbose: conf[:verbose])
        else
          error_count = 0
          args.each_with_index do |filename, i|
            puts "progress: #{i + 1}/#{args.length}" if conf[:verbose]
            begin
              msg = IO.read(filename, mode: 'rb', encoding: 'ascii-8bit')
              t = look_for_date(conf[:look_for_date], msg, filename)
              imap_append(imap, conf[:mailbox], msg, store_flags: store_flags, date_time: t, verbose: conf[:verbose])
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
          end
        end
      ensure
        imap.logout
      end

      0
    end
    command_function :cmd_imap_append, "Append message to IMAP mailbox."

    def imap_res2str(imap_response)
      "#{imap_response.name} #{imap_response.data.text}"
    end
    module_function :imap_res2str

    def look_for_date(place, messg, path=nil)
      case (place)
      when :servertime
        nil
      when :localtime
        Time.now
      when :filetime
        if (path) then
          File.stat(path).mtime
        end
      when :mailheader
        if (d = Mail.new(messg).date) then
          d.to_time
        end
      else
        raise "failed to look for date: #{place}"
      end
    end
    module_function :look_for_date

    def imap_append(imap, mailbox, message, store_flags: [], date_time: nil, verbose: false)
      puts "message date: #{date_time}" if (verbose && date_time)
      store_flags = nil if store_flags.empty?
      res = imap.append(mailbox, message, store_flags, date_time)
      puts "append: #{imap_res2str(res)}" if verbose
      nil
    end
    module_function :imap_append
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
