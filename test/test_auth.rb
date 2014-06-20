# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class AuthenticationTest < Test::Unit::TestCase
    def setup
      @username = 'foo'
      @password = 'open_sesame'

      @auth = RIMS::Authentication.new
      @auth.entry(@username, @password)
    end

    def test_authenticate_login
      assert_equal(@username, @auth.authenticate_login(@username, @password))
      assert_nil(@auth.authenticate_login(@username, @password.succ))
      assert_nil(@auth.authenticate_login(@username.succ, @password))
    end

    def test_authenticate_plain
      authz_id = @username
      authc_id = @username

      assert_equal(@username, @auth.authenticate_plain([ authz_id, authc_id, @password ].join("\0")))
      assert_nil(@auth.authenticate_plain([ authz_id.succ, authc_id, @password ].join("\0")))
      assert_nil(@auth.authenticate_plain([ authz_id, authc_id.succ, @password ].join("\0")))
      assert_nil(@auth.authenticate_plain([ authz_id, authc_id, @password.succ ].join("\0")))

      assert_equal(@username, @auth.authenticate_plain([ '', authc_id, @password ].join("\0")))
      assert_nil(@auth.authenticate_plain([ '', authc_id.succ, @password ].join("\0")))
      assert_nil(@auth.authenticate_plain([ '', authc_id, @password.succ ].join("\0")))

      assert_nil(@auth.authenticate_plain([ authz_id, '', @password ].join("\0")))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
