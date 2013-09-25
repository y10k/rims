# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'
require 'time'

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
      assert_equal({ 'foo/global.db' => { 'cnum' => '0', 'uid' => '1', 'uidvalidity' => '1' },
                     'foo/message.db' => {}
                   }, @kv_store)
    end

    def test_mbox
      assert_equal(0, @mail_store.cnum)
      assert_equal(1, @mail_store.uidvalidity)
      assert_equal([], @mail_store.each_mbox_id.to_a)

      assert_equal(1, @mail_store.add_mbox('INBOX'))
      assert_equal(1, @mail_store.cnum)
      assert_equal(2, @mail_store.uidvalidity)
      assert_equal('INBOX', @mail_store.mbox_name(1))
      assert_equal(1, @mail_store.mbox_id('INBOX'))
      assert_equal([ 1 ], @mail_store.each_mbox_id.to_a)

      assert_equal('INBOX', @mail_store.del_mbox(1))
      assert_equal(2, @mail_store.cnum)
      assert_equal(2, @mail_store.uidvalidity)
      assert_nil(@mail_store.mbox_name(0))
      assert_nil(@mail_store.mbox_id('INBOX'))
      assert_equal([], @mail_store.each_mbox_id.to_a)

      assert_equal(2, @mail_store.add_mbox('INBOX'))
      assert_equal(3, @mail_store.cnum)
      assert_equal(3, @mail_store.uidvalidity)
      assert_equal('INBOX', @mail_store.mbox_name(2))
      assert_equal(2, @mail_store.mbox_id('INBOX'))
      assert_equal([ 2 ], @mail_store.each_mbox_id.to_a)
    end

    def test_msg
      cnum = @mail_store.cnum
      mbox_id = @mail_store.add_mbox('INBOX')
      assert_equal(0, @mail_store.mbox_msgs(mbox_id))
      assert_equal([], @mail_store.each_msg_id(mbox_id).to_a)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      msg_id = @mail_store.add_msg(mbox_id, 'foo', Time.parse('1975-11-19 12:34:56'))
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal(1, @mail_store.mbox_msgs(mbox_id))
      assert_equal([ msg_id ], @mail_store.each_msg_id(mbox_id).to_a)

      assert_equal('foo', @mail_store.msg_text(mbox_id, msg_id))
      assert_equal(Time.parse('1975-11-19 12:34:56'), @mail_store.msg_date(mbox_id, msg_id))

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

      copy_mbox_id = @mail_store.add_mbox('copy_test')
      assert_equal(0, @mail_store.mbox_msgs(copy_mbox_id))
      assert_equal([], @mail_store.each_msg_id(copy_mbox_id).to_a)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      @mail_store.copy_msg(msg_id, copy_mbox_id)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal(1, @mail_store.mbox_msgs(copy_mbox_id))
      assert_equal([ msg_id ], @mail_store.each_msg_id(copy_mbox_id).to_a)

      assert_equal('foo', @mail_store.msg_text(copy_mbox_id, msg_id))
      assert_equal(Time.parse('1975-11-19 12:34:56'), @mail_store.msg_date(copy_mbox_id, msg_id))

      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flags(copy_mbox_id, 'recent'))

      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'draft'))
      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, msg_id, 'recent'))

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

      assert_equal(1, @mail_store.mbox_flags(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flags(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'draft'))
      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, msg_id, 'recent'))

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

      assert_equal(1, @mail_store.mbox_flags(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'draft'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'recent'))

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

      assert_equal(1, @mail_store.mbox_flags(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'draft'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'recent'))

      @mail_store.expunge_mbox(mbox_id)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal(0, @mail_store.mbox_msgs(mbox_id))
      assert_equal([], @mail_store.each_msg_id(mbox_id).to_a)

      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(mbox_id, 'recent'))

      assert_equal(1, @mail_store.mbox_msgs(copy_mbox_id))
      assert_equal([ msg_id ], @mail_store.each_msg_id(copy_mbox_id).to_a)

      assert_equal(1, @mail_store.mbox_flags(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, msg_id, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'draft'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, msg_id, 'recent'))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
