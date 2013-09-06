# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class GlobalDBTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @g_db = RIMS::GlobalDB.new(@kv_store)
    end

    def test_setup
      @g_db.setup
      assert_equal({ 'cnum' => '0', 'uid' => '0', 'uidvalidity' => '0' }, @kv_store)
    end

    def test_uid
      @g_db.setup
      assert_equal(0, @g_db.cnum)
      @g_db.cnum = 1
      assert_equal(1, @g_db.cnum)
      assert_equal('1', @kv_store['cnum'])
    end

    def test_uid
      @g_db.setup
      assert_equal(0, @g_db.uid)
      @g_db.uid = 1
      assert_equal(1, @g_db.uid)
      assert_equal('1', @kv_store['uid'])
    end

    def test_uidvalidity
      @g_db.setup
      assert_equal(0, @g_db.uidvalidity)
      @g_db.uidvalidity = 1
      assert_equal(1, @g_db.uidvalidity)
      assert_equal('1', @kv_store['uidvalidity'])
    end

    def test_mbox
      @g_db.add_mbox(0, 'INBOX')
      assert_equal('INBOX', @kv_store['mbox_id-0'])
      assert_equal('0', @kv_store['mbox_name-INBOX'])
      assert_equal('INBOX', @g_db.mbox_name(0))
      assert_equal(0, @g_db.mbox_id('INBOX'))
      assert_equal([ 0 ], @g_db.each_mbox_id.to_a)

      @g_db.del_mbox(0)
      assert(! (@kv_store.key? 'mbox_id-0'))
      assert(! (@kv_store.key? 'mbox_name-INBOX'))
      assert_nil(@g_db.mbox_name(0))
      assert_nil(@g_db.mbox_id('INBOX'))
      assert_equal([], @g_db.each_mbox_id.to_a)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
