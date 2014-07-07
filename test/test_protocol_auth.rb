# -*- coding: utf-8 -*-

require 'logger'
require 'rims'
require 'test/unit'

module RIMS::Test
  class ProtocolAuthenticationReaderTest < Test::Unit::TestCase
    include RIMS::Test::PseudoAuthenticationUtility

    def setup
      src_time = Time.at(1404360345)
      random_seed = 212687380986801693724170864620978811477

      @time_source = make_pseudo_time_source(src_time)
      @random_string_source = make_pseudo_random_string_source(random_seed)

      @username = 'foo'
      @password = 'open_sesame'

      @auth = RIMS::Authentication.new(time_source: make_pseudo_time_source(src_time),
                                       random_string_source: make_pseudo_random_string_source(random_seed))
      @auth.entry(@username, @password)

      @input = StringIO.new('', 'r')
      @output = StringIO.new('', 'w')

      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL

      @reader = RIMS::Protocol::AuthenticationReader.new(@auth, @input, @output, @logger)
    end

    def assert_input_output_stream(input_txt, expected_output_txt)
      @input.string = input_txt
      @output.string = ''
      yield
      assert_equal('', @input.read)
      assert_equal(expected_output_txt, @output.string)
    end
    private :assert_input_output_stream

    def client_plain_response_base64(authorization_id, authentication_id, plain_password)
      response_txt = [ authorization_id, authentication_id, plain_password ].join("\0")
      RIMS::Protocol::AuthenticationReader.encode_base64(response_txt)
    end
    private :client_plain_response_base64

    def test_authenticate_client_plain_inline
      assert_equal(@username, @reader.authenticate_client('plain', client_plain_response_base64(@username, @username, @password)))
      assert_equal(@username, @reader.authenticate_client('plain', client_plain_response_base64('', @username, @password)))

      assert_nil(@reader.authenticate_client('plain', client_plain_response_base64(@username, @username, @password.succ)))
      assert_nil(@reader.authenticate_client('plain', client_plain_response_base64(@username.succ, @username.succ, @password)))

      assert_equal('', @output.string)
    end

    def test_authenticate_client_plain_stream
      assert_input_output_stream(client_plain_response_base64(@username, @username, @password) + "\r\n", "+ \r\n") {
        assert_equal(@username, @reader.authenticate_client('plain'), 'call of authentication reader.')
      }
      assert_input_output_stream(client_plain_response_base64('', @username, @password) + "\r\n", "+ \r\n") {
        assert_equal(@username, @reader.authenticate_client('plain'), 'call of authentication reader.')
      }

      assert_input_output_stream(client_plain_response_base64(@username, @username, @password.succ) + "\r\n", "+ \r\n") {
        assert_nil(@reader.authenticate_client('plain'), 'authenticate_client(plain)')
      }
      assert_input_output_stream(client_plain_response_base64(@username.succ, @username.succ, @password) + "\r\n", "+ \r\n") {
        assert_nil(@reader.authenticate_client('plain'), 'authenticate_client(plain)')
      }
    end

    def test_authenticate_client_plain_stream_no_client_authentication
      assert_input_output_stream("*\r\n", "+ \r\n") {
        assert_equal(:*, @reader.authenticate_client('plain'))
      }
    end

    def make_cram_md5_server_client_data_base64(username, password)
      server_challenge_data = RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source)
      client_response_data = username + ' ' + RIMS::Authentication.hmac_md5_hexdigest(password, server_challenge_data)

      server_challenge_data_base64 = RIMS::Protocol::AuthenticationReader.encode_base64(server_challenge_data)
      client_response_data_base64 = RIMS::Protocol::AuthenticationReader.encode_base64(client_response_data)

      return server_challenge_data_base64, client_response_data_base64
    end
    private :make_cram_md5_server_client_data_base64

    def test_authenticate_client_cram_md5_stream
      server_challenge_data_base64, client_response_data_base64 = make_cram_md5_server_client_data_base64(@username, @password)
      assert_input_output_stream(client_response_data_base64 + "\r\n", "+ #{server_challenge_data_base64}\r\n") {
        assert_equal(@username, @reader.authenticate_client('cram-md5'))
      }

      server_challenge_data_base64, client_response_data_base64 = make_cram_md5_server_client_data_base64(@username.succ, @password)
      assert_input_output_stream(client_response_data_base64 + "\r\n", "+ #{server_challenge_data_base64}\r\n") {
        assert_nil(@reader.authenticate_client('cram-md5'), 'authenticate_client(cram-md5)')
      }

      server_challenge_data_base64, client_response_data_base64 = make_cram_md5_server_client_data_base64(@username, @password.succ)
      assert_input_output_stream(client_response_data_base64 + "\r\n", "+ #{server_challenge_data_base64}\r\n") {
        assert_nil(@reader.authenticate_client('cram-md5'), 'authenticate_client(cram-md5)')
      }
    end

    def test_authenticate_client_cram_md5_stream_no_client_authentication
      server_challenge_data_base64, client_response_data_base64 = make_cram_md5_server_client_data_base64(@username, @password)
      assert_input_output_stream("*\r\n", "+ #{server_challenge_data_base64}\r\n") {
        assert_equal(:*, @reader.authenticate_client('cram-md5'))
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
