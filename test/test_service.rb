# -*- coding: utf-8 -*-

require 'pathname'
require 'rims'
require 'test/unit'

module RIMS::Test
  class ServiceConfigurationClassMethodTest < Test::Unit::TestCase
    data('symbol'     => [ 'foo',                  :foo              ],
         'array'      => [ %w[ foo ],              [ :foo ]          ],
         'hash'       => [ { 'foo' => 'bar' },     { foo: :bar }     ],
         'hash_array' => [ { 'foo' => %w[ bar ] }, { foo: [ :bar ] } ],
         'array_hash' => [ [ { 'foo' => 'bar' } ], [ { foo: :bar } ] ])
    def test_stringify_symbol(data)
      expected, conversion_target = data
      conversion_target_copy = Marshal.restore(Marshal.dump(conversion_target))
      assert_equal(expected, RIMS::Service::Configuration.stringify_symbol(conversion_target))
      assert_equal(conversion_target_copy, conversion_target)
    end

    data('string'     => 'foo',
         'integer'    => 1,
         'array'      => [ 'foo', 1 ],
         'hash'       => { 'foo' => 'bar' },
         'hash_array' => { 'foo' => [ 'bar', 1 ] },
         'array_hash' => [ { 'foo' => 'bar' }, 1 ])
    def test_stringify_symbol_not_converted(data)
      data_copy = Marshal.restore(Marshal.dump(data))
      assert_equal(data_copy, RIMS::Service::Configuration.stringify_symbol(data))
    end

    data('value'              => [ 'bar',                          'foo',                  'bar'                 ],
         'array'              => [ [ 1, 2, 3 ],                    [ 1 ],                  [ 2, 3 ]              ],
         'array_replace'      => [ 'foo',                          %w[ foo ],              'foo'                 ],
         'hash_merge'         => [ { 'foo' => 'a', 'bar' => 'b' }, { 'foo' => 'a' },       { 'bar' => 'b' }      ],
         'hash_replace'       => [ { 'foo' => 'b' },               { 'foo' => 'a' },       { 'foo' => 'b' }      ],
         'hash_array'         => [ { 'foo' => [ 1, 2, 3 ] },       { 'foo' => [ 1 ] },     { 'foo' => [ 2, 3 ] } ],
         'hash_array_replace' => [ { 'foo' => 'bar' },             { 'foo' => %w[ bar ] }, { 'foo' => 'bar' }    ])
    def test_update(data)
      expected, dest, other = data
      assert_equal(expected, RIMS::Service::Configuration.update(dest, other))
    end

    data('array'              => [ [ 1, 2, 3 ],                    [ 1 ],                  [ 2, 3 ]              ],
         'hash_merge'         => [ { 'foo' => 'a', 'bar' => 'b' }, { 'foo' => 'a' },       { 'bar' => 'b' }      ],
         'hash_replace'       => [ { 'foo' => 'b' },               { 'foo' => 'a' },       { 'foo' => 'b' }      ],
         'hash_array'         => [ { 'foo' => [ 1, 2, 3 ] },       { 'foo' => [ 1 ] },     { 'foo' => [ 2, 3 ] } ],
         'hash_array_replace' => [ { 'foo' => 'bar' },             { 'foo' => %w[ bar ] }, { 'foo' => 'bar' }    ])
    def test_update_destructive(data)
      expected, dest, other = data
      RIMS::Service::Configuration.update(dest, other)
      assert_equal(expected, dest)
    end

    def test_update_not_hash_error
      error = assert_raise(ArgumentError) { RIMS::Service::Configuration.update({}, 'foo') }
      assert_equal('hash can only be updated with hash.', error.message)
    end
  end

  class ServiceConfigurationTest < Test::Unit::TestCase
    def setup
      @c = RIMS::Service::Configuration.new
    end

    data('relpath' => 'foo/bar',
         'abspath' => '/foo/bar')
    def test_base_dir(path)
      @c.load(base_dir: path)
      assert_equal(Pathname(path), @c.base_dir)
    end

    data('relpath' => 'foo/bar',
         'abspath' => '/foo/bar')
    def test_load_path(path)
      @c.load({}, path)
      assert_equal(Pathname(path), @c.base_dir)
    end

    data('relpath' => [ '/path/foo/bar', 'foo/bar',  '/path' ],
         'abspath' => [ '/foo/bar',      '/foo/bar', '/path' ])
    def test_base_dir_with_load_path(data)
      expected_path, base_dir, load_path = data
      @c.load({ base_dir: base_dir }, load_path)
      assert_equal(Pathname(expected_path), @c.base_dir)
    end

    def test_base_dir_not_defined_error
      error = assert_raise(KeyError) { @c.base_dir }
      assert_equal('not defined base_dir.', error.message)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
