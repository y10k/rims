# -*- coding: utf-8 -*-

require 'mail'
require 'net/imap'
require 'optparse'
require 'pp'if $DEBUG
require 'yaml'

module RIMS
  module Cmd
    CMDs = {}

    def self.command_function(method_name)
      module_function(method_name)
      method_name = method_name.to_s
      cmd_name = method_name.sub(/^cmd_/, '').gsub(/_/, '-')
      CMDs[cmd_name] = method_name.to_sym
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

      if (method_name = CMDs[cmd_name]) then
        options.program_name += " #{cmd_name}"
        send(method_name, options, args)
      else
        raise "unknown command: #{cmd_name}"
      end
    end
    module_function :run_cmd

    def cmd_help(options, args)
      STDERR.puts "usage: #{File.basename($0)} command options"
      STDERR.puts ""
      STDERR.puts "commands:"
      CMDs.each_key do |cmd_name|
        STDERR.puts "  #{cmd_name}"
      end
      STDERR.puts ""
      STDERR.puts "command help options:"
      STDERR.puts "  -h, --help"
      0
    end
    command_function :cmd_help

    def cmd_server(options, args)
      conf = Config.new
      conf.load(base_dir: Dir.getwd)

      options.on('-f', '--config-yaml=CONFIG_FILE') do |path|
        conf.load_config_yaml(path)
      end
      options.on('-d', '--base-dir=DIR', ) do |path|
        conf.load(base_dir: path)
      end
      options.on('--log-file=FILE') do |path|
        conf.load(log_file: path)
      end
      options.on('-l', '--log-level=LEVEL', %w[ debug info warn error fatal ]) do |level|
        conf.load(log_level: level)
      end
      options.on('--kvs-type=TYPE', %w[ gdbm ]) do |type|
        conf.load(key_value_store_type: type)
      end
      options.on('--username=NAME', String) do |name|
        conf.load(username: name)
      end
      options.on('--password=PASS') do |pass|
        conf.load(password: pass)
      end
      options.on('--ip-addr=IP_ADDR') do |ip_addr|
        conf.load(ip_addr: ip_addr)
      end
      options.on('--ip-port=PORT', Integer) do |port|
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
    command_function :cmd_server

    def cmd_imap_append(options, args)
      conf = {
        verbose: false,
        imap_host: 'localhost',
        imap_port: 1430,
        imap_ssl: false,
        username: nil,
        password: nil,
        mailbox: 'INBOX',
        look_for_date: :servertime
      }

      options.on('-v', '--[no-]verbose') do |v|
        conf[:verbose] = v
      end
      options.on('-f', '--config-yaml=CONFIG_FILE') do |path|
        for name, value in YAML.load_file(path)
          conf[name.to_sym] = value
        end
      end
      options.on('-n', '--host=HOSTNAME') do |host|
        conf[:imap_host] = host
      end
      options.on('-o', '--port=PORT', Integer) do |port|
        conf[:imap_port] = port
      end
      options.on('-s', '--[no-]use-ssl') do |v|
        conf[:imap_ssl] = v
      end
      options.on('-u', '--username=NAME') do |name|
        conf[:username] = name
      end
      options.on('-w', '--password=PASS') do |pass|
        conf[:password] = pass
      end
      options.on('-m', '--mailbox') do |mbox|
        conf[:mailbox] = mbox
      end
      options.on('--look-for-date=PLACE', [ :servertime, :localtime, :filetime, :mailheader ]) do |place|
        conf[:look_for_date] = place
      end
      options.on('--[no-]imap-debug') do |v|
        Net::IMAP.debug = v
      end
      options.parse!(args)
      pp conf if $DEBUG

      unless (conf[:username] && conf[:password]) then
        raise 'need for username and password.'
      end

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
          imap_append(imap, conf[:mailbox], msg, date_time: t, verbose: conf[:verbose])
        else
          for filename in args
            msg = IO.read(filename, mode: 'rb', encoding: 'ascii-8bit')
            t = look_for_date(conf[:look_for_date], msg, filename)
            imap_append(imap, conf[:mailbox], msg, date_time: t, verbose: conf[:verbose])
          end
        end
      ensure
        imap.logout
      end

      0
    end
    command_function :cmd_imap_append

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

    def imap_append(imap, mailbox, message, date_time: nil, verbose: false)
      puts "message date: #{date_time}" if (verbose && date_time)
      res = imap.append(mailbox, message, nil, date_time)
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
