# -*- coding: utf-8 -*-

require 'digest'
require 'fileutils'
require 'logger'
require 'pp' if $DEBUG
require 'rims'
require 'socket'
require 'test/unit'
require 'yaml'

module RIMS::Test
  class ConfigTest < Test::Unit::TestCase
    def setup
      @base_dir = 'dummy_test_base_dir'
    end

    def teardown
      FileUtils.rm_rf(@base_dir)
    end

    def assert_load_from_base_dir(conf_params)
      conf = RIMS::Config.new
      conf.load_config_from_base_dir(conf_params, @base_dir)
      yield(conf)
    end
    private :assert_load_from_base_dir

    def assert_config(conf_params)
      conf = RIMS::Config.new
      conf.load(base_dir: @base_dir)
      conf.load(conf_params)
      yield(conf)
    end
    private :assert_config

    def assert_logging_params(conf_params, expected_params)
      assert_config(conf_params) {|conf|
        assert_equal(expected_params, conf.logging_params, 'logging_params')
        assert_equal({}, conf.through_server_params, 'throuth_server_params')
      }
    end
    private :assert_logging_params

    def assert_key_value_store_params(db_type, conf_params, expected_params)
      assert_config(conf_params) {|conf|
        assert_equal(expected_params, conf.key_value_store_params(db_type), 'key_value_store_params')
        assert_equal({}, conf.through_server_params, 'throuth_server_params')
      }
    end
    private :assert_key_value_store_params

    def assert_build_authentication(conf_params)
      assert_config(conf_params) {|conf|
        yield(conf.build_authentication)
        assert_equal({}, conf.through_server_params, 'throuth_server_params')
      }
    end
    private :assert_build_authentication

    def assert_privilege_params(conf_params, expected_params)
      assert_config(conf_params) {|conf|
        if ((expected_params.is_a? Class) && (expected_params <= Exception)) then
          assert_raise(expected_params) { conf.setup_privilege_params }
        else
          conf.setup_privilege_params
          assert_equal(expected_params, conf.through_server_params)
        end
      }
    end
    private :assert_privilege_params

    def test_load_from_base_dir
      assert_load_from_base_dir({}) {|conf|
        assert_equal(@base_dir, conf.base_dir)
        assert_equal({}, conf.through_server_params)
      }

      assert_load_from_base_dir({ ip_addr: '192.168.0.1' }) {|conf|
        assert_equal(@base_dir, conf.base_dir)
        assert_equal({ ip_addr: '192.168.0.1' }, conf.through_server_params)
      }

      assert_load_from_base_dir({ base_dir: 'foo' }) {|conf|
        assert_equal(File.join(@base_dir, 'foo'), conf.base_dir)
        assert_equal({}, conf.through_server_params)
      }

      assert_load_from_base_dir({ base_dir: 'foo', ip_addr: '192.168.0.1' }) {|conf|
        assert_equal(File.join(@base_dir, 'foo'), conf.base_dir)
        assert_equal({ ip_addr: '192.168.0.1' }, conf.through_server_params)
      }

      assert_load_from_base_dir({ base_dir: '/foo' }) {|conf|
        assert_equal('/foo', conf.base_dir)
        assert_equal({}, conf.through_server_params)
      }

      assert_load_from_base_dir({ base_dir: '/foo', ip_addr: '192.168.0.1' }) {|conf|
        assert_equal('/foo', conf.base_dir)
        assert_equal({ ip_addr: '192.168.0.1' }, conf.through_server_params)
      }
    end

    def test_load_libraries
      assert(! $LOADED_FEATURES.any?{|name| name =~ /prime/})
      fork{
        begin
          assert_config(load_libraries: %w[ prime ]) {|conf|
            conf.setup_load_libraries
            assert($LOADED_FEATURES.any?{|name| name =~ /prime/})
          }
        rescue
          exit!(1)
        end
        exit!(0)
      }
      Process.wait
      assert_equal(0, $?.exitstatus)
    end

    def test_logging_params
      assert_logging_params({}, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_level: 'debug' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::DEBUG,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_level: 'info' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_level: 'warn' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::WARN,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_level: 'error' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::ERROR,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_stdout: 'debug' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::DEBUG
                            })

      assert_logging_params({ log_stdout: 'info' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_stdout: 'warn' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::WARN
                            })

      assert_logging_params({ log_stdout: 'error' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::ERROR
                            })

      assert_logging_params({ log_file: 'server.log' }, {
                              log_file: File.join(@base_dir, 'server.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_file: 'foo/bar/server.log' }, {
                              log_file: File.join(@base_dir, 'foo/bar/server.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_file: '/var/rims/server.log' }, {
                              log_file: '/var/rims/server.log',
                              log_level: Logger::INFO,
                              log_opt_args: [],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_shift_age: 'daily' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [ 'daily' ],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_shift_size: 1024**2 }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [ 1, 1024**2 ],
                              log_stdout: Logger::INFO
                            })

      assert_logging_params({ log_shift_age: 10,
                              log_shift_size: 1024**2
                            }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [ 10, 1024**2 ],
                              log_stdout: Logger::INFO
                            })
    end

    def test_key_value_store_params
      assert_key_value_store_params(:meta_key_value_store, {}, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: {},
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      assert_key_value_store_params(:meta_key_value_store, {
                                      meta_key_value_store: {
                                        'plug_in' => 'gdbm'
                                      }
                                    }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: {},
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      assert_key_value_store_params(:meta_key_value_store, {
                                      meta_key_value_store: {
                                        'plug_in' => 'gdbm',
                                        'configuration' => { 'foo' => 'bar' }
                                      }
                                    }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: { 'foo' => 'bar' },
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      FileUtils.mkdir_p(@base_dir)
      IO.write(File.join(@base_dir, 'config.yml'), { 'foo' => 'bar' }.to_yaml)

      assert_key_value_store_params(:meta_key_value_store, {
                                      meta_key_value_store: {
                                        'plug_in' => 'gdbm',
                                        'configuration_file' => 'config.yml'
                                      }
                                    }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: { 'foo' => 'bar' },
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      assert_key_value_store_params(:meta_key_value_store, {
                                      meta_key_value_store: {
                                        'use_checksum' => true
                                      }
                                    }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: {},
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      assert_key_value_store_params(:meta_key_value_store, {
                                      meta_key_value_store: {
                                        'use_checksum' => false
                                      }
                                    }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: {},
                                      middleware_key_value_store_list: []
                                    })

      # for backward compatibility
      assert_key_value_store_params(:meta_key_value_store, { key_value_store_type: 'gdbm' }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: {},
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      # for backward compatibility
      assert_key_value_store_params(:meta_key_value_store, { use_key_value_store_checksum: true }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: {},
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      # for backward compatibility
      assert_key_value_store_params(:meta_key_value_store, { use_key_value_store_checksum: false }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      origin_config: {},
                                      middleware_key_value_store_list: []
                                    })
    end

    def test_build_authentication
      username = 'foo'
      password = 'open_sesame'
      salt = "\x8F\x16\x63\x6D\x21\xE0\x0F\x3D"

      assert_build_authentication({ username: username, password: password }) {|auth|
        assert_equal(Socket.gethostname, auth.hostname, 'hostname')
        assert(auth.authenticate_login(username, password), 'user')
        refute(auth.authenticate_login(username.succ, password), 'mismatch username')
        refute(auth.authenticate_login(username, password.succ), 'mismatch password')
      }

      assert_build_authentication({ username: username, password: password, hostname: 'rims-test' }) {|auth|
        assert_equal('rims-test', auth.hostname, 'hostname')
        assert(auth.authenticate_login(username, password), 'user')
        refute(auth.authenticate_login(username.succ, password), 'mismatch username')
        refute(auth.authenticate_login(username, password.succ), 'mismatch password')
      }

      assert_build_authentication({ user_list: [
                                      { 'user' => username, 'pass' => password },
                                      { 'user' => username.succ, 'pass' => password.succ }
                                    ]
                                  }) {|auth|
        assert(auth.authenticate_login(username, password), 'user 1')
        assert(auth.authenticate_login(username.succ, password.succ), 'user 2')
        refute(auth.authenticate_login(username.succ.succ, password.succ.succ), 'user 3')
      }

      assert_build_authentication({ username: username, password: password,
                                    user_list: [
                                      { 'user' => username.succ, 'pass' => password.succ }
                                    ]
                                  }) {|auth|
        assert(auth.authenticate_login(username, password), 'user 1')
        assert(auth.authenticate_login(username.succ, password.succ), 'user 2')
        refute(auth.authenticate_login(username.succ.succ, password.succ.succ), 'user 3')
      }

      assert_build_authentication({ authentication: [
                                      { 'plug_in' => 'plain',
                                        'configuration' => [
                                          { 'user' => username, 'pass' => password }
                                        ]
                                      }
                                    ]
                                  }) {|auth|
        assert(auth.authenticate_login(username, password), 'user')
        refute(auth.authenticate_login(username.succ, password), 'mismatch username')
        refute(auth.authenticate_login(username, password.succ), 'mismatch password')
      }

      assert_build_authentication({ authentication: [
                                      { 'plug_in' => 'hash',
                                        'configuration' => [
                                          { 'user' => username,
                                            'hash' => RIMS::Password::HashSource.make_entry(Digest::SHA256, 1000, salt, password).to_s
                                          }
                                        ]
                                      }
                                    ]
                                  }) {|auth|
        assert(auth.authenticate_login(username, password), 'user')
        refute(auth.authenticate_login(username.succ, password), 'mismatch username')
        refute(auth.authenticate_login(username, password.succ), 'mismatch password')
      }

      FileUtils.mkdir_p(@base_dir)
      IO.write(File.join(@base_dir, 'passwd.yml'), [
                 { 'user' => username, 'pass' => password }
               ].to_yaml)

      assert_build_authentication({ authentication: [
                                      { 'plug_in' => 'plain',
                                        'configuration_file' => 'passwd.yml'
                                      }
                                    ]
                                  }) {|auth|
        assert(auth.authenticate_login(username, password), 'user')
        refute(auth.authenticate_login(username.succ, password), 'mismatch username')
        refute(auth.authenticate_login(username, password.succ), 'mismatch password')
      }

      IO.write(File.join(@base_dir, 'passwd.yml'), [
                 { 'user' => username,
                   'hash' => RIMS::Password::HashSource.make_entry(Digest::SHA256, 1000, salt, password).to_s
                 }
               ].to_yaml)

      assert_build_authentication({ authentication: [
                                      { 'plug_in' => 'hash',
                                        'configuration_file' => 'passwd.yml'
                                      }
                                    ]
                                  }) {|auth|
        assert(auth.authenticate_login(username, password), 'user')
        refute(auth.authenticate_login(username.succ, password), 'mismatch username')
        refute(auth.authenticate_login(username, password.succ), 'mismatch password')
      }
    end

    def test_setup_privilege_params
      assert_privilege_params({}, {
                                process_privilege_uid: 65534,
                                process_privilege_gid: 65534
                              })

      assert_privilege_params({ process_privilege_user: 'root',
                                process_privilege_group: '0'
                              }, {
                                process_privilege_uid: 0,
                                process_privilege_gid: 0
                              })

      assert_privilege_params({ process_privilege_user: 0,
                                process_privilege_group: 0
                              }, {
                                process_privilege_uid: 0,
                                process_privilege_gid: 0
                              })

      assert_privilege_params({ process_privilege_user: 'detarame',
                                process_privilege_group: 0
                              },
                              ArgumentError)

      assert_privilege_params({ process_privilege_user: 0,
                                process_privilege_group: :detarame
                              },
                              TypeError)
    end
  end

  class ConfigPathUtilTest < Test::Unit::TestCase
    def setup
      @base_dir = "dummy_test_base_dir.#{$$}"
      FileUtils.rm_rf(@base_dir) if (File.directory? @base_dir)
    end

    def teardown
      FileUtils.rm_rf(@base_dir) unless $DEBUG
    end

    def test_load_plug_in_configuration
      assert_equal({},RIMS::Config.load_plug_in_configuration(@base_dir, {}))
      assert_equal({ 'foo' => 'bar' },
                   RIMS::Config.load_plug_in_configuration(@base_dir,
                                                           { 'configuration' => { 'foo' => 'bar' } }))

      FileUtils.mkdir_p(@base_dir)
      IO.write(File.join(@base_dir, 'config.yml'), { 'foo' => 'bar' }.to_yaml)
      assert_equal({ 'foo' => 'bar' },
                   RIMS::Config.load_plug_in_configuration(@base_dir,
                                                           { 'configuration_file' => 'config.yml' }))

      assert_raise(RuntimeError) {
        RIMS::Config.load_plug_in_configuration(@base_dir, {
                                                  'configuration' => { 'foo' => 'bar' },
                                                  'configuration_file' => 'config.yml'
                                                })
      }
    end

    def test_mkdir_from_base_dir
      target_dir = File.join(@base_dir, 'foo', 'bar')
      Dir.mkdir(@base_dir)

      refute(File.directory? target_dir)
      assert_equal(target_dir, RIMS::Config.mkdir_from_base_dir(@base_dir, %w[ foo bar ]))
      assert(File.directory? target_dir)
    end

    def test_mkdir_from_base_dir_already_exist_dir
      target_dir = File.join(@base_dir, 'foo', 'bar')
      FileUtils.mkdir_p(target_dir)

      assert(File.directory? target_dir)
      assert_nil(RIMS::Config.mkdir_from_base_dir(@base_dir, %w[ foo bar ]))
      assert(File.directory? target_dir)
    end

    def test_mkdir_from_base_dir_already_exist_file
      target_dir = File.join(@base_dir, 'foo', 'bar')
      FileUtils.mkdir_p(File.dirname(target_dir))
      FileUtils.touch(target_dir)

      assert(File.file? target_dir)
      assert_raise(RuntimeError) {
        RIMS::Config.mkdir_from_base_dir(@base_dir, %w[ foo bar ])
      }
      assert(File.file? target_dir)
    end

    def test_mkdir_from_base_dir_not_exist_base_dir
      refute(File.directory? @base_dir)
      assert_raise(RuntimeError) {
        RIMS::Config.mkdir_from_base_dir(@base_dir, %w[ foo bar ])
      }
      refute(File.directory? @base_dir)
    end

    def test_make_key_value_store_path_name_list
      assert_equal([ 'v1', 'ab', 'c' ],
                   RIMS::Config.make_key_value_store_path_name_list('v1', 'abc'))
      assert_equal([ 'v1', 'e3', 'b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' ],
                   RIMS::Config.make_key_value_store_path_name_list('v1', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'))
      assert_equal([ 'v1', 'e3', 'b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'meta_db' ],
                   RIMS::Config.make_key_value_store_path_name_list('v1', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', db_name: 'meta_db'))

      assert_raise(ArgumentError) { RIMS::Config.make_key_value_store_path_name_list('v1', '') }
      assert_raise(ArgumentError) { RIMS::Config.make_key_value_store_path_name_list('v1', 'ab') }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
