# -*- coding: utf-8 -*-

require 'fileutils'
require 'logger'
require 'socket'

module RIMS
  class Server
    def initialize(config)
      @store_dir = config['store_dir']
      @log_file = config['log_file']
      @user_name = config['username']
      @user_password = config['password']
      @ip_addr = config['IP_addr']
      @ip_port = config['IP_port']

      @passwd = proc{|name, password|
        name == @user_name && password == @user_password
      }
      @kvs_open = proc{|user_name, db_name|
        db_path = File.join(@store_dir, user_name, db_name)
        FileUtils.mkdir_p(File.dirname(db_path))
        GDBM_KeyValueStore.open(db_path)
      }

      @mail_store_pool = MailStorePool.new(@kvs_open, @kvs_open)
    end

    def open_log
      @logger = Logger.new(@log_file)
    end

    def start
      @logger.info("open server: #{@ip_addr}:#{@ip_port}")
      sv_sock = TCPServer.new(@ip_addr, @ip_port)

      loop do
        Thread.start(sv_sock.accept) {|cl_sock|
          begin
            @logger.info("accept client: #{cl_sock.peeraddr[1..2].reverse.join(':')}")
            decoder = Protocol::Decoder.new(@mail_store_pool, @passwd, @logger)
            begin
              Protocol::Decoder.repl(decoder, cl_sock, cl_sock, @logger)
            ensure
              decoder.cleanup
            end
          ensure
            cl_sock.close
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
  require 'rims'
  require 'yaml'

  if (ARGV.length != 1) then
    STDERR.puts "usage: #{$0} config.yml"
    exit(1)
  end

  config = YAML.load_file(ARGV[0])
  server = RIMS::Server.new(config)
  server.open_log
  server.start
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
