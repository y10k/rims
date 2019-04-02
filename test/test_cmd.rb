# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class CmdTest < Test::Unit::TestCase
    data('string'     => [ :foo,                    'foo'                            ],
         'hash'       => [ { foo: 'bar' },          { 'foo' => 'bar' }               ],
         'hash_hash'  => [ { foo: { bar: 'baz' } }, { 'foo' => { 'bar' => 'baz' } }, ],
         'array_hash' => [ [ { foo: 'bar' } ],      [ { 'foo' => 'bar' } ]           ])
    def test_symbolize_string_key(data)
      expected, conversion_target = data
      saved_conversion_target = Marshal.restore(Marshal.dump(conversion_target))
      assert_equal(expected, RIMS::Cmd::Config.symbolize_string_key(conversion_target))
      assert_equal(saved_conversion_target, conversion_target)
    end

    data('symbol'     => :foo,
         'integer'    => 1,
         'array'      => [ :foo, 1 ],
         'hash'       => { foo: 'bar' },
         'hash_hash'  => { foo: { bar: 'baz' } },
         'array_hash' => [ { foo: 'bar' } ])
    def test_symbolize_string_key_not_converted(data)
      saved_data = Marshal.restore(Marshal.dump(data))
      assert_equal(saved_data, RIMS::Cmd::Config.symbolize_string_key(data))
      assert_equal(saved_data, data)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
