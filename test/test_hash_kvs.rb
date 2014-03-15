# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class Hash_KeyValueStoreTest < Test::Unit::TestCase
    def setup
      @db = {}
      @kvs = RIMS::Hash_KeyValueStore.new(@db)
    end

    def teardown
      pp @db if $DEBUG
    end

    def test_store_fetch
      assert_nil(@db['foo'])
      assert_nil(@kvs['foo'])

      assert_equal('apple', (@kvs['foo'] = 'apple'))
      assert_equal({ 'foo' => 'apple' }, @db)

      assert_equal('apple', @db['foo'])
      assert_equal('apple', @kvs['foo'])
    end

    def test_delete
      assert_nil(@kvs.delete('foo'))

      @kvs['foo'] = 'apple'
      assert_equal({ 'foo' => 'apple' }, @db)
      assert_equal('apple', @kvs.delete('foo'))
      assert_equal({}, @db)

      assert_nil(@db['foo'])
      assert_nil(@kvs['foo'])
    end

    def test_key?
      assert_equal(false, (@db.key? 'foo'))
      assert_equal(false, (@kvs.key? 'foo'))

      @kvs['foo'] = 'apple'
      assert_equal({ 'foo' => 'apple' }, @db)
      assert_equal(true, (@db.key? 'foo'))
      assert_equal(true, (@kvs.key? 'foo'))

      @kvs.delete('foo')
      assert_equal({}, @db)
      assert_equal(false, (@db.key? 'foo'))
      assert_equal(false, (@kvs.key? 'foo'))
    end

    def test_each_key
      assert_equal(%w[], @db.each_key.to_a)
      assert_equal(%w[], @kvs.each_key.to_a)

      @kvs['foo'] = 'apple'
      assert_equal({ 'foo' => 'apple' }, @db)
      assert_equal(%w[ foo ], @db.each_key.to_a)
      assert_equal(%w[ foo ], @kvs.each_key.to_a)
      assert_equal(%w[ apple ], @kvs.each_value.to_a)
      assert_equal([ %w[ foo apple ] ], @kvs.each_pair.to_a)

      @kvs['bar'] = 'banana'
      assert_equal({ 'foo' => 'apple', 'bar' => 'banana' }, @db)
      assert_equal(%w[ foo bar ], @db.each_key.to_a)
      assert_equal(%w[ foo bar ], @kvs.each_key.to_a)
      assert_equal(%w[ apple banana ], @kvs.each_value.to_a)
      assert_equal([ %w[ foo apple ], %w[ bar banana ] ], @kvs.each_pair.to_a)

      @kvs['baz'] = 'orange'
      assert_equal({ 'foo' => 'apple', 'bar' => 'banana', 'baz' => 'orange' }, @db)
      assert_equal(%w[ foo bar baz ], @db.each_key.to_a)
      assert_equal(%w[ foo bar baz ], @kvs.each_key.to_a)
      assert_equal(%w[ apple banana orange ], @kvs.each_value.to_a)
      assert_equal([ %w[ foo apple ], %w[ bar banana ], %w[ baz orange ] ], @kvs.each_pair.to_a)

      @kvs.delete('bar')
      assert_equal({ 'foo' => 'apple', 'baz' => 'orange' }, @db)
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
      assert_equal({}, @db)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
