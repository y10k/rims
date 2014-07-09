# -*- coding: utf-8 -*-

require 'logger'
require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class TestError < Test::Unit::TestCase
    class FooError < StandardError
    end

    class BarError < StandardError
    end

    def setup
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL
      @flow_list = []
    end

    def teardown
      pp @flow_list if $DEBUG
    end

    def test_suppress_2nd_error_at_resource_closing_no_error
      begin
        @flow_list << :main
      ensure
        RIMS::Error.suppress_2nd_error_at_resource_closing{ @flow_list << :close }
      end
      assert_equal([ :main, :close ], @flow_list)

      begin
        @flow_list << :main
      ensure
        RIMS::Error.suppress_2nd_error_at_resource_closing(logger: @logger) { @flow_list << :close }
      end
      assert_equal([ :main, :close, :main, :close ], @flow_list)
    end

    def test_suppress_2nd_error_at_resource_closing_raise_1st_error
      assert_raise(FooError) {
        begin
          raise FooError
          @flow_list << :main
        ensure
          RIMS::Error.suppress_2nd_error_at_resource_closing{ @flow_list << :close }
        end
      }
      assert_equal([ :close ], @flow_list)

      assert_raise(FooError) {
        begin
          raise FooError
          @flow_list << :main
        ensure
          RIMS::Error.suppress_2nd_error_at_resource_closing(logger: @logger) { @flow_list << :close }
        end
      }
      assert_equal([ :close, :close ], @flow_list)
    end

    def test_suppress_2nd_error_at_resource_closing_suppress_2nd_error
      assert_raise(FooError) {
        begin
          raise FooError
          @flow_list << :main
        ensure
          RIMS::Error.suppress_2nd_error_at_resource_closing{
            raise BarError
            @flow_list << :close
          }
        end
      }
      assert_equal([], @flow_list)

      assert_raise(FooError) {
        begin
          raise FooError
          @flow_list << :main
        ensure
          RIMS::Error.suppress_2nd_error_at_resource_closing(logger: @logger) {
            raise BarError
            @flow_list << :close
          }
        end
      }
      assert_equal([], @flow_list)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
