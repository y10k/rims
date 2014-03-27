# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'rims'
require 'test/unit'
require 'time'

module RIMS::Test
  class MailStoreTest < Test::Unit::TestCase
    def setup
      @kvs = Hash.new{|h, k| h[k] = Hash.new }
      @kvs_open = proc{|name| RIMS::Hash_KeyValueStore.new(@kvs[name]) }
      @mail_store = RIMS::MailStore.new(RIMS::DB::Meta.new(@kvs_open.call('meta')),
                                        RIMS::DB::Message.new(@kvs_open.call('msg'))) {|mbox_id|
        RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
    end

    def teardown
      @mail_store.close if @mail_store
      pp @kvs if $DEBUG
    end

    def assert_strenc_equal(expected_enc, expected_str, expr_str)
      assert_equal(Encoding.find(expected_enc), expr_str.encoding)
      assert_equal(expected_str.dup.force_encoding(expected_enc), expr_str)
    end
    private :assert_strenc_equal

    def test_mbox
      assert_equal(0, @mail_store.cnum)
      assert_equal(1, @mail_store.uidvalidity)
      assert_equal([], @mail_store.each_mbox_id.to_a)

      assert_equal(1, @mail_store.add_mbox('INBOX'))
      assert_equal(1, @mail_store.cnum)
      assert_equal(2, @mail_store.uidvalidity)
      assert_strenc_equal('utf-8', 'INBOX', @mail_store.mbox_name(1))
      assert_equal(1, @mail_store.mbox_id('INBOX'))
      assert_equal([ 1 ], @mail_store.each_mbox_id.to_a)

      assert_equal('INBOX', @mail_store.rename_mbox(1, 'foo'))
      assert_equal(2, @mail_store.cnum)
      assert_equal(2, @mail_store.uidvalidity)
      assert_strenc_equal('utf-8', 'foo', @mail_store.mbox_name(1))
      assert_equal(1, @mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('INBOX'))
      assert_equal([ 1 ], @mail_store.each_mbox_id.to_a)

      assert_equal('foo', @mail_store.del_mbox(1))
      assert_equal(3, @mail_store.cnum)
      assert_equal(2, @mail_store.uidvalidity)
      assert_nil(@mail_store.mbox_name(1))
      assert_nil(@mail_store.mbox_id('foo'))
      assert_equal([], @mail_store.each_mbox_id.to_a)

      assert_equal(2, @mail_store.add_mbox('INBOX'))
      assert_equal(4, @mail_store.cnum)
      assert_equal(3, @mail_store.uidvalidity)
      assert_strenc_equal('utf-8', 'INBOX', @mail_store.mbox_name(2))
      assert_equal(2, @mail_store.mbox_id('INBOX'))
      assert_equal([ 2 ], @mail_store.each_mbox_id.to_a)
    end

    def test_msg
      cnum = @mail_store.cnum
      mbox_id = @mail_store.add_mbox('INBOX')
      assert_equal(0, @mail_store.mbox_msg_num(mbox_id))
      assert_equal([], @mail_store.each_msg_uid(mbox_id).to_a)
      assert(! (@mail_store.msg_exist? mbox_id, 1))
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      uid = @mail_store.add_msg(mbox_id, 'foo', Time.parse('1975-11-19 12:34:56'))
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal(1, @mail_store.mbox_msg_num(mbox_id))
      assert((@mail_store.msg_exist? mbox_id, 1))
      assert_equal([ uid ], @mail_store.each_msg_uid(mbox_id).to_a)

      assert_equal('foo', @mail_store.msg_text(mbox_id, uid))
      assert_equal(Time.parse('1975-11-19 12:34:56'), @mail_store.msg_date(mbox_id, uid))

      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'recent'))

      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'draft'))
      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'recent'))

      copy_mbox_id = @mail_store.add_mbox('copy_test')
      assert_equal(0, @mail_store.mbox_msg_num(copy_mbox_id))
      assert_equal([], @mail_store.each_msg_uid(copy_mbox_id).to_a)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      @mail_store.copy_msg(uid, mbox_id, copy_mbox_id)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal(1, @mail_store.mbox_msg_num(copy_mbox_id))
      assert_equal([ uid ], @mail_store.each_msg_uid(copy_mbox_id).to_a)

      assert_equal('foo', @mail_store.msg_text(copy_mbox_id, uid))
      assert_equal(Time.parse('1975-11-19 12:34:56'), @mail_store.msg_date(copy_mbox_id, uid))

      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flag_num(copy_mbox_id, 'recent'))

      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'draft'))
      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'recent'))

      # duplicated message copy
      @mail_store.copy_msg(uid, mbox_id, copy_mbox_id)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal(2, @mail_store.mbox_msg_num(copy_mbox_id))
      assert_equal([ uid, uid + 1 ], @mail_store.each_msg_uid(copy_mbox_id).to_a)

      assert_equal('foo', @mail_store.msg_text(copy_mbox_id, uid))
      assert_equal(Time.parse('1975-11-19 12:34:56'), @mail_store.msg_date(copy_mbox_id, uid))

      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'draft'))
      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'recent'))

      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'draft'))
      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'recent'))

      @mail_store.set_msg_flag(mbox_id, uid, 'seen', true)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum

      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'draft'))
      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'recent'))

      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'draft'))
      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'draft'))
      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'recent'))

      # duplicated flag settings
      @mail_store.set_msg_flag(mbox_id, uid, 'seen', true)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum

      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'draft'))
      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'recent'))

      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'draft'))
      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'draft'))
      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'recent'))

      @mail_store.set_msg_flag(mbox_id, uid, 'recent', false)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum

      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'draft'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'recent'))

      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'draft'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'recent'))

      # duplicated
      @mail_store.set_msg_flag(mbox_id, uid, 'recent', false)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum

      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'draft'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'recent'))

      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'draft'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'recent'))

      @mail_store.set_msg_flag(mbox_id, uid, 'deleted', true)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum

      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'flagged'))
      assert_equal(1, @mail_store.mbox_flag_num(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'flagged'))
      assert_equal(true, @mail_store.msg_flag(mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'draft'))
      assert_equal(false, @mail_store.msg_flag(mbox_id, uid, 'recent'))

      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'draft'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'recent'))

      @mail_store.expunge_mbox(mbox_id)
      assert(@mail_store.cnum > cnum); cnum = @mail_store.cnum
      assert_equal(0, @mail_store.mbox_msg_num(mbox_id))
      assert_equal([], @mail_store.each_msg_uid(mbox_id).to_a)

      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flag_num(mbox_id, 'recent'))

      assert_equal(2, @mail_store.mbox_msg_num(copy_mbox_id))
      assert_equal([ uid, uid + 1 ], @mail_store.each_msg_uid(copy_mbox_id).to_a)

      assert_equal(2, @mail_store.mbox_flag_num(copy_mbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flag_num(copy_mbox_id, 'recent'))

      assert_equal(true, @mail_store.msg_flag(copy_mbox_id, uid, 'seen'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'answered'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'draft'))
      assert_equal(false, @mail_store.msg_flag(copy_mbox_id, uid, 'recent'))
    end

    def test_mail_folder
      mbox_id = @mail_store.add_mbox('INBOX')
      folder = @mail_store.select_mbox(mbox_id)
      assert_equal(mbox_id, folder.mbox_id)
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
      @mail_store.each_msg_uid(mbox_id) do |id|
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
      assert_equal([], @mail_store.each_msg_uid(mbox_id).to_a)
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

    def test_close_open
      mbox_id1 = @mail_store.add_mbox('INBOX')
      msg_uid1 = @mail_store.add_msg(mbox_id1, 'foo', Time.local(2014, 5, 6, 12, 34, 56))
      msg_uid2 = @mail_store.add_msg(mbox_id1, 'bar', Time.local(2014, 5, 6, 12, 34, 57))
      msg_uid3 = @mail_store.add_msg(mbox_id1, 'baz', Time.local(2014, 5, 6, 12, 34, 58))
      mbox_id2 = @mail_store.add_mbox('foo')
      mbox_id3 = @mail_store.add_mbox('bar')

      assert_equal(mbox_id3 +1, @mail_store.uidvalidity)
      assert_equal([ mbox_id1, mbox_id2, mbox_id3 ], @mail_store.each_mbox_id.to_a)
      assert_equal('INBOX', @mail_store.mbox_name(mbox_id1))
      assert_equal('foo', @mail_store.mbox_name(mbox_id2))
      assert_equal('bar', @mail_store.mbox_name(mbox_id3))
      assert_equal(mbox_id1, @mail_store.mbox_id('INBOX'))
      assert_equal(mbox_id2, @mail_store.mbox_id('foo'))
      assert_equal(mbox_id3, @mail_store.mbox_id('bar'))
      assert_equal(mbox_id3 + 1, @mail_store.uid(mbox_id1))
      assert_equal(1, @mail_store.uid(mbox_id2))
      assert_equal(1, @mail_store.uid(mbox_id3))
      assert_equal(3, @mail_store.mbox_msg_num(mbox_id1))
      assert_equal(0, @mail_store.mbox_msg_num(mbox_id2))
      assert_equal(0, @mail_store.mbox_msg_num(mbox_id2))

      assert_equal([ msg_uid1, msg_uid2, msg_uid3 ], @mail_store.each_msg_uid(mbox_id1).to_a)
      assert_equal('foo', @mail_store.msg_text(mbox_id1, msg_uid1))
      assert_equal('bar', @mail_store.msg_text(mbox_id1, msg_uid2))
      assert_equal('baz', @mail_store.msg_text(mbox_id1, msg_uid3))
      assert_equal(Time.local(2014, 5, 6, 12, 34, 56), @mail_store.msg_date(mbox_id1, msg_uid1))
      assert_equal(Time.local(2014, 5, 6, 12, 34, 57), @mail_store.msg_date(mbox_id1, msg_uid2))
      assert_equal(Time.local(2014, 5, 6, 12, 34, 58), @mail_store.msg_date(mbox_id1, msg_uid3))

      @mail_store.close
      @mail_store = RIMS::MailStore.new(RIMS::DB::Meta.new(@kvs_open.call('meta')),
                                        RIMS::DB::Message.new(@kvs_open.call('msg'))) {|mbox_id|
        RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }

      assert_equal(mbox_id3 +1, @mail_store.uidvalidity)
      assert_equal([ mbox_id1, mbox_id2, mbox_id3 ], @mail_store.each_mbox_id.to_a)
      assert_equal('INBOX', @mail_store.mbox_name(mbox_id1))
      assert_equal('foo', @mail_store.mbox_name(mbox_id2))
      assert_equal('bar', @mail_store.mbox_name(mbox_id3))
      assert_equal(mbox_id1, @mail_store.mbox_id('INBOX'))
      assert_equal(mbox_id2, @mail_store.mbox_id('foo'))
      assert_equal(mbox_id3, @mail_store.mbox_id('bar'))
      assert_equal(mbox_id3 + 1, @mail_store.uid(mbox_id1))
      assert_equal(1, @mail_store.uid(mbox_id2))
      assert_equal(1, @mail_store.uid(mbox_id3))
      assert_equal(3, @mail_store.mbox_msg_num(mbox_id1))
      assert_equal(0, @mail_store.mbox_msg_num(mbox_id2))
      assert_equal(0, @mail_store.mbox_msg_num(mbox_id2))

      assert_equal([ msg_uid1, msg_uid2, msg_uid3 ], @mail_store.each_msg_uid(mbox_id1).to_a)
      assert_equal('foo', @mail_store.msg_text(mbox_id1, msg_uid1))
      assert_equal('bar', @mail_store.msg_text(mbox_id1, msg_uid2))
      assert_equal('baz', @mail_store.msg_text(mbox_id1, msg_uid3))
      assert_equal(Time.local(2014, 5, 6, 12, 34, 56), @mail_store.msg_date(mbox_id1, msg_uid1))
      assert_equal(Time.local(2014, 5, 6, 12, 34, 57), @mail_store.msg_date(mbox_id1, msg_uid2))
      assert_equal(Time.local(2014, 5, 6, 12, 34, 58), @mail_store.msg_date(mbox_id1, msg_uid3))
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
