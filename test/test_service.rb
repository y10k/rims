# -*- coding: utf-8 -*-

require 'fileutils'
require 'logger'
require 'pathname'
require 'rims'
require 'socket'
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

    def test_get_configuration_hash
      assert_equal({ 'foo' => 'bar' },
                   RIMS::Service::Configuration.get_configuration({ 'configuration' => { 'foo' => 'bar' } },
                                                                  Pathname('/path/to/nothing')))
    end

    def test_get_configuration_file_relpath
      config_dir = 'config_dir'
      config_file = 'config.yml'
      FileUtils.mkdir_p(config_dir)
      begin
        IO.write(File.join(config_dir, config_file), { 'foo' => 'bar' }.to_yaml)
        assert_equal({ 'foo' => 'bar' },
                     RIMS::Service::Configuration.get_configuration({ 'configuration_file' => config_file },
                                                                    Pathname(config_dir)))
      ensure
        FileUtils.rm_rf(config_dir)
      end
    end

    def test_get_configuration_file_abspath
      config_file = 'config.yml'
      begin
        IO.write(config_file, { 'foo' => 'bar' }.to_yaml)
        assert_equal({ 'foo' => 'bar' },
                     RIMS::Service::Configuration.get_configuration({ 'configuration_file' => File.expand_path(config_file) },
                                                                    Pathname('/path/to/nothing')))
      ensure
        FileUtils.rm_f(config_file)
      end
    end

    def test_get_configuration_file_no_config
      assert_equal({}, RIMS::Service::Configuration.get_configuration({}, Pathname('/path/to/nothing')))
    end

    def test_get_configuration_file_conflict_error
      error = assert_raise(KeyError) {
        RIMS::Service::Configuration.get_configuration({ 'configuration' => { 'foo' => 'bar' },
                                                         'configuration_file' => 'config.yml' },
                                                       Pathname('/path/to/nothing'))
      }
      assert_equal('configuration conflict: configuration, configuraion_file', error.message)
    end
  end

  class ServiceConfigurationLoadTest < Test::Unit::TestCase
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
  end

  class ServiceConfigurationTest < Test::Unit::TestCase
    def setup
      @c = RIMS::Service::Configuration.new
      @base_dir = 'config_dir'
      @c.load(base_dir: @base_dir)
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::UNKNOWN
    end

    def teardown
      FileUtils.rm_rf(@base_dir)
    end

    def test_require_features
      assert(! defined? Prime)
      assert(! ($LOADED_FEATURES.any? %r"prime"))

      fork{
        @c.load(required_features: %w[ prime ])
        assert_equal(%w[ prime ], @c.get_required_features)
        @c.require_features
        assert(defined? Prime)
        assert($LOADED_FEATURES.any? %r"prime")
      }

      Process.wait
      assert_equal(0, $?.exitstatus)
    end

    def test_require_features_no_features
      assert_equal([], @c.get_required_features)
      saved_loaded_features = $LOADED_FEATURES.dup
      @c.require_features
      assert_equal(saved_loaded_features, $LOADED_FEATURES)
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

    def test_thread_queue_polling_timeout_seconds
      @c.load(server: { thread_queue_polling_timeout_seconds: 1 })
      assert_equal(1, @c.thread_queue_polling_timeout_seconds)
    end

    def test_thread_queue_polling_timeout_seconds_default
      assert_equal(0.1, @c.thread_queue_polling_timeout_seconds)
    end

    def test_read_lock_timeout_seconds
      @c.load(lock: { read_lock_timeout_seconds: 15 })
      assert_equal(15, @c.read_lock_timeout_seconds)
    end

    def test_read_lock_timeout_seconds_default
      assert_equal(30, @c.read_lock_timeout_seconds)
    end

    def test_write_lock_timeout_seconds
      @c.load(lock: { write_lock_timeout_seconds: 15 })
      assert_equal(15, @c.write_lock_timeout_seconds)
    end

    def test_write_lock_timeout_seconds_default
      assert_equal(30, @c.write_lock_timeout_seconds)
    end

    def test_make_meta_key_value_store_params
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [ RIMS::Checksum_KeyValueStore ] },
                   @c.make_meta_key_value_store_params.to_h)
    end

    def test_make_meta_key_value_store_params_origin_type
      @c.load(storage: {
                meta_key_value_store: {
                  type: 'gdbm'
                }
              })
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [ RIMS::Checksum_KeyValueStore ] },
                   @c.make_meta_key_value_store_params.to_h)
    end

    def test_make_meta_key_value_store_params_origin_config
      @c.load(storage: {
                meta_key_value_store: {
                  configuration: {
                    'foo' => 'bar'
                  }
                }
              })
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: { 'foo' => 'bar' },
                     middleware_list: [ RIMS::Checksum_KeyValueStore ] },
                   @c.make_meta_key_value_store_params.to_h)
    end

    def test_make_meta_key_value_store_params_use_checksum
      @c.load(storage: {
                meta_key_value_store: {
                  use_checksum: true
                }
              })
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [ RIMS::Checksum_KeyValueStore ] },
                   @c.make_meta_key_value_store_params.to_h)
    end

    def test_make_meta_key_value_store_params_use_checksum_no
      @c.load(storage: {
                meta_key_value_store: {
                  use_checksum: false
                }
              })
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [] },
                   @c.make_meta_key_value_store_params.to_h)
    end

    def test_make_text_key_value_store_params
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [ RIMS::Checksum_KeyValueStore ] },
                   @c.make_text_key_value_store_params.to_h)
    end

    def test_make_text_key_value_store_params_origin_type
      @c.load(storage: {
                text_key_value_store: {
                  type: 'gdbm'
                }
              })
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [ RIMS::Checksum_KeyValueStore ] },
                   @c.make_text_key_value_store_params.to_h)
    end

    def test_make_text_key_value_store_params_origin_config
      @c.load(storage: {
                text_key_value_store: {
                  configuration: {
                    'foo' => 'bar'
                  }
                }
              })
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: { 'foo' => 'bar' },
                     middleware_list: [ RIMS::Checksum_KeyValueStore ] },
                   @c.make_text_key_value_store_params.to_h)
    end

    def test_make_text_key_value_store_params_use_checksum
      @c.load(storage: {
                text_key_value_store: {
                  use_checksum: true
                }
              })
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [ RIMS::Checksum_KeyValueStore ] },
                   @c.make_text_key_value_store_params.to_h)
    end

    def test_make_text_key_value_store_params_use_checksum_no
      @c.load(storage: {
                text_key_value_store: {
                  use_checksum: false
                }
              })
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [] },
                   @c.make_text_key_value_store_params.to_h)
    end

    def test_make_key_value_store_path
      assert_equal(Pathname(File.join(@base_dir, 'mailbox', '11', '22222222')),
                   @c.make_key_value_store_path('mailbox', '1122222222'))
    end

    def test_make_key_value_store_path_short_mailbox_data_structure_version_error
      error = assert_raise(ArgumentError) { @c.make_key_value_store_path('', '1122222222') }
      assert_equal('too short mailbox data structure version.', error.message)
    end

    data('too_short' => '1',
         'boundary'  => '12')
    def test_make_key_value_store_path_short_unique_user_id_error(data)
      unique_user_id = data
      error = assert_raise(ArgumentError) { @c.make_key_value_store_path('mailbox', unique_user_id) }
      assert_equal('too short unique user ID.', error.message)
    end

    authentication_users = {
      presence: [
        { 'user' => 'alice', 'pass' => 'open sesame' },
        { 'user' => 'bob',   'pass' => 'Z1ON0101'    }
      ],
      absence: [
        { 'user' => 'no_user', 'pass' => 'nothing' }
      ]
    }

    data('users', authentication_users)
    def test_make_authentication(data)
      auth = @c.make_authentication
      assert_equal(Socket.gethostname, auth.hostname)

      auth.start_plug_in(@logger)
      for pw in data[:presence]
        assert_equal(false, (auth.user? pw['user']))
        assert(! auth.authenticate_login(pw['user'], pw['pass']))
      end
      for pw in data[:absence]
        assert_equal(false, (auth.user? pw['user']))
        assert(! auth.authenticate_login(pw['user'], pw['pass']))
      end
      auth.stop_plug_in(@logger)
    end

    data('users', authentication_users)
    def test_make_authentication_hostname(data)
      @c.load(authentication: {
                hostname: 'imap.example.com'
              })
      auth = @c.make_authentication
      assert_equal('imap.example.com', auth.hostname)
    end

    data('users', authentication_users)
    def test_make_authentication_password_source_single(data)
      @c.load(authentication: {
                password_sources: [
                  { type: 'plain',
                    configuration: data[:presence]
                  }
                ]
              })
      auth = @c.make_authentication

      auth.start_plug_in(@logger)
      for pw in data[:presence]
        assert_equal(true, (auth.user? pw['user']))
        assert(auth.authenticate_login(pw['user'], pw['pass']))
        assert(! auth.authenticate_login(pw['user'], pw['pass'].succ))
      end
      for pw in data[:absence]
        assert_equal(false, (auth.user? pw['user']))
        assert(! auth.authenticate_login(pw['user'], pw['pass']))
      end
      auth.stop_plug_in(@logger)
    end

    data('users', authentication_users)
    def test_make_authentication_password_source_multiple(data)
      @c.load(authentication: {
                password_sources: data[:presence].map{|pw|
                  { type: 'plain',
                    configuration: [ pw ]
                  }
                }
              })
      auth = @c.make_authentication

      auth.start_plug_in(@logger)
      for pw in data[:presence]
        assert_equal(true, (auth.user? pw['user']))
        assert(auth.authenticate_login(pw['user'], pw['pass']))
        assert(! auth.authenticate_login(pw['user'], pw['pass'].succ))
      end
      for pw in data[:absence]
        assert_equal(false, (auth.user? pw['user']))
        assert(! auth.authenticate_login(pw['user'], pw['pass']))
      end
      auth.stop_plug_in(@logger)
    end

    data('users', authentication_users)
    def test_make_authentication_no_type_error(data)
      @c.load(authentication: {
                password_sources: [
                  { configuration: data[:presence] }
                ]
              })
      error = assert_raise(KeyError) { @c.make_authentication }
      assert_equal('not found a password source type.', error.message)
    end

    def test_mail_delivery_user
      @c.load(authorization: {
                mail_delivery_user: 'alice'
              })
      assert_equal('alice', @c.mail_delivery_user)
    end

    def test_mail_delivery_user_default
      assert_equal('#postman', @c.mail_delivery_user)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
