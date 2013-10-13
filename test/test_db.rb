# -*- coding: utf-8 -*-

require 'digest'
require 'rims'
require 'set'
require 'test/unit'
require 'time'

module RIMS::Test
  class GlobalDBTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @g_db = RIMS::GlobalDB.new(RIMS::GDBM_KeyValueStore.new(@kv_store))
    end

    def test_setup
      @g_db.setup
      assert_equal({ 'cnum' => '0', 'uid' => '1', 'uidvalidity' => '1' }, @kv_store)
    end

    def test_cnum
      @g_db.setup
      assert_equal(0, @g_db.cnum)
      @g_db.cnum = 1
      assert_equal(1, @g_db.cnum)
      assert_equal('1', @kv_store['cnum'])
    end

    def test_uid
      @g_db.setup
      assert_equal(1, @g_db.uid)
      @g_db.uid = 2
      assert_equal(2, @g_db.uid)
      assert_equal('2', @kv_store['uid'])
    end

    def test_uidvalidity
      @g_db.setup
      assert_equal(1, @g_db.uidvalidity)
      @g_db.uidvalidity = 2
      assert_equal(2, @g_db.uidvalidity)
      assert_equal('2', @kv_store['uidvalidity'])
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

  class MessageDBTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @msg_db = RIMS::MessageDB.new(RIMS::GDBM_KeyValueStore.new(@kv_store))
    end

    def test_msg
      t0 = Time.now
      @msg_db.add_msg(0, 'foo')
      assert_equal('foo', @kv_store['text-0'])
      assert(@kv_store.key? 'date-0')
      assert_equal('sha256:' + Digest::SHA256.hexdigest('foo'), @kv_store['cksum-0'])
      assert_equal('foo', @msg_db.msg_text(0))
      assert(@msg_db.msg_date(0) >= t0)
      assert_equal('sha256:' + Digest::SHA256.hexdigest('foo'), @msg_db.msg_cksum(0))
      assert_equal([ 0 ], @msg_db.each_msg_id.to_a)

      assert(@msg_db.set_msg_flag(0, 'seen', true)) # changed.
      assert_equal(true, @msg_db.msg_flag(0, 'seen'))
      assert(! @msg_db.set_msg_flag(0, 'seen', true)) # not changed.
      assert_equal(true, @msg_db.msg_flag(0, 'seen'))
      assert(@msg_db.set_msg_flag(0, 'seen', false)) # changed.
      assert_equal(false, @msg_db.msg_flag(0, 'seen'))
      assert(! @msg_db.set_msg_flag(0, 'seen', false)) # not changed.
      assert_equal(false, @msg_db.msg_flag(0, 'seen'))

      assert_equal([].to_set, @msg_db.msg_mboxes(0))
      @msg_db.add_msg_mbox(0, 0)
      assert_equal([ 0 ].to_set, @msg_db.msg_mboxes(0))
      @msg_db.add_msg_mbox(0, 1)
      assert_equal([ 0, 1 ].to_set, @msg_db.msg_mboxes(0))
      @msg_db.del_msg_mbox(0, 0)
      assert_equal([ 1 ].to_set, @msg_db.msg_mboxes(0))

      @msg_db.add_msg(1, 'bar', Time.parse('1975-11-19 12:34:56'))
      assert_equal('bar', @msg_db.msg_text(1))
      assert_equal(Time.parse('1975-11-19 12:34:56'), @msg_db.msg_date(1))
      assert_equal([ 0, 1 ], @msg_db.each_msg_id.to_a)
    end
  end

  class MailboxDBTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @mbox_db = RIMS::MailboxDB.new(RIMS::GDBM_KeyValueStore.new(@kv_store)).setup
    end

    def test_attributes
      @mbox_db.mbox_id = 0
      assert_equal(0, @mbox_db.mbox_id)
      assert_equal('0', @kv_store['mbox_id'])

      @mbox_db.mbox_name = 'INBOX'
      assert_equal('INBOX', @mbox_db.mbox_name)
      assert_equal('INBOX', @kv_store['mbox_name'])
    end

    def test_counter
      assert_equal(0, @mbox_db.msgs)
      @mbox_db.msgs_increment
      assert_equal(1, @mbox_db.msgs)
      assert_equal('1', @kv_store['msg_count'])
      @mbox_db.msgs_decrement
      assert_equal(0, @mbox_db.msgs)
      assert_equal('0', @kv_store['msg_count'])

      for n in %w[ seen answered flagged deleted draft recent ]
        assert_equal(0, @mbox_db.flags(n), "flag_#{n}")
        @mbox_db.flags_increment(n)
        assert_equal(1, @mbox_db.flags(n), "flag_#{n}")
        assert_equal('1', @kv_store["flags_#{n}"])
        @mbox_db.flags_decrement(n)
        assert_equal(0, @mbox_db.flags(n), "flag_#{n}")
        assert_equal('0', @kv_store["flags_#{n}"])
      end
    end

    def test_msg
      # these flags should be updated by RIMS::MailStore.
      flags_kv = {
        'flags_answered' => '0',
        'flags_flagged' => '0',
        'flags_deleted' => '0',
        'flags_seen' => '0',
        'flags_draft' => '0',
        'flags_recent' => '0'
      }

      @mbox_db.add_msg(0)
      assert_equal([ 0 ], @mbox_db.each_msg_id.to_a)
      assert_equal(false, @mbox_db.msg_flag_del(0))
      assert_equal({ 'msg_count' => '1', 'msg-0' => '' }.merge(flags_kv), @kv_store)
      assert(@mbox_db.set_msg_flag_del(0, true)) # changed.
      assert_equal(true, @mbox_db.msg_flag_del(0))
      assert_equal({ 'msg_count' => '1', 'msg-0' => 'deleted' }.merge(flags_kv), @kv_store)
      assert(! @mbox_db.set_msg_flag_del(0, true)) # not changed.
      assert_equal(true, @mbox_db.msg_flag_del(0))
      assert_equal({ 'msg_count' => '1', 'msg-0' => 'deleted' }.merge(flags_kv), @kv_store)
      @mbox_db.expunge_msg(0)
      assert_equal([], @mbox_db.each_msg_id.to_a)
      assert_equal({ 'msg_count' => '0' }.merge(flags_kv), @kv_store)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
