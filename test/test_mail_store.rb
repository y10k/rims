# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'
require 'time'

module RIMS::Test
  class MailStoreTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @kvs_open = proc{|path|
        kvs = {}
        def kvs.close
          self
        end
        RIMS::GDBM_KeyValueStore.new(@kv_store[path] = kvs)
      }
      @mail_store = RIMS::MailStore.new(@kvs_open, @kvs_open)
      @mail_store.open
    end

    def teardown
      @mail_store.close if @mail_store
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
      assert_nil(@mail_store.mbox_name(1))
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
      assert(! (@mail_store.msg_exist? mbox_id, 1))
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      msg_id = @mail_store.add_msg(mbox_id, 'foo', Time.parse('1975-11-19 12:34:56'))
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal(1, @mail_store.mbox_msgs(mbox_id))
      assert((@mail_store.msg_exist? mbox_id, 1))
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

      # duplicated message copy
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

      # duplicated flag settings
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

      # duplicated
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

    def test_mail_folder
      mbox_id = @mail_store.add_mbox('INBOX')
      folder = @mail_store.select_mbox(mbox_id)
      assert_equal(mbox_id, folder.id)
      assert_equal(false, folder.updated?)
      assert_equal([], folder.msg_list)

      @mail_store.add_msg(mbox_id, 'foo')
      assert_equal(true, folder.updated?)
      folder.reload
      assert_equal(false, folder.updated?)
      assert_equal([ [ 1, 1 ] ], folder.msg_list.map{|i| i.to_a })
    end

    def each_msg_src
      return enum_for(:each_msg_src) unless block_given?
      s = 'a'
      loop do
        yield(s)
        s.succ!
      end
    end
    private :each_msg_src

    def test_mail_folder_parse_msg_set
      mbox_id = @mail_store.add_mbox('INBOX')

      msg_src = each_msg_src
      100.times do
        @mail_store.add_msg(mbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(mbox_id) do |id|
        if (id % 2 == 0) then
          @mail_store.set_msg_flag(mbox_id, id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(mbox_id)

      folder = @mail_store.select_mbox(mbox_id)

      assert_equal([ 1 ].to_set, folder.parse_msg_set('1'))
      assert_equal([ 1 ].to_set, folder.parse_msg_set('1', uid: false))
      assert_equal([ 1 ].to_set, folder.parse_msg_set('1', uid: true))

      assert_equal([ 2 ].to_set, folder.parse_msg_set('2'))
      assert_equal([ 2 ].to_set, folder.parse_msg_set('2', uid: false))
      assert_equal([ 2 ].to_set, folder.parse_msg_set('2', uid: true))

      assert_equal([ 50 ].to_set, folder.parse_msg_set('*'))
      assert_equal([ 50 ].to_set, folder.parse_msg_set('*', uid: false))
      assert_equal([ 99 ].to_set, folder.parse_msg_set('*', uid: true))

      assert_equal((1..50).to_set, folder.parse_msg_set('1:*'))
      assert_equal((1..50).to_set, folder.parse_msg_set('1:*', uid: false))
      assert_equal((1..99).to_set, folder.parse_msg_set('1:*', uid: true))

      assert_raise(RIMS::MessageSetSyntaxError) {
        folder.parse_msg_set('detarame')
      }
    end

    def test_mail_folder_parse_msg_set_empty
      mbox_id = @mail_store.add_mbox('INBOX')
      assert_equal([], @mail_store.each_msg_id(mbox_id).to_a)
      folder = @mail_store.select_mbox(mbox_id)

      assert_equal([].to_set, folder.parse_msg_set('1'))
      assert_equal([].to_set, folder.parse_msg_set('1', uid: false))
      assert_equal([].to_set, folder.parse_msg_set('1', uid: true))

      assert_equal([].to_set, folder.parse_msg_set('*'))
      assert_equal([].to_set, folder.parse_msg_set('*', uid: false))
      assert_equal([].to_set, folder.parse_msg_set('*', uid: true))

      assert_equal([].to_set, folder.parse_msg_set('1:*'))
      assert_equal([].to_set, folder.parse_msg_set('1:*', uid: false))
      assert_equal([].to_set, folder.parse_msg_set('1:*', uid: true))
    end
  end

  class MailFolderClassMethodTest < Test::Unit::TestCase
    def test_parse_msg_seq
      assert_equal(1..1, RIMS::MailFolder.parse_msg_seq('1', 99))
      assert_equal(99..99, RIMS::MailFolder.parse_msg_seq('*', 99))
      assert_equal(1..10, RIMS::MailFolder.parse_msg_seq('1:10', 99))
      assert_equal(1..99, RIMS::MailFolder.parse_msg_seq('1:*', 99))
      assert_equal(99..99, RIMS::MailFolder.parse_msg_seq('*:*', 99))
      assert_raise(RIMS::MessageSetSyntaxError) {
        RIMS::MailFolder.parse_msg_seq('detarame', 99)
      }
    end

    def test_parse_msg_set
      assert_equal([ 1 ].to_set, RIMS::MailFolder.parse_msg_set('1', 99))
      assert_equal([ 99 ].to_set, RIMS::MailFolder.parse_msg_set('*', 99))
      assert_equal((1..10).to_set, RIMS::MailFolder.parse_msg_set('1:10', 99))
      assert_equal((1..99).to_set, RIMS::MailFolder.parse_msg_set('1:*', 99))
      assert_equal((99..99).to_set, RIMS::MailFolder.parse_msg_set('*:*', 99))

      assert_equal([ 1, 5, 7, 99 ].to_set, RIMS::MailFolder.parse_msg_set('1,5,7,*', 99))
      assert_equal([ 1, 2, 3, 11, 97, 98, 99 ].to_set, RIMS::MailFolder.parse_msg_set('1:3,11,97:*', 99))
      assert_equal((1..99).to_set, RIMS::MailFolder.parse_msg_set('1:70,30:*', 99))

      assert_raise(RIMS::MessageSetSyntaxError) {
        RIMS::MailFolder.parse_msg_set('detarame', 99)
      }
      assert_raise(RIMS::MessageSetSyntaxError) {
        RIMS::MailFolder.parse_msg_set('1,2,X', 99)
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
