# -*- coding: utf-8 -*-

require 'digest'
require 'pp' if $DEBUG
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

    def teardown
      pp @kv_store if $DEBUG
    end

    def test_cnum
      @g_db.setup
      assert_equal(0, @g_db.cnum)
      @g_db.cnum = 1
      assert_equal(1, @g_db.cnum)
    end

    def test_uidvalidity
      @g_db.setup
      assert_equal(1, @g_db.uidvalidity)
      @g_db.uidvalidity = 2
      assert_equal(2, @g_db.uidvalidity)
    end

    def test_mbox
      @g_db.setup

      @g_db.add_mbox(0, 'INBOX')
      assert_equal('INBOX', @g_db.mbox_name(0))
      assert_equal(0, @g_db.mbox_id('INBOX'))
      assert_equal([ 0 ], @g_db.each_mbox_id.to_a)

      pp @kv_store if $DEBUG

      @g_db.del_mbox(0)
      assert_nil(@g_db.mbox_name(0))
      assert_nil(@g_db.mbox_id('INBOX'))
      assert_equal([], @g_db.each_mbox_id.to_a)
    end
  end

  class MessageDBTest < Test::Unit::TestCase
    def setup
      @text_st = {}
      @attr_st = {}
      @msg_db = RIMS::MessageDB.new(RIMS::GDBM_KeyValueStore.new(@text_st),
                                    RIMS::GDBM_KeyValueStore.new(@attr_st)).setup
    end

    def teardown
      pp @text_st, @attr_st if $DEBUG
    end

    def test_msg
      t0 = Time.now
      id = @msg_db.add_msg('foo')
      assert_kind_of(Integer, id)
      assert_equal('foo', @msg_db.msg_text(id))
      assert(@msg_db.msg_date(id) >= t0)
      assert_equal('sha256:' + Digest::SHA256.hexdigest('foo'), @msg_db.msg_cksum(id))
      assert_equal([ id ], @msg_db.each_msg_id.to_a)

      pp @text_st, @attr_st if $DEBUG

      assert_equal(false, @msg_db.msg_flag(id, 'seen'))
      assert(@msg_db.set_msg_flag(id, 'seen', true)) # changed.
      assert_equal(true, @msg_db.msg_flag(id, 'seen'))
      assert(! @msg_db.set_msg_flag(id, 'seen', true)) # not changed.
      assert_equal(true, @msg_db.msg_flag(id, 'seen'))
      assert(@msg_db.set_msg_flag(id, 'seen', false)) # changed.
      assert_equal(false, @msg_db.msg_flag(id, 'seen'))
      assert(! @msg_db.set_msg_flag(id, 'seen', false)) # not changed.
      assert_equal(false, @msg_db.msg_flag(id, 'seen'))

      pp @text_st, @attr_st if $DEBUG

      assert_equal([].to_set, @msg_db.msg_mboxes(id))
      assert(@msg_db.add_msg_mbox(id, 0))   # changed.
      assert_equal([ 0 ].to_set, @msg_db.msg_mboxes(id))
      assert(! @msg_db.add_msg_mbox(id, 0)) # not changed.
      assert_equal([ 0 ].to_set, @msg_db.msg_mboxes(id))
      assert(@msg_db.add_msg_mbox(id, 1))   # changed.
      assert_equal([ 0, 1 ].to_set, @msg_db.msg_mboxes(id))
      assert(! @msg_db.add_msg_mbox(id, 1)) # not changed.
      assert_equal([ 0, 1 ].to_set, @msg_db.msg_mboxes(id))
      assert(@msg_db.del_msg_mbox(id, 0))   # changed.
      assert_equal([ 1 ].to_set, @msg_db.msg_mboxes(id))
      assert(! @msg_db.del_msg_mbox(id, 0)) # not changed.
      assert_equal([ 1 ].to_set, @msg_db.msg_mboxes(id))

      pp @text_st, @attr_st if $DEBUG

      id2 = @msg_db.add_msg('bar', Time.parse('1975-11-19 12:34:56'))
      assert_kind_of(Integer, id2)
      assert(id2 > id)
      assert_equal('bar', @msg_db.msg_text(id2))
      assert_equal(Time.parse('1975-11-19 12:34:56'), @msg_db.msg_date(id2))
      assert_equal([ id, id2 ], @msg_db.each_msg_id.to_a)
    end
  end

  class MailboxDBTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @mbox_db = RIMS::MailboxDB.new(RIMS::GDBM_KeyValueStore.new(@kv_store)).setup
    end

    def teardown
      pp @kv_store if $DEBUG
    end

    def test_attributes
      @mbox_db.mbox_id = 0
      assert_equal(0, @mbox_db.mbox_id)

      @mbox_db.mbox_name = 'INBOX'
      assert_equal('INBOX', @mbox_db.mbox_name)
    end

    def test_counter
      assert_equal(0, @mbox_db.msgs)
      @mbox_db.msgs_increment
      assert_equal(1, @mbox_db.msgs)
      @mbox_db.msgs_decrement
      assert_equal(0, @mbox_db.msgs)

      for n in %w[ seen answered flagged deleted draft recent ]
        assert_equal(0, @mbox_db.flags(n), "flag_#{n}")
        @mbox_db.flags_increment(n)
        assert_equal(1, @mbox_db.flags(n), "flag_#{n}")
        @mbox_db.flags_decrement(n)
        assert_equal(0, @mbox_db.flags(n), "flag_#{n}")
      end
    end

    def test_msg
      @mbox_db.add_msg(0)
      assert_equal([ 0 ], @mbox_db.each_msg_id.to_a)
      assert_equal(false, @mbox_db.msg_flag_del(0))
      assert(@mbox_db.set_msg_flag_del(0, true)) # changed.
      assert_equal(true, @mbox_db.msg_flag_del(0))
      assert(! @mbox_db.set_msg_flag_del(0, true)) # not changed.
      assert_equal(true, @mbox_db.msg_flag_del(0))
      @mbox_db.expunge_msg(0)
      assert_equal([], @mbox_db.each_msg_id.to_a)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
