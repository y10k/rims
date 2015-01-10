# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'test/unit'

module RIMS::Test
  class DaemonWaitpidTest < Test::Unit::TestCase
    def setup
      @child_pid_list = []
    end

    def teardown
      for pid in @child_pid_list
	begin
	  unless (Process.waitpid(pid, Process::WNOHANG)) then
	    Process.kill('KILL', pid)
	    Process.wait
	  end
	rescue SystemCallError
	  next
	end
      end
    end

    def fork_child_process
      latch_in, latch_out = IO.pipe

      pid = fork{
	latch_out.close
	latch_in.gets
	yield
	exit!
      }
      @child_pid_list << pid
      latch_in.close

      return latch_out, pid
    end
    private :fork_child_process

    def until_child_process_exit
      until (pid = yield)
	# nothing to do.
      end

      pid
    end
    private :until_child_process_exit

    def test_waitpid
      latch_out1, pid1 = fork_child_process{ exit!(0) }
      latch_out2, pid2 = fork_child_process{ exit!(1) }
      latch_out3, pid3 = fork_child_process{ exit!(2) }

      assert_nil(Process.waitpid(-1, Process::WNOHANG))

      latch_out3.puts
      assert_equal(pid3, until_child_process_exit{ Process.waitpid(-1) })

      latch_out1.puts
      assert_equal(pid1, until_child_process_exit{ Process.waitpid(-1) })

      latch_out2.puts
      assert_equal(pid2, until_child_process_exit{ Process.waitpid(-1) })
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
