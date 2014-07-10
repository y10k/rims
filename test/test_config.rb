# -*- coding: utf-8 -*-

require 'logger'
require 'pp' if $DEBUG
require 'rims'
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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
