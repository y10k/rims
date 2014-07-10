# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class AuthenticationTest < Test::Unit::TestCase
    include RIMS::Test::PseudoAuthenticationUtility

    def setup
      src_time = Time.at(1404046689)
      random_seed = 70100924388646298230620504594645040907

      @time_source = make_pseudo_time_source(src_time)
      @random_string_source = make_pseudo_random_string_source(random_seed)

      @username = 'foo'
      @password = 'open_sesame'

      @auth = RIMS::Authentication.new(time_source: make_pseudo_time_source(src_time),
                                       random_string_source: make_pseudo_random_string_source(random_seed))
      @auth.entry(@username, @password)
    end

    def test_unique_user_id
      id1 = RIMS::Authentication.unique_user_id(@username)
      assert_instance_of(String, id1)
      refute(id1.empty?)

      id2 = RIMS::Authentication.unique_user_id(@username)
      assert_instance_of(String, id2)
      refute(id2.empty?)

      id3 = RIMS::Authentication.unique_user_id(@username.succ)
      assert_instance_of(String, id3)
      refute(id3.empty?)

      assert(id2.bytesize == id1.bytesize)
      assert(id3.bytesize == id3.bytesize)

      assert(id2 == id1)
      assert(id3 != id1)

      pp [ id1, id2, id3 ] if $DEBUG
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

    def test_make_time_source
      time_source = RIMS::Authentication.make_time_source

      t1 = time_source.call
      assert_instance_of(Time, t1)

      t2 = time_source.call
      assert_instance_of(Time, t2)

      assert(t1 != t2)
    end

    def test_pseudo_make_time_source
      t1 = @time_source.call
      assert_instance_of(Time, t1)

      t2 = @time_source.call
      assert_instance_of(Time, t2)

      assert(t1 != t2)
      assert(t1 + 1 == t2)
    end

    def test_make_random_string_source
      random_string_source = RIMS::Authentication.make_random_string_source

      s1 = random_string_source.call
      assert_instance_of(String, s1)
      refute(s1.empty?)

      s2 = random_string_source.call
      assert_instance_of(String, s2)
      refute(s2.empty?)

      assert(s1.bytesize == s2.bytesize)
      assert(s1 != s2)
    end

    def test_pseudo_make_random_string_source
      s1 = @random_string_source.call
      assert_instance_of(String, s1)
      refute(s1.empty?)

      s2 = @random_string_source.call
      assert_instance_of(String, s2)
      refute(s2.empty?)

      assert(s1.bytesize == s2.bytesize)
      assert(s1 != s2)
    end

    def test_cram_md5_server_challenge_data_class_method
      s1 = RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source)
      assert_instance_of(String, s1)
      refute(s1.empty?)

      s2 = RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source)
      assert_instance_of(String, s2)
      refute(s2.empty?)

      assert(s1 != s2)
    end

    def test_cram_md5_server_challenge_data
      assert_equal(RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source), @auth.cram_md5_server_challenge_data)
      assert_equal(RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source), @auth.cram_md5_server_challenge_data)
      assert_equal(RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source), @auth.cram_md5_server_challenge_data)
      assert_equal(RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source), @auth.cram_md5_server_challenge_data)
      assert_equal(RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source), @auth.cram_md5_server_challenge_data)
    end

    def cram_md5_client_response(username, password, server_challenge_data)
      "#{username} #{RIMS::Authentication.hmac_md5_hexdigest(password, server_challenge_data)}"
    end
    private :cram_md5_client_response

    def test_authenticate_cram_md5
      server_challenge_data = @auth.cram_md5_server_challenge_data
      assert_equal(@username, @auth.authenticate_cram_md5(server_challenge_data,
                                                          cram_md5_client_response(@username, @password, server_challenge_data)))
      assert_nil(@auth.authenticate_cram_md5(server_challenge_data,
                                             cram_md5_client_response(@username.succ, @password, server_challenge_data)))
      assert_nil(@auth.authenticate_cram_md5(server_challenge_data,
                                             cram_md5_client_response(@username, @password.succ, server_challenge_data)))
      assert_nil(@auth.authenticate_cram_md5(server_challenge_data,
                                             cram_md5_client_response(@username, @password, server_challenge_data.succ)))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
