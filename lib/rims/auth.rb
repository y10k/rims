# -*- coding: utf-8 -*-

require 'digest'
require 'openssl'
require 'securerandom'

module RIMS
  class Authentication
    class << self
      def unique_user_id(username)
        Digest::SHA256.hexdigest(username)
      end

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
      @capability = %w[ PLAIN CRAM-MD5 ]
      @plain_src = Password::PlainSource.new
      @passwd_src_list = [ @plain_src ]
    end

    attr_reader :hostname
    attr_reader :capability

    def add_plug_in(passwd_src)
      unless (passwd_src.raw_password?) then
        @capability.delete('CRAM-MD5')
      end
      @passwd_src_list << passwd_src
      self
    end

    def entry(username, password)
      @plain_src.entry(username, password)
      self
    end

    def user?(username)
      @passwd_src_list.any?{|passwd_src| passwd_src.user? username }
    end

    def authenticate_login(username, password)
      for passwd_src in @passwd_src_list
        if (passwd_src.user? username) then
          if (passwd_src.compare_password(username, password)) then
            return username
          end
        end
      end

      nil
    end

    def authenticate_plain(client_response_data)
      authz_id, authc_id, password = client_response_data.split("\0", 3)
      if (authz_id.empty? || (authz_id == authc_id)) then
        authenticate_login(authc_id, password)
      end
    end

    def cram_md5_server_challenge_data
      self.class.cram_md5_server_challenge_data(@hostname, @time_source, @random_string_source)
    end

    def authenticate_cram_md5(server_challenge_data, client_response_data)
      username, client_hmac_result_data = client_response_data.split(' ', 2)
      for passwd_src in @passwd_src_list
        if (passwd_src.raw_password?) then
          if (passwd_src.user? username) then
            key = passwd_src.fetch_password(username) or raise 'internal error.'
            server_hmac_result_data = Authentication.hmac_md5_hexdigest(key, server_challenge_data)
            if (client_hmac_result_data == server_hmac_result_data) then
              return username
            end
          end
        end
      end

      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
