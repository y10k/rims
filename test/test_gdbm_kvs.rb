# -*- coding: utf-8 -*-

require 'fileutils'
require 'gdbm'
require 'rims'
require 'test/unit'

module RIMS::Test
  class GDBM_KeyValueStoreTest < Test::Unit::TestCase
    def setup
      @name = "kvs_test.gdbm.#{$$}"
      @db = GDBM.new(@name)
      @kvs = RIMS::GDBM_KeyValueStore.new(@db, @name)
    end

    def teardown
      @db.close unless @db.closed?
      FileUtils.rm_f(@name)
    end

    def test_store_fetch
      assert_nil(@db['foo'])
      assert_nil(@kvs['foo'])

      assert_equal('apple', (@kvs['foo'] = 'apple'))

      assert_equal('apple', @db['foo'])
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
      assert_equal(%w[ foo bar ].sort, @db.each_key.sort)
      assert_equal(%w[ foo bar ].sort, @kvs.each_key.sort)
      assert_equal(%w[ apple banana ].sort, @kvs.each_value.sort)
      assert_equal([ %w[ foo apple ], %w[ bar banana ] ].sort, @kvs.each_pair.sort)

      @kvs['baz'] = 'orange'
      assert_equal(%w[ foo bar baz ].sort, @db.each_key.sort)
      assert_equal(%w[ foo bar baz ].sort, @kvs.each_key.sort)
      assert_equal(%w[ apple banana orange ].sort, @kvs.each_value.sort)
      assert_equal([ %w[ foo apple ], %w[ bar banana ], %w[ baz orange ] ].sort, @kvs.each_pair.sort)

      @kvs.delete('bar')
      assert_equal(%w[ foo baz ].sort, @db.each_key.sort)
      assert_equal(%w[ foo baz ].sort, @kvs.each_key.sort)
      assert_equal(%w[ apple orange ].sort, @kvs.each_value.sort)
      assert_equal([ %w[ foo apple ], %w[ baz orange ] ].sort, @kvs.each_pair.sort)
    end

    def test_sync
      @kvs.sync
    end

    def test_close
      @kvs.close
      assert_equal(true, @db.closed?)

      # closed exception
      assert_raise(RuntimeError) { @kvs['foo'] }
      assert_raise(RuntimeError) { @kvs['foo'] = 'apple' }
      assert_raise(RuntimeError) { @kvs.delete('foo') }
      assert_raise(RuntimeError) { @kvs.key? 'foo' }
      assert_raise(RuntimeError) { @kvs.each_key.to_a }
      assert_raise(RuntimeError) { @kvs.each_value.to_a }
      assert_raise(RuntimeError) { @kvs.each_pair.to_a }
    end

    def test_destroy
      assert_raise(RuntimeError) { @kvs.destroy }
      assert_equal(true, (File.exist? @name))

      @kvs.close
      @kvs.destroy
      assert_equal(false, (File.exist? @name))
    end
  end

  class GDBM_KeyValueStoreOpenCloseTest < Test::Unit::TestCase
    def setup
      @base_dir = 'gdbm_test_dir'
      @name = File.join(@base_dir, 'test_kvs')
      FileUtils.mkdir_p(@base_dir)
    end

    def teardown
      FileUtils.rm_rf(@base_dir)
    end

    def test_open_close
      assert_equal(false, (RIMS::GDBM_KeyValueStore.exist? @name))

      kvs = RIMS::GDBM_KeyValueStore.open(@name)
      begin
        assert_equal(true, (RIMS::GDBM_KeyValueStore.exist? @name))
      ensure
        kvs.close
      end
      assert_equal(true, (RIMS::GDBM_KeyValueStore.exist? @name))

      kvs.destroy
      assert_equal(false, (RIMS::GDBM_KeyValueStore.exist? @name))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
