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

    def test_msg
      cnum = @mail_store.cnum
      mbox_id = @mail_store.add_mbox('INBOX')
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      msg_id = @mail_store.add_msg(mbox_id, 'foo')
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal([ msg_id ], @mail_store.each_msg_id(mbox_id).to_a)

      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flags(mbox_id, 'recent'))

      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'draft'))
      assert_equal(true, @mail_store.msg_flag(mbox_id, msg_id, 'recent'))

      @mail_store.set_msg_flag(mbox_id, msg_id, 'seen', true)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum

      assert_equal(1, @mail_store.mbox_flags(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flags(mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'draft'))
      assert_equal(true, @mail_store.msg_flag(mbox_id, msg_id, 'recent'))

      @mail_store.set_msg_flag(mbox_id, msg_id, 'recent', false)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum

      assert_equal(1, @mail_store.mbox_flags(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'draft'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'recent'))

      @mail_store.set_msg_flag(mbox_id, msg_id, 'deleted', true)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum

      assert_equal(1, @mail_store.mbox_flags(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'flagged'))
      assert_equal(1, @mail_store.mbox_flags(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'flagged'))
      assert_equal(true, @mail_store.msg_flag(mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'draft'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, msg_id, 'recent'))

      @mail_store.expunge_mbox(mbox_id)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal([], @mail_store.each_msg_id(mbox_id).to_a)

      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'recent'))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
