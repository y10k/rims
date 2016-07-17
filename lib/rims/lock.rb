# -*- coding: utf-8 -*-

module RIMS
  class LockError < StandardError
  end

  class IllegalLockError < LockError
  end

  class ReadLockError < LockError
  end

  class ReadLockTimeoutError < ReadLockError
  end

  class WriteLockError < LockError
  end

  class WriteLockTimeoutError < LockError
  end

  class ReadWriteLock
    DEFAULT_TIMEOUT_SECONDS = 300

    def initialize
      @lock = Thread::Mutex.new
      @read_cond = Thread::ConditionVariable.new
      @write_cond = Thread::ConditionVariable.new
      @count_of_working_readers = 0
      @count_of_standby_writers = 0
      @prefer_to_writer = true
      @writing = false
    end

    def read_lock(timeout_seconds=DEFAULT_TIMEOUT_SECONDS)
      t0 = Time.now
      @lock.synchronize{
        while (@writing || (@prefer_to_writer && @count_of_standby_writers > 0))
          @read_cond.wait(@lock, timeout_seconds)
          if (Time.now - t0 >= timeout_seconds) then
            raise ReadLockTimeoutError, "timeout over #{timeout_seconds}s since #{t0}"
          end
        end
        @count_of_working_readers += 1
      }
      nil
    end

    def read_unlock
      @lock.synchronize{
        @count_of_working_readers -= 1
        @count_of_working_readers >= 0 or raise IllegalLockError, 'illegal read lock pattern: lock/unlock/unlock'
        @prefer_to_writer = true
        if (@count_of_standby_writers > 0) then
          @write_cond.signal
        end
      }
      nil
    end

    def read_synchronize(timeout_seconds=DEFAULT_TIMEOUT_SECONDS)
      read_lock(timeout_seconds)
      begin
        yield
      ensure
        read_unlock
      end
    end

    def write_lock(timeout_seconds=DEFAULT_TIMEOUT_SECONDS)
      t0 = Time.now
      @lock.synchronize{
        @count_of_standby_writers += 1
        begin
          while (@writing || @count_of_working_readers > 0)
            @write_cond.wait(@lock, timeout_seconds)
            if (Time.now - t0 >= timeout_seconds) then
              raise WriteLockTimeoutError, "timeout over #{timeout_seconds}s since #{t0}"
            end
          end
          @writing = true
        ensure
          @count_of_standby_writers -= 1
        end
      }
      nil
    end

    def write_unlock
      @lock.synchronize{
        @writing or raise IllegalLockError, 'illegal write lock pattern: lock/unlock/unlock'
        @writing = false
        @prefer_to_writer = false
        @read_cond.broadcast
        if (@count_of_standby_writers > 0) then
          @write_cond.signal
        end
      }
      nil
    end

    def write_synchronize(timeout_seconds=DEFAULT_TIMEOUT_SECONDS)
      write_lock(timeout_seconds)
      begin
        yield
      ensure
        write_unlock
      end
    end

    # compatible for Thread::Mutex
    alias synchronize write_synchronize
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
