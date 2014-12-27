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
      @read_file = RIMS::Daemon.new_status_file(@stat_path, exclusive: false)
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

    def another_process_exclusive_lock(write_text: nil)
      FileUtils.touch(@ready_spin_lock)
      FileUtils.touch(@final_spin_lock)

      pid = Process.fork{
        lock_file = RIMS::Daemon.new_status_file(@stat_path, exclusive: true)
        lock_file.open{
          lock_file.synchronize{
            lock_file.write(write_text) if write_text
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

    def test_readable_lock_status
      assert_raise(Errno::ENOENT) {
        @read_file.open
      }

      another_process_exclusive_lock{
        @read_file.open{
          assert_equal(true, @read_file.locked?)
        }
      }

      @read_file.open{
        assert_equal(false, @read_file.locked?)
      }
    end

    def test_readable_should_be_locked
      another_process_exclusive_lock{
        @read_file.open{
          @read_file.should_be_locked
        }
      }

      @read_file.open{
        assert_raise(RuntimeError) {
          @read_file.should_be_locked
        }
      }
    end

    def test_write_read
      another_process_exclusive_lock(write_text: "pid: #{$$}") {
        @read_file.open{
          assert_equal("pid: #{$$}", @read_file.read)
          assert_equal("pid: #{$$}", @read_file.read, 'rewind')
        }
      }

      @read_file.open{
        assert_raise(RuntimeError) {
          @read_file.read
        }
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
