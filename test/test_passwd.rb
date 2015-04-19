# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class PasswordPlainSourceTest < Test::Unit::TestCase
    def setup
      @username = 'foo'
      @password = 'open_sesame'
      @src = RIMS::Password::PlainSource.new
      @src.entry(@username, @password)
    end

    def test_raw_password?
      assert_equal(true, @src.raw_password?)
    end

    def test_user?
      assert_equal(true, (@src.user? @username))
      assert_equal(false, (@src.user? @username.succ))
    end

    def test_fetch_password
      assert_equal(@password, @src.fetch_password(@username))
      assert_nil(@src.fetch_password(@username.succ))
    end

    def test_compare_password
      assert_equal(true, @src.compare_password(@username, @password))
      assert_equal(false, @src.compare_password(@username, @password.succ))
      assert_nil(@src.compare_password(@username.succ, @password))
    end

    def test_build_from_conf
      config = [
        { 'user' => @username, 'pass' => @password }
      ]
      @src = RIMS::Password::PlainSource.build_from_conf(config)

      test_user?
      test_fetch_password
      test_compare_password
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
