# -*- coding: utf-8 -*-

require 'fileutils'
require 'logger'
require 'pp' if $DEBUG
require 'rims'
require 'socket'
require 'test/unit'

module RIMS::Test
  class ConfigTest < Test::Unit::TestCase
    def setup
      @base_dir = 'dummy_test_base_dir'
    end

    def assert_config(conf_params)
      conf = RIMS::Config.new
      conf.load(base_dir: @base_dir)
      conf.load(conf_params)
      yield(conf)
      assert_equal({}, conf.through_server_params, 'throuth_server_params')
    end
    private :assert_config

    def assert_logging_params(conf_params, expected_params)
      assert_config(conf_params) {|conf|
        assert_equal(expected_params, conf.logging_params, 'logging_params')
      }
    end
    private :assert_logging_params

    def assert_key_value_store_params(conf_params, expected_params)
      assert_config(conf_params) {|conf|
        assert_equal(expected_params, conf.key_value_store_params, 'key_value_store_params')
      }
    end
    private :assert_key_value_store_params

    def assert_build_authentication(conf_params)
      assert_config(conf_params) {|conf|
        yield(conf.build_authentication)
      }
    end
    private :assert_build_authentication

    def test_logging_params
      assert_logging_params({}, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: []
                            })

      assert_logging_params({ log_file: 'server.log' }, {
                              log_file: File.join(@base_dir, 'server.log'),
                              log_level: Logger::INFO,
                              log_opt_args: []
                            })

      assert_logging_params({ log_shift_age: 'daily' }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [ 'daily' ]
                            })

      assert_logging_params({ log_shift_size: 1024**2 }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [ 1, 1024**2 ]
                            })

      assert_logging_params({ log_shift_age: 10,
                              log_shift_size: 1024**2
                            }, {
                              log_file: File.join(@base_dir, 'imap.log'),
                              log_level: Logger::INFO,
                              log_opt_args: [ 10, 1024**2 ]
                            })
    end

    def test_key_value_store_params
      assert_key_value_store_params({}, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      assert_key_value_store_params({ key_value_store_type: 'GDBM' }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      assert_key_value_store_params({ use_key_value_store_checksum: true }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      middleware_key_value_store_list: [ RIMS::Checksum_KeyValueStore ]
                                    })

      assert_key_value_store_params({ use_key_value_store_checksum: false }, {
                                      origin_key_value_store: RIMS::GDBM_KeyValueStore,
                                      middleware_key_value_store_list: []
                                    })
    end

    def test_build_authentication
      username = 'foo'
      password = 'open_sesame'

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

    def test_mkdir_from_base_dir
      Dir.mkdir(@base_dir)

      refute(File.directory? File.join(@base_dir, 'foo', 'bar'))
      RIMS::Config.mkdir_from_base_dir(@base_dir, %w[ foo bar ])
      assert(File.directory? File.join(@base_dir, 'foo', 'bar'))
    end

    def test_mkdir_from_base_dir_already_exist
      FileUtils.mkdir_p(File.join(@base_dir, 'foo', 'bar'))

      assert(File.directory? File.join(@base_dir, 'foo', 'bar'))
      RIMS::Config.mkdir_from_base_dir(@base_dir, %w[ foo bar ])
      assert(File.directory? File.join(@base_dir, 'foo', 'bar'))
    end

    def test_mkdir_from_base_dir_not_exist_base_dir
      refute(File.directory? @base_dir)
      assert_raise(RuntimeError) {
        RIMS::Config.mkdir_from_base_dir(@base_dir, %w[ foo bar ])
      }
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
