# -*- coding: utf-8 -*-

require 'digest'
require 'logger'
require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class PasswordPlainSourceTest < Test::Unit::TestCase
    def setup
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL

      @username = 'foo'
      @password = 'open_sesame'

      @src = RIMS::Password::PlainSource.new
      @src.entry(@username, @password)
      @src.logger = @logger
      @src.start
    end

    def teardown
      @src.stop
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
      assert(@src.compare_password(@username, @password))
      assert(! @src.compare_password(@username, @password.succ))
      assert(! @src.compare_password(@username.succ, @password))
    end

    def test_build_from_conf
      @src.stop

      config = [
        { 'user' => @username, 'pass' => @password }
      ]
      @src = RIMS::Password::PlainSource.build_from_conf(config)
      @src.logger = @logger
      @src.start

      test_user?
      test_fetch_password
      test_compare_password
    end
  end

  class PasswordHashSourceEntryTest < Test::Unit::TestCase
    def setup
      @digest_factory = Digest::SHA256
      @hash_type = 'SHA256'
      @strech_count = 1000
      @salt = "\332\322\046\267\211\013\250\263".b
      @password = 'open_sesame'
      @entry = RIMS::Password::HashSource.make_entry(@digest_factory, @strech_count, @salt, @password)
      pp @entry if $DEBUG
    end

    def new_digest
      @digest_factory.new
    end
    private :new_digest

    def test_encode
      encoded_password = RIMS::Password::HashSource::Entry.encode(new_digest, @strech_count, @salt, @password)
      assert_equal(encoded_password,
                   RIMS::Password::HashSource::Entry.encode(new_digest, @strech_count, @salt, @password))
      assert_not_equal(encoded_password,
                   RIMS::Password::HashSource::Entry.encode(new_digest, @strech_count.succ, @salt, @password))
      assert_not_equal(encoded_password,
                   RIMS::Password::HashSource::Entry.encode(new_digest, @strech_count, @salt.succ, @password))
      assert_not_equal(encoded_password,
                   RIMS::Password::HashSource::Entry.encode(new_digest, @strech_count, @salt, @password.succ))
    end

    def test_entry
      assert_equal(@hash_type, @entry.hash_type)
      assert_equal(@salt, @entry.salt)
      assert_equal(RIMS::Protocol.encode_base64(@salt), @entry.salt_base64)
      assert_equal(RIMS::Password::HashSource::Entry.encode(new_digest, @strech_count, @salt, @password), @entry.hash)
    end

    def test_search_digest_factory
      assert_equal(Digest::MD5, RIMS::Password::HashSource.search_digest_factory('MD5'))
      assert_equal(Digest::SHA256, RIMS::Password::HashSource.search_digest_factory('SHA256'))
      assert_raise(LoadError) { RIMS::Password::HashSource.search_digest_factory('NoDigest') }
      assert_raise(TypeError) { RIMS::Password::HashSource.search_digest_factory('Object') }
    end

    def test_make_salt_generator
      salt_generator = RIMS::Password::HashSource.make_salt_generator(8)

      s1 = salt_generator.call
      assert_equal(8, s1.bytesize)
      assert_equal(Encoding::ASCII_8BIT, s1.encoding)

      s2 = salt_generator.call
      assert_equal(8, s2.bytesize)
      assert_equal(Encoding::ASCII_8BIT, s2.encoding)

      assert(s1 != s2)
    end

    def test_parse
      entry_description = @entry.to_s
      pp entry_description if $DEBUG
      parsed_entry = RIMS::Password::HashSource.parse_entry(entry_description)
      assert_equal(@entry.hash_type, parsed_entry.hash_type)
      assert_equal(@entry.salt, parsed_entry.salt)
      assert_equal(@entry.salt_base64, parsed_entry.salt_base64)
      assert_equal(@entry.hash, parsed_entry.hash)

      assert_raise(LoadError) { RIMS::Password::HashSource.parse_entry('NoDigest:') }
      assert_raise(TypeError) { RIMS::Password::HashSource.parse_entry('Object:') }
    end

    def test_compare
      assert(@entry.compare(@password))
      assert(! @entry.compare(@password.succ))
    end
  end

  class PasswordHashSourceTest < Test::Unit::TestCase
    def setup
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL

      @username = 'foo'
      @password = 'open_sesame'

      @digest_factory = Digest::SHA256
      @hash_type = 'SHA256'
      @strech_count = 1000
      @salt = "\332\322\046\267\211\013\250\263".b
      @entry = RIMS::Password::HashSource.make_entry(@digest_factory, @strech_count, @salt, @password)

      @src = RIMS::Password::HashSource.new
      @src.add(@username, @entry)
      @src.logger = @logger
      @src.start
    end

    def teardown
      @src.stop
    end

    def test_raw_password?
      assert_equal(false, @src.raw_password?)
    end

    def test_user?
      assert_equal(true, (@src.user? @username))
      assert_equal(false, (@src.user? @username.succ))
    end

    def test_fetch_password
      assert_nil(@src.fetch_password(@username))
      assert_nil(@src.fetch_password(@username.succ))
    end

    def test_compare_password
      assert(@src.compare_password(@username, @password))
      assert(! @src.compare_password(@username, @password.succ))
      assert(! @src.compare_password(@username.succ, @password))
    end

    def test_build_from_conf
      @src.stop

      config = [
        { 'user' => @username, 'hash' => @entry.to_s }
      ]
      @src = RIMS::Password::HashSource.build_from_conf(config)
      @src.logger = @logger
      @src.start

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
