# -*- coding: utf-8 -*-

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

    RELOAD_SIGNAL_LIST = %w[ HUP ]
    RESTART_SIGNAL_LIST = %w[ USR1 ]
    STOP_SIGNAL_LIST = %w[ TERM INT ]

    RELOAD_SIGNAL = RELOAD_SIGNAL_LIST[0]
    RESTART_SIGNAL = RESTART_SIGNAL_LIST[0]
    STOP_SIGNAL = STOP_SIGNAL_LIST[0]

    class ChildProcess
      def initialize
        @stat = nil
        @pid = run{ yield }
      end

      def run
        pipe_in, pipe_out = IO.pipe

        pid = Process.fork{
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
        pipe_out.close

        s = pipe_in.gets
        puts "[child process message] #{s}" if $DEBUG
        pipe_in.close

        pid
      end
      private :run

      # return nil if child process is alive.
      # return self if child process is dead.
      def wait(nohang: false)
        return self if @stat

        wait_flags = 0
        wait_flags |= Process::WNOHANG if nohang

        if (Process.waitpid(@pid, wait_flags)) then
          @stat = $?
          if (@stat.exitstatus != 0) then
            warn("warning: aborted child process: #{@pid} (#{$?.exitstatus})")
          end

          self
        end
      end

      def alive?
        if (@pid) then
          if (wait(nohang: true)) then
            false
          else
            true
          end
        end
      end

      def terminate
        begin
          Process.kill(STOP_SIGNAL, @pid)
          wait
        rescue SystemCallError
          warn("warning: failed to terminate child process: #{@pid}")
        end

        nil
      end
    end

    class SignalEventHandler
      def initialize
        @state = :init
      end

      def run?
        @state == :run
      end

      # call from main thread
      def event_loop
        continue = true

        begin
          while (continue)
            continue = catch(:rims_daemon_signal_event_loop) {
              begin
                @state = :run
                yield
              ensure
                @state = :wait
              end

              false
            }
          end
        ensure
          @state = :stop
        end

        nil
      end

      # call from Signal.trap handler
      def event_push(continue: true)
        throw(:rims_daemon_signal_event_loop, continue)
        nil
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
