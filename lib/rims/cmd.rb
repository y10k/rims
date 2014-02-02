# -*- coding: utf-8 -*-

module RIMS
  module Cmd
    CMDs = {}

    def self.command_function(method_name)
      module_function(method_name)
      method_name = method_name.to_s
      cmd_name = method_name.sub(/^cmd_/, '')
      CMDs[cmd_name] = method_name.to_sym
    end

    def run_cmd(args)
      if (args.empty?) then
        cmd_help(args)
        return 1
      end

      cmd_name = args.shift
      if (method_name = CMDs[cmd_name]) then
        send(method_name, args)
      else
        raise "unknown command: #{cmd_name}"
      end
    end
    module_function :run_cmd

    def cmd_help(args)
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

    def cmd_server(args)
      raise NotImplementedError, 'not implemented.'
    end
    command_function :cmd_server
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
