# -*- coding: utf-8 -*-

require 'fileutils'
require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class DaemonStatusFileTest < Test::Unit::TestCase
    def setup
      @stat_path = "status.#{$$}"
      @stat_file = RIMS::Daemon.new_status_file(@stat_path, exclusive: true)
      @ready_spin_lock = "ready_spin_lock.#{$$}"
      @final_spin_lock = "final_spin_lock.#{$$}"
    end

    def teardown
      FileUtils.rm_f(@stat_path)
      FileUtils.rm_f(@ready_spin_lock)
      FileUtils.rm_f(@final_spin_lock)
    end

    def test_lock_status
      @stat_file.open{
        assert_equal(false, @stat_file.locked?)
        @stat_file.synchronize{
          assert_equal(true, @stat_file.locked?)
        }
        assert_equal(false, @stat_file.locked?)
      }
    end

    def test_should_be_locked
      assert_raise(RuntimeError) {
        @stat_file.should_be_locked
      }

      @stat_file.open{
        @stat_file.synchronize{
          @stat_file.should_be_locked
        }
      }
    end

    def test_should_not_be_locked
      @stat_file.should_not_be_locked

      @stat_file.open{
        @stat_file.synchronize{
          assert_raise(RuntimeError) {
            @stat_file.should_not_be_locked
          }
        }
      }
    end

    def test_lock_guard
      @stat_file.open{
        @stat_file.synchronize{
          assert_raise(RuntimeError) {
            @stat_file.lock
          }
        }
      }
    end

    def test_unlock_guard
      @stat_file.open{
        assert_raise(RuntimeError) {
          @stat_file.unlock
        }
      }
    end

    def another_process_exclusive_lock
      FileUtils.touch(@ready_spin_lock)
      FileUtils.touch(@final_spin_lock)

      pid = Process.fork{
        lock_file = RIMS::Daemon.new_status_file(@stat_path, exclusive: true)
        lock_file.open{
          lock_file.synchronize{
            FileUtils.rm_f(@ready_spin_lock)
            while (File.exist? @final_spin_lock)
              # nothing to do.
            end
          }
        }
        exit!
      }

      while (File.exist? @ready_spin_lock)
        # nothing to do.
      end

      begin
        yield
      ensure
        FileUtils.rm_f(@final_spin_lock)
        Process.waitpid(pid)
      end
    end
    private :another_process_exclusive_lock

    def test_exclusive_lock
      another_process_exclusive_lock{
        @stat_file.open{
          assert_raise(RuntimeError) {
            @stat_file.synchronize{
              flunk("don't reach here.")
            }
          }
        }
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
