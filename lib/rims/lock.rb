# -*- coding: utf-8 -*-

require 'logger'

module RIMS
  class LockError < Error
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
      time_limit = Time.now + timeout_seconds
      @lock.synchronize{
        while (@writing || (@prefer_to_writer && @count_of_standby_writers > 0))
          if (timeout_seconds > 0) then
            @read_cond.wait(@lock, timeout_seconds)
          else
            raise ReadLockTimeoutError, 'read-lock wait timeout'
          end
          timeout_seconds = time_limit - Time.now
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
      time_limit = Time.now + timeout_seconds
      @lock.synchronize{
        @count_of_standby_writers += 1
        begin
          while (@writing || @count_of_working_readers > 0)
            if (timeout_seconds > 0) then
              @write_cond.wait(@lock, timeout_seconds)
            else
              raise WriteLockTimeoutError, 'write-lock wait timeout'
            end
            timeout_seconds = time_limit - Time.now
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

    def self.write_lock_timeout_detach(first_timeout_seconds, detached_timeout_seconds, logger: Logger.new(STDOUT)) # yields: timeout_seconds
      begin
        logger.debug('ready to detach write-lock timeout.')
        yield(first_timeout_seconds)
        logger.debug('not detached write-lock timeout.')
        nil
      rescue WriteLockTimeoutError
        logger.warn($!)
        Thread.new{
          begin
            logger.warn('detached write-lock timeout.')
            yield(detached_timeout_seconds)
            logger.info('detached write-lock timeout thread is completed.')
            nil
          rescue WriteLockTimeoutError
            logger.warn($!)
            retry
          rescue
            logger.error('unexpected error at a detached thread and give up to retry write-lock timeout error.')
            Error.trace_error_chain($!) do |exception|
              logger.error(exception)
            end

            $!
          end
        }
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
