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
      saved_conversion_target = Marshal.restore(Marshal.dump(conversion_target))
      assert_equal(expected, RIMS::Service::Configuration.stringify_symbol(conversion_target))
      assert_equal(saved_conversion_target, conversion_target)
    end

    data('string'     => 'foo',
         'integer'    => 1,
         'array'      => [ 'foo', 1 ],
         'hash'       => { 'foo' => 'bar' },
         'hash_array' => { 'foo' => [ 'bar', 1 ] },
         'array_hash' => [ { 'foo' => 'bar' }, 1 ])
    def test_stringify_symbol_not_converted(data)
      saved_data = Marshal.restore(Marshal.dump(data))
      assert_equal(saved_data, RIMS::Service::Configuration.stringify_symbol(data))
      assert_equal(saved_data, data)
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

    def test_get_configuration_file_no_base_dir_error
      error = assert_raise(ArgumentError) {
        RIMS::Service::Configuration.get_configuration({ 'configuration_file' => 'config.yml' })
      }
      assert_equal('need for base_dir.', error.message)
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

    data('rel_path' => 'foo/bar',
         'abs_path' => '/foo/bar')
    def test_base_dir(path)
      @c.load(base_dir: path)
      assert_equal(Pathname(path), @c.base_dir)
    end

    data('rel_path' => 'foo/bar',
         'abs_path' => '/foo/bar')
    def test_load_path(path)
      @c.load({}, path)
      assert_equal(Pathname(path), @c.base_dir)
    end

    data('rel_path' => [ '/path/foo/bar', 'foo/bar',  '/path' ],
         'abs_path' => [ '/foo/bar',      '/foo/bar', '/path' ])
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

    data('rel_path' => [ %q{"#{@config_dir}/foo/bar"}, 'foo/bar'  ],
         'abs_path' => [ %q{'/foo/bar'},                '/foo/bar' ])
    def test_load_yaml_base_dir(data)
      expected_path, base_dir = data

      FileUtils.mkdir_p(@config_dir)
      config_path = File.join(@config_dir, 'config.yml')
      IO.write(config_path, { 'base_dir' => base_dir }.to_yaml)

      @c.load_yaml(config_path)
      assert_equal(Pathname(eval(expected_path)), @c.base_dir)
    end

    def test_default_config
      assert_raise(NoMethodError) { RIMS::Service::DEFAULT_CONFIG.load({}) }
      assert_raise(NoMethodError) { RIMS::Service::DEFAULT_CONFIG.load_yaml('config.yml') }
      assert_equal([], RIMS::Service::DEFAULT_CONFIG.get_required_features)
      assert_raise(KeyError) { RIMS::Service::DEFAULT_CONFIG.base_dir }
      assert_equal([ 'rims.log', { level: 'info', progname: 'rims'} ], RIMS::Service::DEFAULT_CONFIG.make_file_logger_params)
      assert_equal([ STDOUT, { level: 'info', progname: 'rims' } ], RIMS::Service::DEFAULT_CONFIG.make_stdout_logger_params)
      assert_equal([ 'protocol.log', { level: 'unknown', progname: 'rims' } ], RIMS::Service::DEFAULT_CONFIG.make_protocol_logger_params)
      assert_equal(true, RIMS::Service::DEFAULT_CONFIG.daemonize?)
      assert_equal('rims', RIMS::Service::DEFAULT_CONFIG.daemon_name)
      assert_equal(false, RIMS::Service::DEFAULT_CONFIG.daemon_debug?)
      assert_equal('rims.pid', RIMS::Service::DEFAULT_CONFIG.status_file)
      assert_equal(3, RIMS::Service::DEFAULT_CONFIG.server_polling_interval_seconds)
      assert_equal(0, RIMS::Service::DEFAULT_CONFIG.server_restart_overlap_seconds)
      assert_nil(RIMS::Service::DEFAULT_CONFIG.server_privileged_user)
      assert_nil(RIMS::Service::DEFAULT_CONFIG.server_privileged_group)
      assert_equal('0.0.0.0:1430', RIMS::Service::DEFAULT_CONFIG.listen_address)
      assert_equal(0.1, RIMS::Service::DEFAULT_CONFIG.accept_polling_timeout_seconds)
      assert_equal(0, RIMS::Service::DEFAULT_CONFIG.process_num)
      assert_equal(20, RIMS::Service::DEFAULT_CONFIG.process_queue_size)
      assert_equal(0.1, RIMS::Service::DEFAULT_CONFIG.process_queue_polling_timeout_seconds)
      assert_equal(0.1, RIMS::Service::DEFAULT_CONFIG.process_send_io_polling_timeout_seconds)
      assert_equal(20, RIMS::Service::DEFAULT_CONFIG.thread_num)
      assert_equal(20, RIMS::Service::DEFAULT_CONFIG.thread_queue_size)
      assert_equal(0.1, RIMS::Service::DEFAULT_CONFIG.thread_queue_polling_timeout_seconds)
      assert_equal(1024 * 16, RIMS::Service::DEFAULT_CONFIG.send_buffer_limit_size)
      assert_nil(RIMS::Service::DEFAULT_CONFIG.ssl_context)
      assert_equal(30, RIMS::Service::DEFAULT_CONFIG.read_lock_timeout_seconds)
      assert_equal(30, RIMS::Service::DEFAULT_CONFIG.write_lock_timeout_seconds)
      assert_equal(1, RIMS::Service::DEFAULT_CONFIG.cleanup_write_lock_timeout_seconds)
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [ RIMS::Checksum_KeyValueStore ]
                   },
                   RIMS::Service::DEFAULT_CONFIG.make_meta_key_value_store_params.to_h)
      assert_equal({ origin_type: RIMS::GDBM_KeyValueStore,
                     origin_config: {},
                     middleware_list: [ RIMS::Checksum_KeyValueStore ]
                   },
                   RIMS::Service::DEFAULT_CONFIG.make_text_key_value_store_params.to_h)
      assert_raise(KeyError) { RIMS::Service::DEFAULT_CONFIG.make_key_value_store_path('path', 'abcd') }
      assert_equal(Socket.gethostname, RIMS::Service::DEFAULT_CONFIG.make_authentication.hostname)
      assert_equal('#postman', RIMS::Service::DEFAULT_CONFIG.mail_delivery_user)
    end
  end

  class ServiceConfigurationTest < Test::Unit::TestCase
    BASE_DIR = 'config_dir'

    def setup
      @c = RIMS::Service::Configuration.new
      @base_dir = BASE_DIR
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

    data('default'  => [ [], {} ],
         'config'   => [ %w[ rims/qdbm rims/passwd/ldap ],
                         { required_features: %w[ rims/qdbm rims/passwd/ldap ] } ],
         'compat'   => [ %w[ rims/qdbm rims/passwd/ldap ],
                         { load_libraries: %w[ rims/qdbm rims/passwd/ldap ] } ],
         'priority' => [ %w[ rims/qdbm ],
                         { required_features: %w[ rims/qdbm ],
                           load_libraries: %w[ rims/passwd/ldap ]
                         }
                       ])
    def test_get_required_features(data)
      expected_features, config = data
      @c.load(config)
      assert_equal(expected_features, @c.get_required_features)
    end

    default_rims_log = File.join(BASE_DIR, 'rims.log')
    data('default'             => [ [ default_rims_log,{ level: 'info', progname: 'rims' } ], {} ],
         'rel_path'            => [ [ File.join(BASE_DIR, 'server.log'), { level: 'info', progname: 'rims' } ],
                                    { logging: { file: { path: 'server.log' } } } ],
         'abs_path'            => [ [ '/var/log/rims.log', { level: 'info', progname: 'rims' } ],
                                    { logging: { file: { path: '/var/log/rims.log' } } } ],
         'compat_path'         => [ [ File.join(BASE_DIR, 'server.log'), { level: 'info', progname: 'rims' } ],
                                    { log_file: 'server.log' } ],
         'shift_age'           => [ [ default_rims_log, 10, { level: 'info', progname: 'rims' } ],
                                    { logging: { file: { shift_age: 10 } } } ],
         'compat_shift_age'    => [ [ default_rims_log, 10, { level: 'info', progname: 'rims' } ],
                                    { log_shift_age: 10 } ],
         'shift_daily'         => [ [ default_rims_log, 'daily', { level: 'info', progname: 'rims' } ],
                                    { logging: { file: { shift_age: 'daily' } } } ],
         'shift_weekly'        => [ [ default_rims_log, 'weekly', { level: 'info', progname: 'rims' } ],
                                    { logging: { file: { shift_age: 'weekly' } } } ],
         'shift_monthly'       => [ [ default_rims_log, 'monthly', { level: 'info', progname: 'rims' } ],
                                    { logging: { file: { shift_age: 'monthly' } } } ],
         'shift_size'          => [ [ default_rims_log, 0, 16777216, { level: 'info', progname: 'rims' } ],
                                    { logging: { file: { shift_size: 16777216 } } } ],
         'compat_shift_size'   => [ [ default_rims_log, 0, 16777216, { level: 'info', progname: 'rims' } ],
                                    { log_shift_size: 16777216 } ],
         'level'               => [ [ default_rims_log, { level: 'debug', progname: 'rims' } ],
                                    { logging: { file: { level: 'debug' } } } ],
         'compat_level'        => [ [ default_rims_log, { level: 'debug', progname: 'rims' } ],
                                    { log_level: 'debug' } ],
         'datetime_format'     => [ [ default_rims_log, { level: 'info', progname: 'rims', datetime_format: '%Y%m%d%H%M%S' } ],
                                    { logging: { file: { datetime_format: '%Y%m%d%H%M%S' } } } ],
         'shift_period_suffix' => [ [ default_rims_log, { level: 'info', progname: 'rims', shift_period_suffix: '%Y-%m-%d' } ],
                                    { logging: { file: { shift_period_suffix: '%Y-%m-%d' } } } ],
         'all'                 => [ [ '/var/log/rims.log',
                                      10,
                                      16777216,
                                      { level: 'debug',
                                        progname: 'rims',
                                        datetime_format: '%Y%m%d%H%M%S',
                                        shift_period_suffix: '%Y-%m-%d'
                                      }
                                    ],
                                    { logging: {
                                        file: {
                                          path: '/var/log/rims.log',
                                          shift_age: 10,
                                          shift_size: 16777216,
                                          level: 'debug',
                                          datetime_format: '%Y%m%d%H%M%S',
                                          shift_period_suffix: '%Y-%m-%d'
                                        }
                                      }
                                    }
                                  ],
         'priority'            => [ [ '/var/log/rims.log',
                                      10,
                                      16777216,
                                      { level: 'debug',
                                        progname: 'rims',
                                      }
                                    ],
                                    { logging: {
                                        file: {
                                          path: '/var/log/rims.log',
                                          shift_age: 10,
                                          shift_size: 16777216,
                                          level: 'debug'
                                        }
                                      },
                                      log_file: '/var/log/server.log',
                                      log_shift_age: 7,
                                      log_shift_size: 1048576,
                                      log_level: 'info'
                                    }
                                  ])
    def test_make_file_logger_params(data)
      expected_logger_params, config = data
      @c.load(config)
      assert_equal(expected_logger_params, @c.make_file_logger_params)
    end

    data('default'         => [ [ STDOUT, { level: 'info', progname: 'rims' } ], {} ],
         'level'           => [ [ STDOUT, { level: 'debug', progname: 'rims' } ],
                                { logging: { stdout: { level: 'debug' } } } ],
         'compat_level'    => [ [ STDOUT, { level: 'debug', progname: 'rims' } ],
                                { log_stdout: 'debug' } ],
         'datetime_format' => [ [ STDOUT, { level: 'info', progname: 'rims', datetime_format: '%Y%m%d%H%M%S' } ],
                                { logging: { stdout: { datetime_format: '%Y%m%d%H%M%S' } } } ],
         'all'             => [ [ STDOUT, { level: 'debug', progname: 'rims', datetime_format: '%Y%m%d%H%M%S' } ],
                                { logging: {
                                    stdout: {
                                      level: 'debug',
                                      datetime_format: '%Y%m%d%H%M%S'
                                    }
                                  }
                                }
                              ],
         'priority'        => [ [ STDOUT, { level: 'debug', progname: 'rims' } ],
                                { logging: { stdout: { level: 'debug' } },
                                  log_stdout: 'info'
                                }
                              ])
    def test_make_stdout_logger_params(data)
      expected_logger_params, config = data
      @c.load(config)
      assert_equal(expected_logger_params, @c.make_stdout_logger_params)
    end

    default_protocol_log = File.join(BASE_DIR, 'protocol.log')
    data('default'             => [ [ default_protocol_log, { level: 'unknown', progname: 'rims' } ], {} ],
         'rel_path'            => [ [ File.join(BASE_DIR, 'imap.log'), { level: 'unknown', progname: 'rims' } ],
                                    { logging: { protocol: { path: 'imap.log' } } } ],
         'abs_path'            => [ [ '/var/log/imap.log', { level: 'unknown', progname: 'rims' } ],
                                    { logging: { protocol: { path: '/var/log/imap.log' } } } ],
         'shift_age'           => [ [ default_protocol_log, 10, { level: 'unknown', progname: 'rims' } ],
                                    { logging: { protocol: { shift_age: 10 } } } ],
         'shift_daily'         => [ [ default_protocol_log, 'daily', { level: 'unknown', progname: 'rims' } ],
                                    { logging: { protocol: { shift_age: 'daily' } } } ],
         'shift_weekly'        => [ [ default_protocol_log, 'weekly', { level: 'unknown', progname: 'rims' } ],
                                    { logging: { protocol: { shift_age: 'weekly' } } } ],
         'shift_monthly'       => [ [ default_protocol_log, 'monthly', { level: 'unknown', progname: 'rims' } ],
                                    { logging: { protocol: { shift_age: 'monthly' } } } ],
         'shift_size'          => [ [ default_protocol_log, 0, 16777216, { level: 'unknown', progname: 'rims' } ],
                                    { logging: { protocol: { shift_size: 16777216 } } } ],
         'level'               => [ [ default_protocol_log, { level: 'info', progname: 'rims' } ],
                                    { logging: { protocol: { level: 'info' } } } ],
         'datetime_format'     => [ [ default_protocol_log, { level: 'unknown', progname: 'rims', datetime_format: '%Y%m%d%H%M%S' } ],
                                    { logging: { protocol: { datetime_format: '%Y%m%d%H%M%S' } } } ],
         'shift_period_suffix' => [ [ default_protocol_log, { level: 'unknown', progname: 'rims', shift_period_suffix: '%Y-%m-%d' } ],
                                    { logging: { protocol: { shift_period_suffix: '%Y-%m-%d' } } } ],
         'all'                 => [ [ '/var/log/imap.log',
                                      10,
                                      16777216,
                                      { level: 'info',
                                        progname: 'rims',
                                        datetime_format: '%Y%m%d%H%M%S',
                                        shift_period_suffix: '%Y-%m-%d'
                                      }
                                    ],
                                    { logging: {
                                        protocol: {
                                          path: '/var/log/imap.log',
                                          shift_age: 10,
                                          shift_size: 16777216,
                                          level: 'info',
                                          datetime_format: '%Y%m%d%H%M%S',
                                          shift_period_suffix: '%Y-%m-%d'
                                        }
                                      }
                                    }
                                  ])
    def test_make_protocol_logger_params(data)
      expected_logger_params, config = data
      @c.load(config)
      assert_equal(expected_logger_params, @c.make_protocol_logger_params)
    end

    data('default'       => [ true,  {} ],
         'daemonize'     => [ true,  { daemon: { daemonize: true } } ],
         'not_daemonize' => [ false, { daemon: { daemonize: false } } ])
    def test_daemonize?(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.daemonize?)
    end

    data('default'   => [ false, {} ],
         'debug'     => [ true,  { daemon: { debug: true } } ],
         'not_debug' => [ false, { daemon: { debug: false } } ])
    def test_daemon_debug?(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.daemon_debug?)
    end

    data('default'  => [ File.join(BASE_DIR, 'rims.pid'), {} ],
         'rel_path' => [ File.join(BASE_DIR, 'status'),   { daemon: { status_file: 'status' } } ],
         'abs_path' => [ '/var/run/rims.pid',             { daemon: { status_file: '/var/run/rims.pid' } } ])
    def test_status_file(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.status_file)
    end

    data('default' => [ 3, {} ],
         'config'  => [ 1, { daemon: { server_polling_interval_seconds: 1 } } ])
    def test_server_polling_interval_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.server_polling_interval_seconds)
    end

    data('default'  => [ nil, {} ],
         'name'     => [ 'imap', { daemon: { server_privileged_user: 'imap' } } ],
         'uid'      => [ 1000,   { daemon: { server_privileged_user: 1000 } } ],
         'compat'   => [ 'imap', { process_privilege_user: 'imap' } ],
         'priority' => [ 'imap',
                         { daemon: { server_privileged_user: 'imap' },
                           process_privilege_user: 'nobody'
                         }
                       ])
    def test_server_privileged_user(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.server_privileged_user)
    end

    data('default'  => [ nil, {} ],
         'name'     => [ 'imap', { daemon: { server_privileged_group: 'imap' } } ],
         'gid'      => [ 1000,   { daemon: { server_privileged_group: 1000 } } ],
         'compat'   => [ 'imap', { process_privilege_group: 'imap' } ],
         'priority' => [ 'imap',
                         { daemon: { server_privileged_group: 'imap' },
                           process_privilege_group: 'nogroup'
                         }
                       ])
    def test_server_privileged_group(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.server_privileged_group)
    end

    data('default'          => [ '0.0.0.0:1430', {} ],
         'string'           => [ 'imap.example.com:143',
                                 { server: { listen_address: 'imap.example.com:143' } } ],
         'uri'              => [ 'tcp://imap.example.com:143',
                                 { server: { listen_address: 'tcp://imap.example.com:143' } } ],
         'hash'             => [ { 'type' => 'tcp',
                                   'host'          => 'imap.example.com',
                                   'port'          => 143,
                                   'backlog'       => 64
                                 },
                                 { server: {
                                     listen_address: {
                                       'type'      => 'tcp',
                                       'host'      => 'imap.example.com',
                                       'port'      => 143,
                                       'backlog'   => 64
                                     }
                                   }
                                 }
                               ],
         'compat_imap_host' => [ { 'type' => 'tcp',
                                   'host' => 'imap.example.com',
                                   'port' => 1430
                                 },
                                 { imap_host: 'imap.example.com',
                                   ip_addr: 'imap2.example.com'
                                 }
                               ],
         'compat_ip_addr'   => [ { 'type' => 'tcp',
                                   'host'   => 'imap.example.com',
                                   'port'   => 1430
                                 },
                                 { ip_addr: 'imap.example.com' }
                               ],
         'compat_imap_port' => [ { 'type' => 'tcp',
                                   'host' => '0.0.0.0',
                                   'port' => 143
                                 },
                                 { imap_port: 143,
                                   ip_port: 5000
                                 }
                               ],
         'compat_ip_port'   =>  [ { 'type' => 'tcp',
                                    'host'  => '0.0.0.0',
                                    'port'  => 143
                                  },
                                  { ip_port: 143 }
                                ],
         'priority'         => [ 'imap.example.com:143',
                                 { server: {
                                     listen_address: 'imap.example.com:143'
                                   },
                                   imap_host: 'imap2.example.com',
                                   imap_port: 5000,
                                   ip_addr: 'imap3.example.com',
                                   ip_port: 6000
                                 }
                               ])
    def test_listen_address(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.listen_address)
    end

    data('default' => [ 0.1, {} ],
         'config'  => [ 1,   { server: { accept_polling_timeout_seconds: 1 } }])
    def test_accept_polling_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.accept_polling_timeout_seconds)
    end

    data('default' => [ 0, {} ],
         'config'  => [ 4, { server: { process_num: 4 } } ])
    def test_process_num(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.process_num)
    end

    data('default' => [ 20, {} ],
         'config'  => [ 30, { server: { process_queue_size: 30 } } ])
    def test_process_queue_size(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.process_queue_size)
    end

    data('default' => [ 0.1, {} ],
         'config'  => [ 1,   { server: { process_queue_polling_timeout_seconds: 1 } } ])
    def test_process_queue_polling_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.process_queue_polling_timeout_seconds)
    end

    data('default' => [ 0.1, {} ],
         'config'  => [ 1,   { server: { process_send_io_polling_timeout_seconds: 1 } } ])
    def test_process_send_io_polling_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.process_send_io_polling_timeout_seconds)
    end

    data('default' => [ 20, {} ],
         'config'  => [ 30, { server: { thread_num: 30 } } ])
    def test_thread_num(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.thread_num)
    end

    data('default' => [ 20, {} ],
         'config'  => [ 30, { server: { thread_queue_size: 30 } }])
    def test_thread_queue_size(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.thread_queue_size)
    end

    data('default' => [ 0.1, {} ],
         'config'  => [ 1,   { server: { thread_queue_polling_timeout_seconds: 1 } } ])
    def test_thread_queue_polling_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.thread_queue_polling_timeout_seconds)
    end

    tls_dir = Pathname(__FILE__).dirname / "tls"
    TLS_SERVER_PKEY = tls_dir / 'server.priv_key'
    TLS_SERVER_CERT = tls_dir / 'server_localhost.cert'

    unless ([ TLS_SERVER_PKEY, TLS_SERVER_CERT ].all?(&:file?)) then
      warn("warning: do `rake test_cert:make' to create TLS private key file and TLS certificate file for test.")
    end

    def test_ssl_context
      FileUtils.mkdir_p(@base_dir)
      FileUtils.cp(TLS_SERVER_PKEY.to_path, @base_dir)
      FileUtils.cp(TLS_SERVER_CERT.to_path, @base_dir)

      @c.load(openssl: {
                ssl_context: <<-EOF
                  _.key = PKey.read((base_dir / #{TLS_SERVER_PKEY.basename.to_path.dump}).read)
                  _.cert = X509::Certificate.new((base_dir / #{TLS_SERVER_CERT.basename.to_path.dump}).read)
                EOF
              })

      ssl_context = @c.ssl_context
      assert_instance_of(OpenSSL::SSL::SSLContext, ssl_context)
      assert_equal(OpenSSL::PKey::RSA.new(TLS_SERVER_PKEY.read).params, ssl_context.key.params)
      assert_equal(OpenSSL::X509::Certificate.new(TLS_SERVER_CERT.read), ssl_context.cert)
    end

    def test_ssl_context_use_ssl
      @c.load(openssl: {
                use_ssl: true
              })

      ssl_context = @c.ssl_context
      assert_instance_of(OpenSSL::SSL::SSLContext, ssl_context)
      assert_nil(ssl_context.key)
      assert_nil(ssl_context.cert)
    end

    data('default'        => {},
         'no_ssl_context' => { openssl: {} },
         'not_use_ssl'    => { openssl: {
                                 use_ssl: false,
                                 ssl_context: <<-EOF
                                   _.key = PKey.read((base_dir / #{TLS_SERVER_PKEY.basename.to_path.dump}).read)
                                   _.cert = X509::Certificate.new((base_dir / #{TLS_SERVER_CERT.basename.to_path.dump}).read)
                                 EOF
                               }
                             })
    def test_ssl_context_not_use_ssl(config)
      @c.load(config)
      assert_nil(@c.ssl_context)
    end

    data('default'  => [ 1024 * 16, {} ],
         'config'   => [ 1024 * 64, { connection: { send_buffer_limit_size: 1024 * 64 } } ],
         'compat'   => [ 1024 * 64, { send_buffer_limit: 1024 * 64 } ],
         'priority' => [ 1024 * 64,
                         { connection: { send_buffer_limit_size: 1024 * 64 },
                           send_buffer_limit: 1024 * 32
                         }
                       ])
    def test_send_buffer_limit_size(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.send_buffer_limit_size)
    end

    data('default' => [ { read_polling_interval_seconds: 1,
                          command_wait_timeout_seconds: 60 * 30
                        },
                        {}
                      ],
         'config'  => [ { read_polling_interval_seconds: 5,
                          command_wait_timeout_seconds: 60 * 60
                        },
                        { connection: {
                            read_polling_interval_seconds: 5,
                            command_wait_timeout_seconds: 60 * 60
                          }
                        }
                      ])
    def test_connection_limits(data)
      expected_values, config = data
      @c.load(config)
      limits = @c.connection_limits
      assert_instance_of(RIMS::Protocol::ConnectionLimits, limits)
      assert_equal(expected_values, limits.to_h)
    end

    data('default'                 => [ [ [ 'EUC-JP',      Encoding::EUCJP_MS ],
                                          [ 'ISO-2022-JP', Encoding::CP50221 ],
                                          [ 'SHIFT_JIS',   Encoding::WINDOWS_31J ]
                                        ],
                                        {}
                                      ],
         'use_default_aliases:yes' => [ [ [ 'EUC-JP',      Encoding::EUCJP_MS ],
                                          [ 'ISO-2022-JP', Encoding::CP50221 ],
                                          [ 'SHIFT_JIS',   Encoding::WINDOWS_31J ]
                                        ],
                                        { charset: {
                                            use_default_aliases: true
                                          }
                                        }
                                      ],
         'use_default_aliases:no'  => [ [],
                                        { charset: {
                                            use_default_aliases: false
                                          }
                                        }
                                      ],
         'aliases'                 => [ [ [ 'EUC-JP',      Encoding::EUCJP_MS ],
                                          [ 'SHIFT_JIS',   Encoding::WINDOWS_31J ]
                                        ],
                                        { charset: {
                                            use_default_aliases: false,
                                            aliases: [
                                              { name: 'euc-jp',    encoding: 'eucJP-ms' },
                                              { name: 'Shift_JIS', encoding: 'Windows-31J' }
                                            ]
                                          }
                                        }
                                      ])
    def test_charset_aliases(data)
      expected_aliases, config = data
      @c.load(config)
      assert_equal(expected_aliases, @c.charset_aliases.to_a)
    end

    data('default'                              => [ { undef: :replace }, {} ],
         'replace_invalid_byte_sequence: true'  => [ { invalid: :replace,
                                                       undef: :replace
                                                     },
                                                     { charset: {
                                                         convert_options: {
                                                           replace_invalid_byte_sequence: true
                                                         }
                                                       }
                                                     }
                                                   ],
         'replace_invalid_byte_sequence: false' => [ { undef: :replace },
                                                     { charset: {
                                                         convert_options: {
                                                           replace_invalid_byte_sequence: false
                                                         }
                                                       }
                                                     }
                                                   ],
         'replace_undefined_character: true'    => [ { undef: :replace },
                                                     { charset: {
                                                         convert_options: {
                                                           replace_undefined_character: true
                                                         }
                                                       }
                                                     }
                                                   ],
         'replace_undefined_character: false'   => [ {},
                                                     { charset: {
                                                         convert_options: {
                                                           replace_undefined_character: false
                                                         }
                                                       }
                                                     }
                                                   ],
         'replaced_mark'                        => [ { undef: :replace,
                                                       replace: "\uFFFD"
                                                     },
                                                     { charset: {
                                                         convert_options: {
                                                           replaced_mark: "\uFFFD"
                                                         }
                                                       }
                                                     }
                                                   ],
         'all'                                  => [ { invalid: :replace,
                                                       undef: :replace,
                                                       replace: "\uFFFD"
                                                     },
                                                     { charset: {
                                                         convert_options: {
                                                           replace_invalid_byte_sequence: true,
                                                           replace_undefined_character: true,
                                                           replaced_mark: "\uFFFD"
                                                         }
                                                       }
                                                     }
                                                   ])
    def test_charset_convert_options(data)
      expected_options, config = data
      @c.load(config)
      assert_equal(expected_options, @c.charset_convert_options)
    end

    data('default' => [ 0, {} ],
         'config'  => [ 4,
                        { drb_services: {
                            process_num: 4
                          }
                        }
                      ])
    def test_drb_process_num(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.drb_process_num)
    end

    data('default' => [ 100, {} ],
         'config'  => [ 1024,
                        { drb_services: {
                            engine: {
                              bulk_response_count: 1024
                            }
                          }
                        }
                      ])
    def test_bulk_response_count(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.bulk_response_count)
    end

    data('default'  => [ 30, {} ],
         'config'   => [ 15,
                         { drb_services: {
                             engine: {
                               read_lock_timeout_seconds: 15
                             }
                           }
                         }
                       ],
         'compat'   => [ 15, { read_lock_timeout_seconds: 15 } ],
         'priority' => [ 15,
                         { drb_services: {
                             engine: {
                               read_lock_timeout_seconds: 15
                             }
                           },
                           read_lock_timeout_seconds: 20
                         }
                       ])
    def test_read_lock_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.read_lock_timeout_seconds)
    end

    data('default'  => [ 30, {} ],
         'config'   => [ 15,
                         { drb_services: {
                             engine: {
                               write_lock_timeout_seconds: 15
                             }
                           }
                         }
                       ],
         'compat'   => [ 15, { write_lock_timeout_seconds: 15 } ],
         'priority' => [ 15,
                         { drb_services: {
                             engine: {
                               write_lock_timeout_seconds: 15
                             }
                           },
                           write_lock_timeout_seconds: 20,
                         }
                       ])
    def test_write_lock_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.write_lock_timeout_seconds)
    end

    data('default'  => [ 1, {} ],
         'config'   => [ 3,
                         { drb_services: {
                             engine: {
                               cleanup_write_lock_timeout_seconds: 3
                             }
                           }
                         }
                       ],
         'compat'   => [ 3, { cleanup_write_lock_timeout_seconds: 3 } ],
         'priority' => [ 3,
                         { drb_services: {
                             engine: {
                               cleanup_write_lock_timeout_seconds: 3
                             }
                           },
                           cleanup_write_lock_timeout_seconds: 5
                         }
                       ])
    def test_cleanup_write_lock_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.cleanup_write_lock_timeout_seconds)
    end

    data('default'                      => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             {}
                                           ],
         'origin_type'                  => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { storage: { meta_key_value_store: { type: 'gdbm' } } }
                                           ],
         'compat_origin_type'           => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { meta_key_value_store: { plug_in: 'gdbm' } }
                                           ],
         'compat_origin_type2'          =>  [ { origin_type: RIMS::GDBM_KeyValueStore,
                                                origin_config: {},
                                                middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                              },
                                              { key_value_store_type: 'gdbm' }
                                            ],
         'compat_origin_type_priority'  => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { meta_key_value_store: { plug_in: 'gdbm' },
                                               key_value_store_type: 'qdbm'
                                             }
                                           ],
         'origin_config'                => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: { 'foo' => 'bar' },
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { storage: { meta_key_value_store: { configuration: { 'foo' => 'bar' } } } }
                                           ],
         'compat_origin_config'         => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: { 'foo' => 'bar' },
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { meta_key_value_store: { configuration: { 'foo' => 'bar' } }  }
                                           ],
         'use_checksum'                 => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { storage: { meta_key_value_store: { use_checksum: true } } }
                                           ],
         'use_checksum_no'              => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: []
                                             },
                                             { storage: { meta_key_value_store: { use_checksum: false } } }
                                           ],
         'compat_use_checksum'          => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: []
                                             },
                                             { meta_key_value_store: { use_checksum: false } }
                                           ],
         'compat_use_checksum2'         => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: []
                                             },
                                             { use_key_value_store_checksum: false }
                                           ],
         'compat_use_checksum_priority' => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: []
                                             },
                                             { meta_key_value_store: { use_checksum: false },
                                               use_key_value_store_checksum: true
                                             }
                                           ],
         'all'                          => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: { 'foo' => 'bar' },
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { storage: {
                                                 meta_key_value_store: {
                                                   type: 'gdbm',
                                                   configuration: { 'foo' => 'bar' },
                                                   use_checksum: true
                                                 }
                                               }
                                             }
                                           ],
         'priority'                     => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: { 'foo' => 'bar' },
                                               middleware_list: []
                                             },
                                             { storage: {
                                                 meta_key_value_store: {
                                                   type: 'gdbm',
                                                   configuration: { 'foo' => 'bar' },
                                                   use_checksum: false
                                                 }
                                               },
                                               meta_key_value_store: {
                                                 plug_in: 'qdbm',
                                                 configuration: { 'foo' => 'baz' },
                                                 use_checksum: true
                                               },
                                               key_value_store_type: 'qdbm',
                                               use_key_value_store_checksum: true
                                             }
                                           ])
    def test_make_meta_key_value_store_params(data)
      expected_params, config = data
      @c.load(config)
      assert_equal(expected_params, @c.make_meta_key_value_store_params.to_h)
    end

    data('default'                      => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             {}
                                           ],
         'origin_type'                  => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { storage: { text_key_value_store: { type: 'gdbm' } } }
                                           ],
         'compat_origin_type'           => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { text_key_value_store: { plug_in: 'gdbm' } }
                                           ],
         'compat_origin_type2'          =>  [ { origin_type: RIMS::GDBM_KeyValueStore,
                                                origin_config: {},
                                                middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                              },
                                              { key_value_store_type: 'gdbm' }
                                            ],
         'compat_origin_type_priority'  => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { text_key_value_store: { plug_in: 'gdbm' },
                                               key_value_store_type: 'qdbm'
                                             }
                                           ],
         'origin_config'                => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: { 'foo' => 'bar' },
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { storage: { text_key_value_store: { configuration: { 'foo' => 'bar' } } } }
                                           ],
         'compat_origin_config'         => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: { 'foo' => 'bar' },
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { text_key_value_store: { configuration: { 'foo' => 'bar' } }  }
                                           ],
         'use_checksum'                 => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { storage: { text_key_value_store: { use_checksum: true } } }
                                           ],
         'use_checksum_no'              => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: []
                                             },
                                             { storage: { text_key_value_store: { use_checksum: false } } }
                                           ],
         'compat_use_checksum'          => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: []
                                             },
                                             { text_key_value_store: { use_checksum: false } }
                                           ],
         'compat_use_checksum2'         => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: []
                                             },
                                             { use_key_value_store_checksum: false }
                                           ],
         'compat_use_checksum_priority' => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: {},
                                               middleware_list: []
                                             },
                                             { text_key_value_store: { use_checksum: false },
                                               use_key_value_store_checksum: true
                                             }
                                           ],
         'all'                          => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: { 'foo' => 'bar' },
                                               middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                             },
                                             { storage: {
                                                 text_key_value_store: {
                                                   type: 'gdbm',
                                                   configuration: { 'foo' => 'bar' },
                                                   use_checksum: true
                                                 }
                                               }
                                             }
                                           ],
         'priority'                     => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                               origin_config: { 'foo' => 'bar' },
                                               middleware_list: []
                                             },
                                             { storage: {
                                                 text_key_value_store: {
                                                   type: 'gdbm',
                                                   configuration: { 'foo' => 'bar' },
                                                   use_checksum: false
                                                 }
                                               },
                                               text_key_value_store: {
                                                 plug_in: 'qdbm',
                                                 configuration: { 'foo' => 'baz' },
                                                 use_checksum: true
                                               },
                                               key_value_store_type: 'qdbm',
                                               use_key_value_store_checksum: true
                                             }
                                           ])
    def test_make_text_key_value_store_params(data)
      expected_params, config = data
      @c.load(config)
      assert_equal(expected_params, @c.make_text_key_value_store_params.to_h)
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
    def test_make_authentication_default(data)
      auth = @c.make_authentication
      assert_equal(Socket.gethostname, auth.hostname)

      auth.start_plug_in(@logger)
      for pw in data[:presence]
        assert_equal(false, (auth.user? pw['user']), "user: #{pw['user']}")
        assert(! auth.authenticate_login(pw['user'], pw['pass']), "user: #{pw['user']}")
      end
      for pw in data[:absence]
        assert_equal(false, (auth.user? pw['user']), "user: #{pw['user']}")
        assert(! auth.authenticate_login(pw['user'], pw['pass']), "user: #{pw['user']}")
      end
      auth.stop_plug_in(@logger)
    end

    data('config'   => { authentication: { hostname: 'imap.example.com' } },
         'compat'   => { hostname: 'imap.example.com' },
         'priority' => { authentication: { hostname: 'imap.example.com' },
                         hostname: 'imap2.example.com'
                       })
    def test_make_authentication_hostname(config)
      @c.load(config)
      auth = @c.make_authentication
      assert_equal('imap.example.com', auth.hostname)
    end

    data('single'                   => [ authentication_users,
                                         { authentication: {
                                             password_sources: [
                                               { type: 'plain',
                                                 configuration: authentication_users[:presence]
                                               }
                                             ]
                                           }
                                         }
                                       ],
         'multiple'                 => [ authentication_users,
                                         { authentication: {
                                             password_sources: authentication_users[:presence].map{|pw|
                                               { type: 'plain',
                                                 configuration: [ pw ]
                                               }
                                             }
                                           }
                                         }
                                       ],
         'compat_username'          => [ { presence: [ authentication_users[:presence][0] ],
                                           absence: authentication_users[:absence]
                                         },
                                         { username: authentication_users[:presence][0]['user'],
                                           password: authentication_users[:presence][0]['pass'],
                                         }
                                       ],
         'compat_user_list'         => [ authentication_users,
                                         { user_list: authentication_users[:presence] }
                                       ],
         'compat_authentication'    => [ authentication_users,
                                         { authentication: [
                                             { plug_in: 'plain',
                                               configuration: authentication_users[:presence]
                                             }
                                           ]
                                         }
                                       ],
         'compat_priored_user_list' => [ authentication_users,
                                         { username: authentication_users[:presence][0]['user'],
                                           password: 'random',
                                           user_list: authentication_users[:presence],
                                           authentication: [
                                             { plug_in: 'plain',
                                               configuration: authentication_users[:presence].map{|pw|
                                                 { user: pw['user'],
                                                   pass: 'random'
                                                 }
                                               }
                                             }
                                           ]
                                         }
                                       ],
         'compat_priored_username'  => [ { presence: [ authentication_users[:presence][0] ],
                                           absence: authentication_users[:absence]
                                         },
                                         { username: authentication_users[:presence][0]['user'],
                                           password: authentication_users[:presence][0]['pass'],
                                           authentication: [
                                             { plug_in: 'plain',
                                               configuration: [
                                                 { user: authentication_users[:presence][0]['user'],
                                                   pass: 'random'
                                                 }
                                               ]
                                             }
                                           ]
                                         }
                                       ],
         'priority'                 => [ authentication_users,
                                         { authentication: {
                                             password_sources: [
                                               { type: 'plain',
                                                 configuration: authentication_users[:presence]
                                               }
                                             ]
                                           },
                                           username: authentication_users[:presence][0]['user'],
                                           password: 'random',
                                           user_list: authentication_users[:presence].map{|pw|
                                             { user: pw['user'],
                                               pass: 'random'
                                             }
                                           }
                                         }
                                       ])
    def test_make_authentication_password_sources(data)
      users, config = data
      @c.load(config)
      auth = @c.make_authentication

      auth.start_plug_in(@logger)
      for pw in users[:presence]
        assert_equal(true, (auth.user? pw['user']), "user: #{pw['user']}")
        assert(auth.authenticate_login(pw['user'], pw['pass']), "user: #{pw['user']}")
        assert(! auth.authenticate_login(pw['user'], pw['pass'].succ), "user: #{pw['user']}")
      end
      for pw in users[:absence]
        assert_equal(false, (auth.user? pw['user']), "user: #{pw['user']}")
        assert(! auth.authenticate_login(pw['user'], pw['pass']), "user: #{pw['user']}")
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

    data('default'  => [ '#postman', {} ],
         'config'   => [ 'alice', { authorization: { mail_delivery_user: 'alice' } } ],
         'compat'   => [ 'alice', { mail_delivery_user: 'alice' } ],
         'priority' => [ 'alice',
                         { authorization: { mail_delivery_user: 'alice' },
                           mail_delivery_user: 'bob'
                         }
                       ])
    def test_mail_delivery_user(data)
      expected_user, config = data
      @c.load(config)
      assert_equal(expected_user, @c.mail_delivery_user)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
