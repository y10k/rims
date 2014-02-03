# -*- coding: utf-8 -*-

require 'optparse'
require 'pp'if $DEBUG

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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
