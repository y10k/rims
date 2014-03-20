# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class Checksum_KeyValueStoreTest < Test::Unit::TestCase
    def setup
      @db = {}
      @builder = RIMS::KeyValueStore::FactoryBuilder.new
      @builder.open{|name| RIMS::Hash_KeyValueStore.new(@db) }
      @builder.use(RIMS::Checksum_KeyValueStore)
      @kvs = @builder.factory.call('test')
    end

    def teardown
      pp @db if $DEBUG
    end

    def test_store_fetch
      assert_nil(@db['foo'])
      assert_nil(@kvs['foo'])

      assert_equal('apple', (@kvs['foo'] = 'apple'))

      assert_not_nil('apple', @db['foo'])
      assert_equal('apple', @kvs['foo'])
    end

    def test_delete
      assert_nil(@kvs.delete('foo'))

      @kvs['foo'] = 'apple'
      assert_equal('apple', @kvs.delete('foo'))

      assert_nil(@db['foo'])
      assert_nil(@kvs['foo'])
    end

    def test_key?
      assert_equal(false, (@db.key? 'foo'))
      assert_equal(false, (@kvs.key? 'foo'))

      @kvs['foo'] = 'apple'
      assert_equal(true, (@db.key? 'foo'))
      assert_equal(true, (@kvs.key? 'foo'))

      @kvs.delete('foo')
      assert_equal(false, (@db.key? 'foo'))
      assert_equal(false, (@kvs.key? 'foo'))
    end

    def test_each_key
      assert_equal(%w[], @db.each_key.to_a)
      assert_equal(%w[], @kvs.each_key.to_a)

      @kvs['foo'] = 'apple'
      assert_equal(%w[ foo ], @db.each_key.to_a)
      assert_equal(%w[ foo ], @kvs.each_key.to_a)
      assert_equal(%w[ apple ], @kvs.each_value.to_a)
      assert_equal([ %w[ foo apple ] ], @kvs.each_pair.to_a)

      @kvs['bar'] = 'banana'
      assert_equal(%w[ foo bar ], @db.each_key.to_a)
      assert_equal(%w[ foo bar ], @kvs.each_key.to_a)
      assert_equal(%w[ apple banana ], @kvs.each_value.to_a)
      assert_equal([ %w[ foo apple ], %w[ bar banana ] ], @kvs.each_pair.to_a)

      @kvs['baz'] = 'orange'
      assert_equal(%w[ foo bar baz ], @db.each_key.to_a)
      assert_equal(%w[ foo bar baz ], @kvs.each_key.to_a)
      assert_equal(%w[ apple banana orange ], @kvs.each_value.to_a)
      assert_equal([ %w[ foo apple ], %w[ bar banana ], %w[ baz orange ] ], @kvs.each_pair.to_a)

      @kvs.delete('bar')
      assert_equal(%w[ foo baz ], @db.each_key.to_a)
      assert_equal(%w[ foo baz ], @kvs.each_key.to_a)
      assert_equal(%w[ apple orange ], @kvs.each_value.to_a)
      assert_equal([ %w[ foo apple ], %w[ baz orange ] ], @kvs.each_pair.to_a)
    end

    def test_sync
      @kvs.sync
    end

    def test_close
      @kvs.close

      # nil exception
      assert_raise(NoMethodError) { @kvs['foo'] }
      assert_raise(NoMethodError) { @kvs['foo'] = 'apple' }
      assert_raise(NoMethodError) { @kvs.delete('foo') }
      assert_raise(NoMethodError) { @kvs.key? 'foo' }
      assert_raise(NoMethodError) { @kvs.each_key.to_a }
      assert_raise(NoMethodError) { @kvs.each_value.to_a }
      assert_raise(NoMethodError) { @kvs.each_pair.to_a }
    end

    def test_destroy
      @kvs.destroy
    end

    def test_checksum_error
      @kvs['foo'] = 'Hello world.'
      assert_equal('Hello world.', @kvs['foo'])

      s = @db['foo']
      @db['foo'] = s.chop
      assert_raise(RuntimeError) { @kvs['foo'] }

      @db['foo'] = 'Hello world.'
      assert_raise(RuntimeError) { @kvs['foo'] }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
