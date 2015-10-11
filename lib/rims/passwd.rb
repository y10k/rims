# -*- coding: utf-8 -*-

require 'digest'
require 'securerandom'

module RIMS
  module Password
    class Source
      attr_writer :logger

      def start
      end

      def stop
      end

      def raw_password?
        false
      end

      def user?(username)
        raise NotImplementedError, 'not implemented.'
      end

      def fetch_password(username)
        nil
      end

      def compare_password(username, password)
        if (raw_password = fetch_password(username)) then
          password == raw_password
        end
      end

      def self.build_from_conf(config)
        raise NotImplementedError, 'not implemented.'
      end
    end

    class PlainSource < Source
      def initialize
        @passwd = {}
      end

      def start
        if (@logger.debug?) then
          @passwd.each_key do |name|
            @logger.debug("user name: #{name}")
          end
        end
        nil
      end

      def stop
        @passwd.clear
        nil
      end

      def raw_password?
        true
      end

      def entry(username, password)
        @passwd[username] = password
        self
      end

      def user?(username)
        @passwd.key? username
      end

      def fetch_password(username)
        @passwd[username]
      end

      def self.build_from_conf(config)
        plain_src = self.new
        for user_entry in config
          plain_src.entry(user_entry['user'], user_entry['pass'])
        end

        plain_src
      end
    end
    Authentication.add_plug_in('plain', PlainSource)

    class HashSource < Source
      class Entry
        def self.encode(digest, stretch_count, salt, password)
          salt_password = salt.b + password.b
          digest.update(salt_password)
          stretch_count.times do
            digest.update(digest.digest + salt_password)
          end
          digest.hexdigest
        end

        def initialize(digest_factory, stretch_count, salt, hash)
          @digest_factory = digest_factory
          @stretch_count = stretch_count
          @salt = salt
          @hash = hash
        end

        def hash_type
          @digest_factory.to_s.sub(/^Digest::/, '')
        end

        attr_reader :stretch_count
        attr_reader :salt
        attr_reader :hash

        def salt_base64
          Protocol.encode_base64(@salt)
        end

        def to_s
          [ hash_type, @stretch_count, salt_base64, @hash ].join(':')
        end

        def compare(password)
          self.class.encode(@digest_factory.new, @stretch_count, @salt, password) == @hash
        end
      end

      def self.search_digest_factory(hash_type)
        if (digest_factory = Digest.const_get(hash_type)) then
          if (digest_factory < Digest::Base) then
            return digest_factory
          end
        end
        raise TypeError, "not a digest factory: #{hash_type}"
      end

      def self.make_salt_generator(octets)
        proc{ SecureRandom.random_bytes(octets) }
      end

      def self.make_entry(digest_factory, stretch_count, salt, password)
        hash = Entry.encode(digest_factory.new, stretch_count, salt, password)
        Entry.new(digest_factory, stretch_count, salt, hash)
      end

      # hash password format:
      #     [hash type]:[stretch count]:[base64 encoded salt]:[password hash hex digest]
      # example:
      #     SHA256:1000:2tImt4kLqLM=:756f633bf70613555aa93a5be1e5d93adfe87160e794abc6294c3b58a18f93aa
      def self.parse_entry(password_hash)
        hash_type, stretch_count, salt_base64, hash = password_hash.split(':', 4)
        digest_factory = search_digest_factory(hash_type)
        stretch_count = stretch_count.to_i
        salt = Protocol.decode_base64(salt_base64)
        Entry.new(digest_factory, stretch_count, salt, hash)
      end

      def initialize
        @passwd = {}
      end

      def start
        if (@logger.debug?) then
          for name, entry in @passwd
            @logger.debug("user name: #{name}")
            @logger.debug("password hash: #{entry}")
          end
        end
        nil
      end

      def stop
        @passwd.clear
        nil
      end

      def raw_password?
        false
      end

      def add(username, entry)
        @passwd[username] = entry
        self
      end

      def user?(username)
        @passwd.key? username
      end

      def compare_password(username, password)
        if (entry = @passwd[username]) then
          entry.compare(password)
        end
      end

      def self.build_from_conf(config)
        hash_src = self.new
        for user_entry in config
          hash_src.add(user_entry['user'], parse_entry(user_entry['hash']))
        end

        hash_src
      end
    end
    Authentication.add_plug_in('hash', HashSource)
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
