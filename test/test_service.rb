# -*- coding: utf-8 -*-

require 'fileutils'
require 'pathname'
require 'rims'
require 'test/unit'
require 'yaml'

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
      @config_dir = 'config_dir'
    end

    def teardown
      FileUtils.rm_rf(@config_dir)
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

    def test_load_yaml_load_path
      FileUtils.mkdir_p(@config_dir)
      config_path = File.join(@config_dir, 'config.yml')
      IO.write(config_path, {}.to_yaml)

      @c.load_yaml(config_path)
      assert_equal(Pathname(@config_dir), @c.base_dir)
    end

    data('relpath' => [ %q{"#{@config_dir}/foo/bar"}, 'foo/bar'  ],
         'abspath' => [ %q{'/foo/bar'},                '/foo/bar' ])
    def test_load_yaml_base_dir(data)
      expected_path, base_dir = data

      FileUtils.mkdir_p(@config_dir)
      config_path = File.join(@config_dir, 'config.yml')
      IO.write(config_path, { 'base_dir' => base_dir }.to_yaml)

      @c.load_yaml(config_path)
      assert_equal(Pathname(eval(expected_path)), @c.base_dir)
    end

    def test_accept_polling_timeout_seconds
      @c.load(server: { accept_polling_timeout_seconds: 1 })
      assert_equal(1, @c.accept_polling_timeout_seconds)
    end

    def test_accept_polling_timeout_seconds_default
      assert_equal(0.1, @c.accept_polling_timeout_seconds)
    end

    def test_thread_num
      @c.load(server: { thread_num: 30 })
      assert_equal(30, @c.thread_num)
    end

    def test_thread_num_default
      assert_equal(20, @c.thread_num)
    end

    def test_thread_queue_size
      @c.load(server: { thread_queue_size: 30 })
      assert_equal(30, @c.thread_queue_size)
    end

    def test_thread_queue_size_default
      assert_equal(20, @c.thread_queue_size)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
