# -*- coding: utf-8 -*-

require 'logger'
require 'yaml'

module RIMS
  class Daemon
    class ExclusiveStatusFile
      def initialize(filename)
        @filename = filename
        @file = nil
        @is_locked = false
      end

      def open
        if (block_given?) then
          open
          begin
            r = yield
          ensure
            close
          end
          return r
        end

        begin
          @file = File.open(@filename, File::WRONLY | File::CREAT, 0640)
        rescue SystemCallError
          @fiile = File.open(@filename, File::WRONLY)
        end

        self
      end

      def close
        @file.close
        self
      end

      def locked?
        @is_locked
      end

      def should_be_locked
        unless (locked?) then
          raise "not locked: #{@filename}"
        end
        self
      end

      def should_not_be_locked
        if (locked?) then
          raise "already locked: #{@filename}"
        end
        self
      end

      def lock
        should_not_be_locked
        unless (@file.flock(File::LOCK_EX | File::LOCK_NB)) then
          raise "locked by another process: #{@filename}"
        end
        @is_locked = true
        self
      end

      def unlock
        should_be_locked
        @file.flock(File::LOCK_UN)
        @is_locked = false
        self
      end

      def synchronize
        lock
        begin
          yield
        ensure
          unlock
        end
      end

      def write(text)
        should_be_locked

        @file.truncate(0)
        @file.syswrite(text)

        self
      end
    end

    class ReadableStatusFile
      def initialize(filename)
        @filename = filename
        @file = nil
      end

      def open
        if (block_given?) then
          open
          begin
            r = yield
          ensure
            close
          end
          return r
        end

        @file = File.open(@filename, File::RDONLY)

        self
      end

      def close
        @file.close
        self
      end

      def locked?
        if (@file.flock(File::LOCK_EX | File::LOCK_NB)) then
          @file.flock(File::LOCK_UN)
          false
        else
          true
        end
      end

      def should_be_locked
        unless (locked?) then
          raise "not locked: #{@filename}"
        end
        self
      end

      def read
        should_be_locked
        @file.seek(0)
        @file.read
      end
    end

    def self.new_status_file(filename, exclusive: false)
      if (exclusive) then
        ExclusiveStatusFile.new(filename)
      else
        ReadableStatusFile.new(filename)
      end
    end

    def self.make_stat_file_path(base_dir)
      File.join(base_dir, 'status')
    end

    RELOAD_SIGNAL_LIST = %w[ HUP ]
    RESTART_SIGNAL_LIST = %w[ USR1 ]
    STOP_SIGNAL_LIST = %w[ TERM INT ]

    RELOAD_SIGNAL = RELOAD_SIGNAL_LIST[0]
    RESTART_SIGNAL = RESTART_SIGNAL_LIST[0]
    STOP_SIGNAL = STOP_SIGNAL_LIST[0]

    SERVER_RESTART_INTERVAL_SECONDS = 5

    class ChildProcess
      # return self if child process has been existed.
      # return nil if no child process.
      def self.cleanup_terminated_process(logger)
        begin
          while (pid = Process.waitpid(-1))
            if ($?.exitstatus != 0) then
              logger.warn("aborted child process: #{pid} (#{$?.exitstatus})")
            end
            yield(pid) if block_given?
          end
        rescue Errno::ECHILD
          return
        end

        self
      end

      def initialize(logger=Logger.new(STDOUT))
        @logger = logger
        @pid = run{ yield }
      end

      attr_reader :pid

      def run
        begin
          pipe_in, pipe_out = IO.pipe
          pid = Process.fork{
            @logger.close
            pipe_in.close

            status_code = catch(:rims_daemon_child_process_stop) {
              for sig_name in RELOAD_SIGNAL_LIST + RESTART_SIGNAL_LIST
                Signal.trap(sig_name, :DEFAULT)
              end
              for sig_name in STOP_SIGNAL_LIST
                Signal.trap(sig_name) { throw(:rims_daemon_child_process_stop, 0) }
              end

              pipe_out.puts("child process (pid: #{$$}) is ready to go.")
              pipe_out.close

              yield
            }
            exit!(status_code)
          }
        rescue
          @logger.error("failed to fork new child process: #{$!}")
          return
        end

        begin
          pipe_out.close
          s = pipe_in.gets
          @logger.info("[child process message] #{s}") if $DEBUG
          pipe_in.close
        rescue
          @logger.error("failed to start new child process: #{$!}")
          begin
            Process.kill(STOP_SIGNAL, pid)
          rescue SystemCallError
            @logger.warn("failed to kill abnormal child process: #{$!}")
          end
          return
        end

        pid
      end
      private :run

      def forked?
        @pid != nil
      end

      def terminate
        begin
          Process.kill(STOP_SIGNAL, @pid)
        rescue SystemCallError
          @logger.warn("failed to terminate child process: #{@pid}")
        end

        nil
      end
    end

    def initialize(stat_file_path, logger=Logger.new(STDOUT), server_options: [])
      @stat_file = self.class.new_status_file(stat_file_path, exclusive: true)
      @logger = logger
      @server_options = server_options
      @server_running = true
      @server_process = nil
    end

    def new_server_process
      ChildProcess.new(@logger) { Cmd.run_cmd(%w[ server ] + @server_options) }
    end
    private :new_server_process

    def run
      @stat_file.open{
        @stat_file.synchronize{
          @stat_file.write({ 'pid' => $$ }.to_yaml)
          begin
            @logger.info('start daemon.')
            loop do
              break unless @server_running

              unless (@server_process && @server_process.forked?) then
                start_time = Time.now
                @server_process = new_server_process
                @logger.info("run server process: #{@server_process.pid}")
              end

              break unless @server_running

              ChildProcess.cleanup_terminated_process(@logger) do |pid|
                if (@server_process.pid == pid) then
                  @server_process = nil
                end
              end

              break unless @server_running

              elapsed_seconds = Time.now - start_time
              the_rest_in_interval_seconds = SERVER_RESTART_INTERVAL_SECONDS - elapsed_seconds
              sleep(the_rest_in_interval_seconds) if (the_rest_in_interval_seconds > 0)
            end
          ensure
            if (@server_process && @server_process.forked?) then
              @server_process.terminate
              ChildProcess.cleanup_terminated_process(@logger)
            end
            @logger.info('stop daemon.')
          end
        }
      }

      self
    end

    # signal trap hook.
    # this method is not true reload.
    def reload_server
      restart_server
    end

    # signal trap hook.
    def restart_server
      @stat_file.should_be_locked
      if (@server_process && @server_process.forked?) then
        @server_process.terminate
      end

      self
    end

    # signal trap hook.
    def stop_server
      @stat_file.should_be_locked
      @server_running = false
      if (@server_process && @server_process.forked?) then
        @server_process.terminate
      end

      self
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
