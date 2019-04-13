# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class ProtocolConnectionTimerTest < Test::Unit::TestCase
    def setup
      @read_io, @write_io = IO.pipe
      @limits = RIMS::Protocol::ConnectionLimits.new(0.001, 0.1)
      @timer = RIMS::Protocol::ConnectionTimer.new(@limits, @read_io)
    end

    def teardown
      @write_io.close
      @read_io.close
    end

    def test_command_wait
      assert(! @timer.command_wait_timeout?)
      @write_io.write("foo\n")
      assert(@timer.command_wait)
      assert(! @timer.command_wait_timeout?)
      assert_equal("foo\n", @read_io.gets)
    end

    def test_command_wait_timeout
      assert(! @timer.command_wait_timeout?)
      assert(! @timer.command_wait)
      assert(@timer.command_wait_timeout?)
    end

    def test_command_wait_immediate
      @limits.command_wait_timeout_seconds = 0

      assert(! @timer.command_wait_timeout?)
      @write_io.write("foo\n")
      assert(@timer.command_wait)
      assert(! @timer.command_wait_timeout?)
      assert_equal("foo\n", @read_io.gets)
    end

    def test_command_wait_timeout_immediate
      @limits.command_wait_timeout_seconds = 0

      assert(! @timer.command_wait_timeout?)
      assert(! @timer.command_wait)
      assert(@timer.command_wait_timeout?)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
