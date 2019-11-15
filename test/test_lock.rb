# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

Thread.abort_on_exception = true if $DEBUG

module RIMS::Test
  class ReadWriteLockTest < Test::Unit::TestCase
    def setup
      @lock = RIMS::ReadWriteLock.new
    end

    def test_read_lock
      count = 0
      @lock.read_synchronize{ count += 1 }
      assert_equal(1, count)
    end

    def test_read_lock_simultaneous
      count = 0
      @lock.read_synchronize{
        @lock.read_synchronize{
          count += 1
        }
      }
      assert_equal(1, count)
    end

    def test_write_lock
      count = 0
      @lock.write_synchronize{ count += 1 }
      assert_equal(1, count)
    end

    def test_read_lock_timeout
      error = assert_raise(RIMS::ReadLockTimeoutError) {
        @lock.write_synchronize{
          @lock.read_synchronize(0) {}
        }
      }
      assert_equal('read-lock wait timeout', error.message)
    end

    def test_write_lock_timeout
      error = assert_raise(RIMS::WriteLockTimeoutError) {
        @lock.write_synchronize{
          @lock.write_synchronize(0) {}
        }
      }
      assert_equal('write-lock wait timeout', error.message)
    end

    def calculate_thread_work_seconds
      t0 = Time.now
      1000.times{|i| i.succ }
      t1 = Time.now
      wait_seconds = t1 - t0
      p format('%.9f', wait_seconds) if $DEBUG

      wait_seconds
    end
    private :calculate_thread_work_seconds

    def test_read_write_lock_multithread
      lock_wait_seconds = calculate_thread_work_seconds

      count = 0
      read_thread_num = 10
      write_thread_num = 5
      write_loop_num = 100

      mutex = Thread::Mutex.new
      end_of_read = false

      read_thread_list = []
      read_thread_num.times do |i|
        read_thread_list << Thread.new(i) {|th_id|
          until (mutex.synchronize{ end_of_read })
            @lock.read_synchronize{
              sleep(lock_wait_seconds)
              assert(count >= 0, "read thread #{th_id}")
            }
          end
        }
      end

      sleep(lock_wait_seconds)

      write_thread_list = []
      write_thread_num.times do |i|
        write_thread_list << Thread.new(i) {|th_id|
          write_loop_num.times do
            @lock.write_synchronize{
              tmp_count = count
              count = -1
              sleep(lock_wait_seconds)
              count = tmp_count + 1
            }
          end
        }
      end

      for t in write_thread_list
        t.join
      end

      mutex.synchronize{ end_of_read = true }
      for t in read_thread_list
        t.join
      end

      assert_equal(write_loop_num * write_thread_num, count)
    end

    def test_write_lock_timeout_detach
      logger = Logger.new(STDOUT)
      logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL
      wait_seconds = calculate_thread_work_seconds

      t_list = []
      assert_nil(RIMS::ReadWriteLock.write_lock_timeout_detach(wait_seconds, wait_seconds * 2, logger: logger ) {|timeout_seconds|
                   @lock.write_synchronize(timeout_seconds) { t_list << timeout_seconds }
                 })
      assert_equal([ wait_seconds ], t_list)

      t_list = []
      detached_thread = nil
      @lock.write_synchronize{
        detached_thread = RIMS::ReadWriteLock.write_lock_timeout_detach(wait_seconds, wait_seconds * 2, logger: logger ) {|timeout_seconds|
          @lock.write_synchronize(timeout_seconds) { t_list << timeout_seconds }
        }
        assert_instance_of(Thread, detached_thread)
        10.times do
          sleep(wait_seconds)
        end
      }

      assert_nil(detached_thread.value)
      assert_equal([ wait_seconds * 2 ], t_list)

      detached_thread = nil
      @lock.write_synchronize{
        detached_thread = RIMS::ReadWriteLock.write_lock_timeout_detach(wait_seconds, wait_seconds * 2, logger: logger ) {|timeout_seconds|
          @lock.write_synchronize(timeout_seconds) { raise 'test' }
        }
        assert_instance_of(Thread, detached_thread)
        10.times do
          sleep(wait_seconds)
        end
      }

      assert(error = detached_thread.value)
      assert_equal('test', error.message)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:

