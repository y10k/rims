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
      assert_raise(RIMS::ReadLockTimeoutError) {
        @lock.write_synchronize{
          @lock.read_synchronize(0) {}
        }
      }
    end

    def test_write_lock_timeout
      assert_raise(RIMS::WriteLockTimeoutError) {
        @lock.write_synchronize{
          @lock.write_synchronize(0) {}
        }
      }
    end

    def test_read_write_lock_multithread
      t0 = Time.now
      1000.times{|i| i.succ }
      t1 = Time.now
      lock_wait = t1 - t0
      p format('%.9f', lock_wait) if $DEBUG

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
              sleep(lock_wait)
              assert(count >= 0, "read thread #{th_id}")
            }
          end
        }
      end

      sleep(lock_wait)

      write_thread_list = []
      write_thread_num.times do |i|
        write_thread_list << Thread.new(i) {|th_id|
          write_loop_num.times do
            @lock.write_synchronize{
              tmp_count = count
              count = -1
              sleep(lock_wait)
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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:

