# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class TestError < Test::Unit::TestCase
    def test_trace_error_chain
      exception = assert_raise(RuntimeError) {
        begin
          begin
            begin
              raise 'error level 0'
            ensure
              raise 'error level 1'
            end
          ensure
            raise 'error level 2'
          end
        ensure
          raise 'error level 3'
        end
      }
      assert_equal('error level 3', exception.message)

      errors = RIMS::Error.trace_error_chain(exception).to_a
      assert_equal(4, errors.length)
      assert_equal([ RuntimeError ] * 4, errors.map(&:class))
      assert_equal([ 'error level 3',
                     'error level 2',
                     'error level 1',
                     'error level 0'
                   ], errors.map(&:message))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
