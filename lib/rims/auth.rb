# -*- coding: utf-8 -*-

require 'openssl'
require 'securerandom'

module RIMS
  class Authentication
    class << self
      def make_time_source
        proc{ Time.now }
      end

      def make_random_string_source
        proc{ SecureRandom.uuid }
      end

      def cram_md5_server_challenge_data(hostname, time_source, random_string_source)
        s = random_string_source.call
        t = time_source.call
        "#{s}.#{t.to_i}@#{hostname}"
      end

      def hmac_md5_hexdigest(key, data)
        OpenSSL::HMAC.hexdigest('md5', key, data)
      end
    end

    def initialize(hostname: 'rims',
                   time_source: Authentication.make_time_source,
                   random_string_source: Authentication.make_random_string_source)
      @hostname = hostname
      @time_source = time_source
      @random_string_source = random_string_source
      @passwd = {}
    end

    def entry(username, password)
      @passwd[username] = password
      self
    end

    def capability
      %w[ PLAIN CRAM-MD5 ]
    end

    def authenticate_login(username, password)
      if (@passwd.key? username) then
        if (@passwd[username] == password) then
          username
        end
      end
    end

    def authenticate_plain(client_response_data)
      authz_id, authc_id, password = client_response_data.split("\0", 3)
      if (authz_id.empty? || (authz_id == authc_id)) then
        if (@passwd.key? authc_id) then
          if (@passwd[authc_id] == password) then
            authc_id
          end
        end
      end
    end

    def cram_md5_server_challenge_data
      self.class.cram_md5_server_challenge_data(@hostname, @time_source, @random_string_source)
    end

    def authenticate_cram_md5(server_challenge_data, client_response_data)
      username, client_hmac_result_data = client_response_data.split(' ', 2)
      if (key = @passwd[username]) then
        server_hmac_result_data = Authentication.hmac_md5_hexdigest(key, server_challenge_data)
        if (client_hmac_result_data == server_hmac_result_data) then
          username
        end
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
