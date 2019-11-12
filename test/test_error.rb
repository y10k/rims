# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class TestError < Test::Unit::TestCase
    def test_optional_data
      error = RIMS::Error.new('test', foo: 1, bar: '2')
      assert_equal('test', error.message)
      assert_equal({ foo: 1, bar: '2' }, error.optional_data)
    end

    def test_no_optional_data
      error = RIMS::Error.new('test')
      assert_equal('test', error.message)
      assert_predicate(error.optional_data, :empty?)
    end

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

    def test_optional_data_block
      count = 0
      error = RIMS::Error.new('test', foo: 1, bar: '2')
      RIMS::Error.optional_data(error) do |e, data|
        count += 1
        assert_equal(error, e)
        assert_equal({ foo: 1, bar: '2' }, data)
      end
      assert_equal(1, count)
    end

    data('not a RIMS::Error' => StandardError.new('test'),
         'no optional data'  => RIMS::Error.new('test'))
    def test_no_optional_data_block(data)
      error = data
      RIMS::Error.optional_data(error) do |e, data|
        flunk
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
