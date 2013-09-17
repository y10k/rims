# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class MailStoreTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @mail_store = RIMS::MailStore.new('foo') {|path|
        kvs = {}
        def kvs.close
          self
        end
        RIMS::GDBM_KeyValueStore.new(@kv_store[path] = kvs)
      }
      @mail_store.open
    end

    def teardown
      @mail_store.close
    end

    def test_open
      assert_equal({ 'foo/global.db' => {}, 'foo/message.db' => {} }, @kv_store)
    end

    def test_mbox
      assert_equal(0, @mail_store.cnum)
      assert_equal(0, @mail_store.uidvalidity)
      assert_equal([], @mail_store.each_mbox_id.to_a)

      assert_equal(0, @mail_store.add_mbox('INBOX'))
      assert_equal(1, @mail_store.cnum)
      assert_equal(1, @mail_store.uidvalidity)
      assert_equal([ 0 ], @mail_store.each_mbox_id.to_a)

      assert_equal('INBOX', @mail_store.del_mbox(0))
      assert_equal(2, @mail_store.cnum)
      assert_equal(1, @mail_store.uidvalidity)
      assert_equal([], @mail_store.each_mbox_id.to_a)

      assert_equal(1, @mail_store.add_mbox('INBOX'))
      assert_equal(3, @mail_store.cnum)
      assert_equal(2, @mail_store.uidvalidity)
      assert_equal([ 1 ], @mail_store.each_mbox_id.to_a)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
