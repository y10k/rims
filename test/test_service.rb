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

    unless (TLS_SERVER_PKEY.file? && TLS_SERVER_CERT.file?) then
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
         'config'   => [ 1024 * 64, { server: { send_buffer_limit_size: 1024 * 64 } } ],
         'compat'   => [ 1024 * 64, { send_buffer_limit: 1024 * 64 } ],
         'priority' => [ 1024 * 64,
                         { server: { send_buffer_limit_size: 1024 * 64 },
                           send_buffer_limit: 1024 * 32
                         }
                       ])
    def test_send_buffer_limit_size(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.send_buffer_limit_size)
    end

    data('default'  => [ 30, {} ],
         'config'   => [ 15, { lock: { read_lock_timeout_seconds: 15 } } ],
         'compat'   => [ 15, { read_lock_timeout_seconds: 15 } ],
         'priority' => [ 15,
                         { lock: { read_lock_timeout_seconds: 15 },
                           read_lock_timeout_seconds: 20
                         }
                       ])
    def test_read_lock_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.read_lock_timeout_seconds)
    end

    data('default'  => [ 30, {} ],
         'config'   => [ 15, { lock: { write_lock_timeout_seconds: 15 } } ],
         'compat'   => [ 15, { write_lock_timeout_seconds: 15 } ],
         'priority' => [ 15,
                         { lock: { write_lock_timeout_seconds: 15 },
                           write_lock_timeout_seconds: 20,
                         }
                       ])
    def test_write_lock_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.write_lock_timeout_seconds)
    end

    data('default'  => [ 1, {} ],
         'config'   => [ 3, { lock: { cleanup_write_lock_timeout_seconds: 3 } } ],
         'compat'   => [ 3, { cleanup_write_lock_timeout_seconds: 3 } ],
         'priority' => [ 3,
                         { lock: { cleanup_write_lock_timeout_seconds: 3 },
                           cleanup_write_lock_timeout_seconds: 5
                         }
                       ])
    def test_cleanup_write_lock_timeout_seconds(data)
      expected_value, config = data
      @c.load(config)
      assert_equal(expected_value, @c.cleanup_write_lock_timeout_seconds)
    end

    data('default'         => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: {},
                                  middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                },
                                {}
                              ],
         'origin_type'     => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: {},
                                  middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                },
                                { storage: { meta_key_value_store: { type: 'gdbm' } } }
                              ],
         'origin_config'   => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: { 'foo' => 'bar' },
                                  middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                },
                                { storage: { meta_key_value_store: { configuration: { 'foo' => 'bar' } } } }
                              ],
         'use_checksum'    => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: {},
                                  middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                },
                                { storage: { meta_key_value_store: { use_checksum: true } } }
                              ],
         'use_checksum_no' => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: {},
                                  middleware_list: []
                                },
                                { storage: { meta_key_value_store: { use_checksum: false } } }
                              ],
         'all'             => [ { origin_type: RIMS::GDBM_KeyValueStore,
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
                              ])
    def test_make_meta_key_value_store_params(data)
      expected_params, config = data
      @c.load(config)
      assert_equal(expected_params, @c.make_meta_key_value_store_params.to_h)
    end

    data('default'         => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: {},
                                  middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                },
                                {}
                              ],
         'origin_type'     => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: {},
                                  middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                },
                                { storage: { text_key_value_store: { type: 'gdbm' } } }
                              ],
         'origin_config'   => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: { 'foo' => 'bar' },
                                  middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                },
                                { storage: { text_key_value_store: { configuration: { 'foo' => 'bar' } } } }
                              ],
         'use_checksum'    => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: {},
                                  middleware_list: [ RIMS::Checksum_KeyValueStore ]
                                },
                                { storage: { text_key_value_store: { use_checksum: true } } }
                              ],
         'use_checksum_no' => [ { origin_type: RIMS::GDBM_KeyValueStore,
                                  origin_config: {},
                                  middleware_list: []
                                },
                                { storage: { text_key_value_store: { use_checksum: false } } }
                              ],
         'all'             => [ { origin_type: RIMS::GDBM_KeyValueStore,
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
