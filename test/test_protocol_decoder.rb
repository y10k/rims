# -*- coding: utf-8 -*-

require 'logger'
require 'rims'
require 'stringio'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolDecoderTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @kvs_open = proc{|user_name, db_name|
        kvs = {}
        def kvs.sync
          self
        end
        def kvs.close
          self
        end
        path = "#{user_name}/#{db_name}"
        RIMS::GDBM_KeyValueStore.new(@kv_store[path] = kvs)
      }
      @mail_store_pool = RIMS::MailStorePool.new(@kvs_open, @kvs_open)
      @mail_store_holder = @mail_store_pool.get('foo')
      @mail_store = @mail_store_holder.to_mst
      @inbox_id = @mail_store.mbox_id('INBOX')
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL
      @passwd =proc{|username, password|username == 'foo' && password == 'open_sesame'}
      @decoder = RIMS::ProtocolDecoder.new(@mail_store_pool, @passwd, @logger)
    end

    def teardown
      @decoder.cleanup
      @mail_store_pool.put(@mail_store_holder)
      assert(@mail_store_pool.empty?)
    end

    def test_capability
      res = @decoder.capability('T001').each
      assert_equal('* CAPABILITY IMAP4rev1', res.next)
      assert_equal('T001 OK CAPABILITY completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_logout
      res = @decoder.logout('T003').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T003 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_login
      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T001', 'foo', 'detarame').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.logout('T003').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T003 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
    end

    def test_select
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.select('T001', 'INBOX').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.select('T003', 'INBOX').each
      assert_equal('* 0 EXISTS', res.next)
      assert_equal('* 0 RECENT', res.next)
      assert_equal('* OK [UNSEEN 0]', res.next)
      assert_equal('* OK [UIDVALIDITY 1]', res.next)
      assert_equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)', res.next)
      assert_equal('T003 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.logout('T004').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T004 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
    end

    def test_examine_not_implemented
      assert_equal(false, @decoder.auth?)

      res = @decoder.examine('T001', 'INBOX').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.examine('T003', 'INBOX').each
      assert_equal('T003 BAD not implemented', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_create
      assert_equal(false, @decoder.auth?)

      res = @decoder.create('T001', 'foo').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      assert_nil(@mail_store.mbox_id('foo'))
      res = @decoder.create('T003', 'foo').each
      assert_equal('T003 OK CREATE completed', res.next)
      assert_raise(StopIteration) { res.next }
      assert_not_nil(@mail_store.mbox_id('foo'))

      res = @decoder.create('T004', 'inbox').each
      assert_match(/^T004 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.logout('T005').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T005 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_delete
      @mail_store.add_mbox('foo')

      assert_equal(false, @decoder.auth?)

      res = @decoder.delete('T001', 'foo').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }
      assert_not_nil(@mail_store.mbox_id('foo'))

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.delete('T003', 'foo').each
      assert_equal('T003 OK DELETE completed', res.next)
      assert_raise(StopIteration) { res.next }
      assert_nil(@mail_store.mbox_id('foo'))

      res = @decoder.delete('T004', 'bar').each
      assert_match(/^T004 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.delete('T005', 'inbox').each
      assert_match(/^T005 NO /, res.next)
      assert_raise(StopIteration) { res.next }
      assert_not_nil(@mail_store.mbox_id('inbox'))

      res = @decoder.logout('T006').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T006 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_rename_not_implemented
      @mail_store.add_mbox('foo')
      assert_not_nil(@mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('bar'))

      assert_equal(false, @decoder.auth?)

      res = @decoder.rename('T001', 'foo', 'bar').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }
      assert_not_nil(@mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('bar'))

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.rename('T003', 'foo', 'bar').each
      assert_equal('T003 BAD not implemented', res.next)
      assert_raise(StopIteration) { res.next }
      assert_not_nil(@mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('bar'))
    end

    def test_subscribe_not_implemented
      assert_equal(false, @decoder.auth?)

      res = @decoder.subscribe('T001', 'INBOX').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.subscribe('T003', 'INBOX').each
      assert_equal('T003 BAD not implemented', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_unsubscribe_not_implemented
      assert_equal(false, @decoder.auth?)

      res = @decoder.unsubscribe('T001', 'INBOX').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.unsubscribe('T003', 'INBOX').each
      assert_equal('T003 BAD not implemented', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_list
      assert_equal(false, @decoder.auth?)

      res = @decoder.list('T001', '', '').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.list('T003', '', '').each
      assert_equal('* LIST (\Noselect) NIL ""', res.next)
      assert_equal('T003 OK LIST completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.list('T004', '', 'nobox').each
      assert_equal('T004 OK LIST completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.list('T005', '', '*').each
      assert_equal('* LIST (\Noinferiors \Unmarked) NIL "INBOX"', res.next)
      assert_equal('T005 OK LIST completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.add_msg(@inbox_id, 'foo')

      res = @decoder.list('T006', '', '*').each
      assert_equal('* LIST (\Noinferiors \Marked) NIL "INBOX"', res.next)
      assert_equal('T006 OK LIST completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.add_mbox('foo')

      res = @decoder.list('T007', '', '*').each
      assert_equal('* LIST (\Noinferiors \Marked) NIL "INBOX"', res.next)
      assert_equal('* LIST (\Noinferiors \Unmarked) NIL "foo"', res.next)
      assert_equal('T007 OK LIST completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.list('T008', '', 'f*').each
      assert_equal('* LIST (\Noinferiors \Unmarked) NIL "foo"', res.next)
      assert_equal('T008 OK LIST completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.list('T009', 'IN', '*').each
      assert_equal('* LIST (\Noinferiors \Marked) NIL "INBOX"', res.next)
      assert_equal('T009 OK LIST completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.logout('T010').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T010 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_status
      assert_equal(false, @decoder.auth?)

      res = @decoder.status('T001', 'nobox', [ :group, 'MESSAGES' ]).each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.status('T003', 'nobox', [ :group, 'MESSAGES' ]).each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.status('T004', 'INBOX', [ :group, 'MESSAGES' ]).each
      assert_equal('* STATUS "INBOX" (MESSAGES 0)', res.next)
      assert_equal('T004 OK STATUS completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.status('T005', 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]).each
      assert_equal("* STATUS \"INBOX\" (MESSAGES 0 RECENT 0 UIDNEXT 1 UIDVALIDITY #{@inbox_id} UNSEEN 0)", res.next)
      assert_equal('T005 OK STATUS completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.add_msg(@inbox_id, 'foo')
      res = @decoder.status('T006', 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]).each
      assert_equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 1 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 1)", res.next)
      assert_equal('T006 OK STATUS completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
      res = @decoder.status('T007', 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]).each
      assert_equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 1)", res.next)
      assert_equal('T007 OK STATUS completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
      res = @decoder.status('T008', 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]).each
      assert_equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 0)", res.next)
      assert_equal('T008 OK STATUS completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.add_msg(@inbox_id, 'bar')
      res = @decoder.status('T009', 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]).each
      assert_equal("* STATUS \"INBOX\" (MESSAGES 2 RECENT 1 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 1)", res.next)
      assert_equal('T009 OK STATUS completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      res = @decoder.status('T010', 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]).each
      assert_equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 0)", res.next)
      assert_equal('T010 OK STATUS completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.status('T011', 'INBOX', 'MESSAGES').each
      assert_match(/^T011 BAD /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.status('T012', 'INBOX', [ :group, 'DETARAME' ]).each
      assert_match(/^T012 BAD /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.logout('T013').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T013 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_lsub_not_implemented
      assert_equal(false, @decoder.auth?)

      res = @decoder.lsub('T001', '', '').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.lsub('T003', '', '').each
      assert_equal('T003 BAD not implemented', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_append
      assert_equal(false, @decoder.auth?)

      res = @decoder.append('T001', 'INBOX', 'a').each
      assert_match(/^T001 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([], @mail_store.each_msg_id(@inbox_id).to_a)

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.append('T003', 'INBOX', 'a').each
      assert_equal('T003 OK APPEND completed', res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal('a', @mail_store.msg_text(@inbox_id, 1))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'recent'))

      res = @decoder.append('T004', 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], 'b').each
      assert_equal('T004 OK APPEND completed', res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1, 2 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal('b', @mail_store.msg_text(@inbox_id, 2))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'answered'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'flagged'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'deleted'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'draft'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'recent'))

      res = @decoder.append('T005', 'INBOX', '19-Nov-1975 12:34:56 +0900', 'c').each
      assert_equal('T005 OK APPEND completed', res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal('c', @mail_store.msg_text(@inbox_id, 3))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'answered'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 3, 'recent'))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), @mail_store.msg_date(@inbox_id, 3))

      res = @decoder.append('T006', 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], '19-Nov-1975 12:34:56 +0900', 'd').each
      assert_equal('T006 OK APPEND completed', res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal('d', @mail_store.msg_text(@inbox_id, 4))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'answered'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'flagged'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'deleted'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'seen'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'draft'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'recent'))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), @mail_store.msg_date(@inbox_id, 4))

      res = @decoder.append('T007', 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], '19-Nov-1975 12:34:56 +0900', :NIL, 'x').each
      assert_match(/^T007 BAD /, res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)

      res = @decoder.append('T008', 'INBOX', '19-Nov-1975 12:34:56 +0900', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], 'x').each
      assert_match(/^T008 BAD /, res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)

      res = @decoder.append('T009', 'INBOX', [ :group, '\Recent' ], 'x').each
      assert_match(/^T009 BAD /, res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)

      res = @decoder.append('T010', 'INBOX', 'bad date-time', 'x').each
      assert_match(/^T010 BAD /, res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)

      res = @decoder.append('T011', 'nobox', 'x').each
      assert_match(/^T011 NO \[TRYCREATE\]/, res.next)
      assert_raise(StopIteration) { res.next }
      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)

      res = @decoder.logout('T012').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T012 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_check
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.check('T001').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.check('T003').each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.check('T005').each
      assert_equal('T005 OK CHECK completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.logout('T006').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T006 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_close
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.close('T001').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.close('T003').each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.close('T005').each
      assert_equal('T005 OK CLOSE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      @mail_store.add_msg(@inbox_id, 'foo')
      assert_equal([ 1 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.select('T006', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T006 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)
      assert_equal([ 1 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.close('T007').each
      assert_equal('T007 OK CLOSE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
      assert_equal([ 1 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.select('T008', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T008 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)
      assert_equal([ 1 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'recent'))

      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)

      res = @decoder.close('T009').each
      assert_equal('T009 OK CLOSE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
      assert_equal([], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.logout('T010').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T010 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_expunge
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.expunge('T001').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.expunge('T003').each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.expunge('T005').each
      assert_equal('T005 OK EXPUNGE completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.add_msg(@inbox_id, 'a')
      @mail_store.add_msg(@inbox_id, 'b')
      @mail_store.add_msg(@inbox_id, 'c')
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)

      res = @decoder.expunge('T006').each
      assert_equal('T006 OK EXPUNGE completed', res.next)
      assert_raise(StopIteration) { res.next }

      for name in %w[ answered flagged seen draft ]
        @mail_store.set_msg_flag(@inbox_id, 2, name, true)
        @mail_store.set_msg_flag(@inbox_id, 3, name, true)
      end
      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)

      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'recent'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'deleted'))

      res = @decoder.expunge('T007').each
      assert_equal('* 2 EXPUNGE', res.next)
      assert_equal('T007 OK EXPUNGE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(2, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'recent'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))

      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.set_msg_flag(@inbox_id, 3, 'deleted', true)
      
      assert_equal([ 1, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(2, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'recent'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))

      res = @decoder.expunge('T008').each
      assert_equal('* 1 EXPUNGE', res.next)
      assert_equal('* 2 EXPUNGE', res.next)
      assert_equal('T008 OK EXPUNGE completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.logout('T009').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T009 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_search
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.search('T001', 'ALL').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.search('T003', 'ALL').each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.search('T005', 'ALL').each
      assert_equal('* SEARCH', res.next)
      assert_equal('T005 OK SEARCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: alice\r\n\r\napple")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: alice\r\n\r\nbnana")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\norange")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\nmelon")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\npineapple")
      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)
      @mail_store.set_msg_flag(@inbox_id, 4, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5 ], @mail_store.each_msg_id(@inbox_id).to_a)

      res = @decoder.search('T006', 'ALL').each
      assert_equal('* SEARCH 1 2 3', res.next)
      assert_equal('T006 OK SEARCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.search('T007', 'ALL', uid: true).each
      assert_equal('* SEARCH 1 3 5', res.next)
      assert_equal('T007 OK SEARCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.search('T008', 'OR', 'FROM', 'alice', 'FROM', 'bob', 'BODY', 'apple').each
      assert_equal('* SEARCH 1 3', res.next)
      assert_equal('T008 OK SEARCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.search('T009', 'OR', 'FROM', 'alice', 'FROM', 'bob', 'BODY', 'apple', uid: true).each
      assert_equal('* SEARCH 1 5', res.next)
      assert_equal('T009 OK SEARCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.logout('T010').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T010 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_fetch
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)

      @mail_store.add_msg(@inbox_id, <<-'EOF', Time.parse('2013-11-08 06:47:50 +0900'))
To: foo@nonet.org
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
      EOF

      @mail_store.add_msg(@inbox_id, <<-'EOF', Time.parse('2013-11-08 19:31:03 +0900'))
To: bar@nonet.com
From: foo@nonet.com
Subject: multipart test
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351297"

--1383.905529.351297
Content-Type: text/plain; charset=us-ascii

Multipart test.
--1383.905529.351297
Content-Type: application/octet-stream

0123456789
--1383.905529.351297
Content-Type: message/rfc822

To: bar@nonet.com
From: foo@nonet.com
Subject: inner multipart
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351298"

--1383.905529.351298
Content-Type: text/plain; charset=us-ascii

Hello world.
--1383.905529.351298
Content-Type: application/octet-stream

9876543210
--1383.905529.351298--
--1383.905529.351297
Content-Type: multipart/mixed; boundary="1383.905529.351299"

--1383.905529.351299
Content-Type: image/gif

--1383.905529.351299
Content-Type: message/rfc822

To: bar@nonet.com
From: foo@nonet.com
Subject: inner multipart
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351300"

--1383.905529.351300
Content-Type: text/plain; charset=us-ascii

HALO
--1383.905529.351300
Content-Type: multipart/alternative; boundary="1383.905529.351301"

--1383.905529.351301
Content-Type: text/plain; charset=us-ascii

alternative message.
--1383.905529.351301
Content-Type: text/html; charset=us-ascii

<html>
<body><p>HTML message</p></body>
</html>
--1383.905529.351301--
--1383.905529.351300--
--1383.905529.351299--
--1383.905529.351297--
      EOF

      assert_equal([ 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.fetch('T001', '1:*', 'FAST').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.fetch('T003', '1:*', 'FAST').each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.fetch('T005', '1:*', 'FAST').each
      assert_equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-11-2013 06:47:50 +0900" RFC822.SIZE 212)', res.next)
      assert_equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-11-2013 19:31:03 +0900" RFC822.SIZE 1616)', res.next)
      assert_equal('T005 OK FETCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.fetch('T006', '1:*', [ :group, 'FAST' ]).each
      assert_equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-11-2013 06:47:50 +0900" RFC822.SIZE 212)', res.next)
      assert_equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-11-2013 19:31:03 +0900" RFC822.SIZE 1616)', res.next)
      assert_equal('T006 OK FETCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.fetch('T007', '1:*', [ :group, 'FLAGS', 'RFC822.HEADER', 'UID' ]).each
      s = ''
      s << "To: foo@nonet.org\r\n"
      s << "From: bar@nonet.org\r\n"
      s << "Subject: test\r\n"
      s << "MIME-Version: 1.0\r\n"
      s << "Content-Type: text/plain; charset=us-ascii\r\n"
      s << "Content-Transfer-Encoding: 7bit\r\n"
      s << "Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)\r\n"
      s << "\r\n"
      assert_equal("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n#{s} UID 2)", res.next)
      s = ''
      s << "To: bar@nonet.com\r\n"
      s << "From: foo@nonet.com\r\n"
      s << "Subject: multipart test\r\n"
      s << "MIME-Version: 1.0\r\n"
      s << "Date: Fri, 8 Nov 2013 19:31:03 +0900\r\n"
      s << "Content-Type: multipart/mixed; boundary=\"1383.905529.351297\"\r\n"
      s << "\r\n"
      assert_equal("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n#{s} UID 3)", res.next)
      assert_equal('T007 OK FETCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.fetch('T008', '1', 'RFC822').each
      s = ''
      s << "To: foo@nonet.org\r\n"
      s << "From: bar@nonet.org\r\n"
      s << "Subject: test\r\n"
      s << "MIME-Version: 1.0\r\n"
      s << "Content-Type: text/plain; charset=us-ascii\r\n"
      s << "Content-Transfer-Encoding: 7bit\r\n"
      s << "Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)\r\n"
      s << "\r\n"
      s << "Hello world.\r\n"
      assert_equal("* 1 FETCH (FLAGS (\\Seen \\Recent) RFC822 {#{s.bytesize}}\r\n#{s})", res.next)
      assert_equal('T008 OK FETCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      body = RIMS::Protocol.body(symbol: 'BODY', option: 'PEEK', section: '1', section_list: [ '1' ])
      res = @decoder.fetch('T009', '2', [ :body, body ]).each
      assert_equal('* 2 FETCH (BODY[1] "Multipart test.")', res.next)
      assert_equal('T009 OK FETCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.fetch('T010', '2', 'RFC822', uid: true).each
      s = ''
      s << "To: foo@nonet.org\r\n"
      s << "From: bar@nonet.org\r\n"
      s << "Subject: test\r\n"
      s << "MIME-Version: 1.0\r\n"
      s << "Content-Type: text/plain; charset=us-ascii\r\n"
      s << "Content-Transfer-Encoding: 7bit\r\n"
      s << "Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)\r\n"
      s << "\r\n"
      s << "Hello world.\r\n"
      assert_equal("* 1 FETCH (UID 2 RFC822 {#{s.bytesize}}\r\n#{s})", res.next)
      assert_equal('T010 OK FETCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      body = RIMS::Protocol.body(symbol: 'BODY', option: 'PEEK', section: '1', section_list: [ '1' ])
      res = @decoder.fetch('T011', '3', [ :group, 'UID', [ :body, body ] ], uid: true).each
      assert_equal('* 2 FETCH (UID 3 BODY[1] "Multipart test.")', res.next)
      assert_equal('T011 OK FETCH completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.logout('T012').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T012 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_store
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        @mail_store.add_msg(@inbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS', [ :group, '\Answered' ]).each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS', [ :group, '\Answered' ]).each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS', [ :group, '\Answered' ]).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Recent)', res.next)
      assert_equal('T005 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))

      res = @decoder.store('T006', '1:2', '+FLAGS', [ :group, '\Flagged' ]).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Flagged \Recent)', res.next)
      assert_equal('T006 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T007', '1:3', '+FLAGS', [ :group, '\Deleted' ]).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Deleted \Recent)', res.next)
      assert_equal('T007 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T008', '1:4', '+FLAGS', [ :group, '\Seen' ]).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Seen \Recent)', res.next)
      assert_equal('T008 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T009', '1:5', '+FLAGS', [ :group, '\Draft' ]).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)', res.next)
      assert_equal('* 5 FETCH FLAGS (\Draft \Recent)', res.next)
      assert_equal('T009 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 9, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T010', '1:*', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('T010 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T011', '1', '-FLAGS', [ :group, '\Answered' ]).each
      assert_equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('T011 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T012', '1:2', '-FLAGS', [ :group, '\Flagged' ]).each
      assert_equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('T012 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T013', '1:3', '-FLAGS', [ :group, '\Deleted' ]).each
      assert_equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)', res.next)
      assert_equal('T013 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T014', '1:4', '-FLAGS', [ :group, '\Seen' ]).each
      assert_equal('* 1 FETCH FLAGS (\Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)', res.next)
      assert_equal('T014 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T015', '1:5', '-FLAGS', [ :group, '\Draft' ]).each
      assert_equal('* 1 FETCH FLAGS (\Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)', res.next)
      assert_equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)', res.next)
      assert_equal('T015 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 9, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.logout('T016').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T016 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_store_silent
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        @mail_store.add_msg(@inbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS.SILENT', [ :group, '\Answered' ]).each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS.SILENT', [ :group, '\Answered' ]).each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS.SILENT', [ :group, '\Answered' ]).each
      assert_equal('T005 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))

      res = @decoder.store('T006', '1:2', '+FLAGS.SILENT', [ :group, '\Flagged' ]).each
      assert_equal('T006 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T007', '1:3', '+FLAGS.SILENT', [ :group, '\Deleted' ]).each
      assert_equal('T007 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T008', '1:4', '+FLAGS.SILENT', [ :group, '\Seen' ]).each
      assert_equal('T008 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T009', '1:5', '+FLAGS.SILENT', [ :group, '\Draft' ]).each
      assert_equal('T009 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 9, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T010', '1:*', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_equal('T010 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T011', '1', '-FLAGS.SILENT', [ :group, '\Answered' ]).each
      assert_equal('T011 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T012', '1:2', '-FLAGS.SILENT', [ :group, '\Flagged' ]).each
      assert_equal('T012 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T013', '1:3', '-FLAGS.SILENT', [ :group, '\Deleted' ]).each
      assert_equal('T013 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T014', '1:4', '-FLAGS.SILENT', [ :group, '\Seen' ]).each
      assert_equal('T014 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T015', '1:5', '-FLAGS.SILENT', [ :group, '\Draft' ]).each
      assert_equal('T015 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 9, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.logout('T016').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T016 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_uid_store
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        @mail_store.add_msg(@inbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS', [ :group, '\Answered' ], uid: true).each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS', [ :group, '\Answered' ], uid: true).each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS', [ :group, '\Answered' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Recent)', res.next)
      assert_equal('T005 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))

      res = @decoder.store('T006', '1,3', '+FLAGS', [ :group, '\Flagged' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Flagged \Recent)', res.next)
      assert_equal('T006 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T007', '1,3,5', '+FLAGS', [ :group, '\Deleted' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Deleted \Recent)', res.next)
      assert_equal('T007 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T008', '1,3,5,7', '+FLAGS', [ :group, '\Seen' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Seen \Recent)', res.next)
      assert_equal('T008 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T009', '1,3,5,7,9', '+FLAGS', [ :group, '\Draft' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)', res.next)
      assert_equal('* 5 FETCH FLAGS (\Draft \Recent)', res.next)
      assert_equal('T009 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 9, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T010', '1:*', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('T010 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T011', '1', '-FLAGS', [ :group, '\Answered' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('T011 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T012', '1,3', '-FLAGS', [ :group, '\Flagged' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)', res.next)
      assert_equal('T012 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T013', '1,3,5', '-FLAGS', [ :group, '\Deleted' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)', res.next)
      assert_equal('T013 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T014', '1,3,5,7', '-FLAGS', [ :group, '\Seen' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Draft \Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)', res.next)
      assert_equal('T014 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T015', '1,3,5,7,9', '-FLAGS', [ :group, '\Draft' ], uid: true).each
      assert_equal('* 1 FETCH FLAGS (\Recent)', res.next)
      assert_equal('* 2 FETCH FLAGS (\Answered \Recent)', res.next)
      assert_equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)', res.next)
      assert_equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)', res.next)
      assert_equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)', res.next)
      assert_equal('T015 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 9, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.logout('T016').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T016 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_uid_store_silent
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        @mail_store.add_msg(@inbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true).each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true).each
      assert_match(/^T003 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true).each
      assert_equal('T005 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))

      res = @decoder.store('T006', '1,3', '+FLAGS.SILENT', [ :group, '\Flagged' ], uid: true).each
      assert_equal('T006 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T007', '1,3,5', '+FLAGS.SILENT', [ :group, '\Deleted' ], uid: true).each
      assert_equal('T007 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T008', '1,3,5,7', '+FLAGS.SILENT', [ :group, '\Seen' ], uid: true).each
      assert_equal('T008 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T009', '1,3,5,7,9', '+FLAGS.SILENT', [ :group, '\Draft' ], uid: true).each
      assert_equal('T009 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 5, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 7, 'draft'))
      assert(@mail_store.msg_flag(@inbox_id, 9, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T010', '1:*', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_equal('T010 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T011', '1', '-FLAGS.SILENT', [ :group, '\Answered' ], uid: true).each
      assert_equal('T011 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T012', '1,3', '-FLAGS.SILENT', [ :group, '\Flagged' ], uid: true).each
      assert_equal('T012 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T013', '1,3,5', '-FLAGS.SILENT', [ :group, '\Deleted' ], uid: true).each
      assert_equal('T013 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T014', '1,3,5,7', '-FLAGS.SILENT', [ :group, '\Seen' ], uid: true).each
      assert_equal('T014 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.store('T015', '1,3,5,7,9', '-FLAGS.SILENT', [ :group, '\Draft' ], uid: true).each
      assert_equal('T015 OK STORE completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(4, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'deleted'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'seen'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 5, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 7, 'draft'))
      assert(! @mail_store.msg_flag(@inbox_id, 9, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      res = @decoder.logout('T016').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T016 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_copy
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        msg_id = @mail_store.add_msg(@inbox_id, msg_src.next)
        @mail_store.set_msg_flag(@inbox_id, msg_id, 'flagged', true)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      work_id = @mail_store.add_mbox('WORK')
      assert_equal([], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(0, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'recent'))

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.copy('T001', '2:4', 'WORK').each
      assert_match(/^T001 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.copy('T003', '2:4', 'WORK').each
      assert_match(/^T003 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal([], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(0, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'recent'))

      res = @decoder.copy('T005', '2:4', 'WORK').each
      assert_equal('T005 OK COPY completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal([ 3, 5, 7 ], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'recent'))

      # duplicted message copy
      res = @decoder.copy('T006', '2:4', 'WORK').each
      assert_equal('T006 OK COPY completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal([ 3, 5, 7 ], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'recent'))

      # copy of empty messge set
      res = @decoder.copy('T007', '100', 'WORK').each
      assert_equal('T007 OK COPY completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal([ 3, 5, 7 ], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'recent'))

      res = @decoder.copy('T008', '1:*', 'nobox').each
      assert_match(/^T008 NO \[TRYCREATE\]/, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.logout('T009').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T009 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_uid_copy
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        msg_id = @mail_store.add_msg(@inbox_id, msg_src.next)
        @mail_store.set_msg_flag(@inbox_id, msg_id, 'flagged', true)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      work_id = @mail_store.add_mbox('WORK')
      assert_equal([], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(0, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'recent'))

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.copy('T001', '3,5,7', 'WORK', uid: true).each
      assert_match(/^T001 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.copy('T003', '3,5,7', 'WORK', uid: true).each
      assert_match(/^T003 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.select('T004', 'INBOX').each
      res.next while (res.peek =~ /^\* /)
      assert_equal('T004 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal([], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(0, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'recent'))

      res = @decoder.copy('T005', '3,5,7', 'WORK', uid: true).each
      assert_equal('T005 OK COPY completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal([ 3, 5, 7 ], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'recent'))

      # duplicted message copy
      res = @decoder.copy('T006', '3,5,7', 'WORK', uid: true).each
      assert_equal('T006 OK COPY completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal([ 3, 5, 7 ], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'recent'))

      # copy of empty messge set
      res = @decoder.copy('T007', '100', 'WORK', uid: true).each
      assert_equal('T007 OK COPY completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      assert_equal([ 3, 5, 7 ], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'recent'))

      res = @decoder.copy('T008', '1:*', 'nobox', uid: true).each
      assert_match(/^T008 NO \[TRYCREATE\]/, res.next)
      assert_raise(StopIteration) { res.next }

      res = @decoder.logout('T009').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T009 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_empty
      output = StringIO.new('', 'w')
      RIMS::ProtocolDecoder.repl(@decoder, StringIO.new('', 'r'), output, @logger)
      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", output.string)

      output = StringIO.new('', 'w')
      RIMS::ProtocolDecoder.repl(@decoder, StringIO.new("\n\t\n \r\n ", 'r'), output, @logger)
      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", output.string)
    end

    def test_command_loop_client_syntax_error
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 FETCH 1 (BODY
T002 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_equal("* BAD client command syntax error.\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T002 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_capability
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 CAPABILITY
T002 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_equal("* CAPABILITY IMAP4rev1\r\n", res.next)
      assert_equal("T001 OK CAPABILITY completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T002 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_login
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 LOGIN foo detarame
T002 LOGIN foo open_sesame
T003 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T003 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_select
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 SELECT INBOX
T002 LOGIN foo open_sesame
T003 SELECT INBOX
T004 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_equal("* 0 EXISTS\r\n", res.next)
      assert_equal("* 0 RECENT\r\n", res.next)
      assert_equal("* OK [UNSEEN 0]\r\n", res.next)
      assert_equal("* OK [UIDVALIDITY 1]\r\n", res.next)
      assert_equal("* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n", res.next)
      assert_equal("T003 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T004 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_create
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 CREATE foo
T002 LOGIN foo open_sesame
T003 CREATE foo
T004 CREATE inbox
T005 LOGOUT
      EOF

      assert_nil(@mail_store.mbox_id('foo'))
      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      assert_not_nil(@mail_store.mbox_id('foo'))
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_equal("T003 OK CREATE completed\r\n", res.next)

      assert_match(/^T004 NO /, res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T005 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_delete
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 DELETE foo
T002 LOGIN foo open_sesame
T003 DELETE foo
T004 DELETE bar
T005 DELETE inbox
T006 LOGOUT
      EOF

      @mail_store.add_mbox('foo')
      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      assert_nil(@mail_store.mbox_id('foo'))
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_equal("T003 OK DELETE completed\r\n", res.next)

      assert_match(/^T004 NO /, res.next)

      assert_match(/^T005 NO /, res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T006 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def _test_command_loop_list
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 LIST "" ""
T002 LOGIN foo open_sesame
T003 LIST "" ""
T007 LIST "" *
T008 LIST '' f*
T009 LIST IN *
T010 LOGOUT
      EOF

      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_mbox('foo')
      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      assert_nil(@mail_store.mbox_id('foo'))
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_equal('* LIST (\Noselect) NIL ""' + "\r\n", res.next)
      assert_equal("T003 OK LIST completed\r\n", res.next)

      assert_equal('* LIST (\Noinferiors \Marked) NIL "INBOX"' + "\r\n", res.next)
      assert_equal('* LIST (\Noinferiors \Unmarked) NIL "foo"' + "\r\n", res.next)
      assert_equal("T007 OK LIST completed\r\n", res.next)

      assert_equal('* LIST (\Noinferiors \Unmarked) NIL "foo"' + "\r\n", res.next)
      assert_equal("T008 OK LIST completed\r\n", res.next)

      assert_equal('* LIST (\Noinferiors \Marked) NIL "INBOX"' + "\r\n", res.next)
      assert_equal("T009 OK LIST completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T010 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_status
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 STATUS nobox (MESSAGES)
T002 LOGIN foo open_sesame
T003 STATUS nobox (MESSAGES)
T009 STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)
T011 STATUS INBOX MESSAGES
T012 STATUS INBOX (DETARAME)
T013 LOGOUT
      EOF

      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
      @mail_store.add_msg(@inbox_id, 'bar')

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      assert_nil(@mail_store.mbox_id('foo'))
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      assert_equal("* STATUS \"INBOX\" (MESSAGES 2 RECENT 1 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 1)\r\n", res.next)
      assert_equal("T009 OK STATUS completed\r\n", res.next)

      assert_match(/^T011 BAD /, res.next)

      assert_match(/^T012 BAD /, res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T013 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_append
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 APPEND INBOX a
T002 LOGIN foo open_sesame
T003 APPEND INBOX a
T004 APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) "b"
T005 APPEND INBOX "19-Nov-1975 12:34:56 +0900" {1}
c
T006 APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) "19-Nov-1975 12:34:56 +0900" d
T007 APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) "19-Nov-1975 12:34:56 +0900" NIL x
T008 APPEND INBOX "19-Nov-1975 12:34:56 +0900" (\Answered \Flagged \Deleted \Seen \Draft) x
T009 APPEND INBOX (\Recent) x
T010 APPEND INBOX "bad date-time" x
T011 APPEND nobox x
T012 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_equal("T003 OK APPEND completed\r\n", res.next)

      assert_equal("T004 OK APPEND completed\r\n", res.next)

      assert_match(/^\+ /, res.next)
      assert_equal("T005 OK APPEND completed\r\n", res.next)

      assert_equal("T006 OK APPEND completed\r\n", res.next)

      assert_match(/^T007 BAD /, res.next)

      assert_match(/^T008 BAD /, res.next)

      assert_match(/^T009 BAD /, res.next)

      assert_match(/^T010 BAD /, res.next)

      assert_match(/^T011 NO \[TRYCREATE\]/, res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T012 OK LOGOUT completed\r\n", res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)

      assert_equal('a', @mail_store.msg_text(@inbox_id, 1))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'answered'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'draft'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'recent'))

      assert_equal('b', @mail_store.msg_text(@inbox_id, 2))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'answered'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'flagged'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'deleted'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'draft'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'recent'))

      assert_equal('c', @mail_store.msg_text(@inbox_id, 3))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'answered'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'deleted'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'draft'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 3, 'recent'))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), @mail_store.msg_date(@inbox_id, 3))

      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal('d', @mail_store.msg_text(@inbox_id, 4))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'answered'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'flagged'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'deleted'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'seen'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'draft'))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, 4, 'recent'))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), @mail_store.msg_date(@inbox_id, 4))
    end

    def test_command_loop_check
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 CHECK
T002 LOGIN foo open_sesame
T003 CHECK
T004 SELECT INBOX
T005 CHECK
T006 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("T005 OK CHECK completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T006 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_close
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 CLOSE
T002 LOGIN foo open_sesame
T003 CLOSE
T006 SELECT INBOX
T007 CLOSE
T008 LOGOUT
      EOF

      @mail_store.add_msg(@inbox_id, 'foo')
      assert_equal([ 1 ], @mail_store.each_msg_id(@inbox_id).to_a)
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T006 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("T007 OK CLOSE completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T008 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }

      assert_equal([], @mail_store.each_msg_id(@inbox_id).to_a)
    end

    def test_command_loop_expunge
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 EXPUNGE
T002 LOGIN foo open_sesame
T003 EXPUNGE
T004 SELECT INBOX
T007 EXPUNGE
T009 LOGOUT
      EOF

      @mail_store.add_msg(@inbox_id, 'a')
      @mail_store.add_msg(@inbox_id, 'b')
      @mail_store.add_msg(@inbox_id, 'c')
      for name in %w[ answered flagged seen draft ]
        @mail_store.set_msg_flag(@inbox_id, 2, name, true)
        @mail_store.set_msg_flag(@inbox_id, 3, name, true)
      end
      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)

      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(3, @mail_store.mbox_flags(@inbox_id, 'recent'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(2, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'deleted'))

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("* 2 EXPUNGE\r\n", res.next)
      assert_equal("T007 OK EXPUNGE completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T009 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(2, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'recent')) # clear by LOGOUT
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(1, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
    end

    def test_command_loop_search
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 SEARCH ALL
T002 LOGIN foo open_sesame
T003 SEARCH ALL
T004 SELECT INBOX
T006 SEARCH ALL
T007 UID SEARCH ALL
T008 SEARCH OR FROM alice FROM bob BODY apple
T009 UID SEARCH OR FROM alice FROM bob BODY apple
T010 LOGOUT
      EOF

      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: alice\r\n\r\napple")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: alice\r\n\r\nbnana")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\norange")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\nmelon")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\npineapple")
      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)
      @mail_store.set_msg_flag(@inbox_id, 4, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5 ], @mail_store.each_msg_id(@inbox_id).to_a)

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("* SEARCH 1 2 3\r\n", res.next)
      assert_equal("T006 OK SEARCH completed\r\n", res.next)

      assert_equal("* SEARCH 1 3 5\r\n", res.next)
      assert_equal("T007 OK SEARCH completed\r\n", res.next)

      assert_equal("* SEARCH 1 3\r\n", res.next)
      assert_equal("T008 OK SEARCH completed\r\n", res.next)

      assert_equal("* SEARCH 1 5\r\n", res.next)
      assert_equal("T009 OK SEARCH completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T010 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_fetch
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)

      @mail_store.add_msg(@inbox_id, <<-'EOF', Time.parse('2013-11-08 06:47:50 +0900'))
To: foo@nonet.org
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
      EOF

      @mail_store.add_msg(@inbox_id, <<-'EOF', Time.parse('2013-11-08 19:31:03 +0900'))
To: bar@nonet.com
From: foo@nonet.com
Subject: multipart test
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351297"

--1383.905529.351297
Content-Type: text/plain; charset=us-ascii

Multipart test.
--1383.905529.351297
Content-Type: application/octet-stream

0123456789
--1383.905529.351297
Content-Type: message/rfc822

To: bar@nonet.com
From: foo@nonet.com
Subject: inner multipart
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351298"

--1383.905529.351298
Content-Type: text/plain; charset=us-ascii

Hello world.
--1383.905529.351298
Content-Type: application/octet-stream

9876543210
--1383.905529.351298--
--1383.905529.351297
Content-Type: multipart/mixed; boundary="1383.905529.351299"

--1383.905529.351299
Content-Type: image/gif

--1383.905529.351299
Content-Type: message/rfc822

To: bar@nonet.com
From: foo@nonet.com
Subject: inner multipart
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351300"

--1383.905529.351300
Content-Type: text/plain; charset=us-ascii

HALO
--1383.905529.351300
Content-Type: multipart/alternative; boundary="1383.905529.351301"

--1383.905529.351301
Content-Type: text/plain; charset=us-ascii

alternative message.
--1383.905529.351301
Content-Type: text/html; charset=us-ascii

<html>
<body><p>HTML message</p></body>
</html>
--1383.905529.351301--
--1383.905529.351300--
--1383.905529.351299--
--1383.905529.351297--
      EOF

      assert_equal([ 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 FETCH 1:* FAST
T002 LOGIN foo open_sesame
T003 FETCH 1:* FAST
T004 SELECT INBOX
T005 FETCH 1:* FAST
T006 FETCH 1:* (FAST)
T007 FETCH 1:* (FLAGS RFC822.HEADER UID)
T008 FETCH 1 RFC822
T009 FETCH 2 BODY.PEEK[1]
T010 UID FETCH 2 RFC822
T011 UID FETCH 3 (UID BODY.PEEK[1])
T012 LOGOUT
      EOF

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("* 1 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-11-2013 06:47:50 +0900\" RFC822.SIZE 212)\r\n", res.next)
      assert_equal("* 2 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-11-2013 19:31:03 +0900\" RFC822.SIZE 1616)\r\n", res.next)
      assert_equal("T005 OK FETCH completed\r\n", res.next)

      assert_equal("* 1 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-11-2013 06:47:50 +0900\" RFC822.SIZE 212)\r\n", res.next)
      assert_equal("* 2 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-11-2013 19:31:03 +0900\" RFC822.SIZE 1616)\r\n", res.next)
      assert_equal("T006 OK FETCH completed\r\n", res.next)

      assert_equal("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER {198}\r\n", res.next)
      assert_equal("To: foo@nonet.org\r\n", res.next)
      assert_equal("From: bar@nonet.org\r\n", res.next)
      assert_equal("Subject: test\r\n", res.next)
      assert_equal("MIME-Version: 1.0\r\n", res.next)
      assert_equal("Content-Type: text/plain; charset=us-ascii\r\n", res.next)
      assert_equal("Content-Transfer-Encoding: 7bit\r\n", res.next)
      assert_equal("Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)\r\n", res.next)
      assert_equal("\r\n", res.next)
      assert_equal(" UID 2)\r\n", res.next)
      assert_equal("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER {186}\r\n", res.next)
      assert_equal("To: bar@nonet.com\r\n", res.next)
      assert_equal("From: foo@nonet.com\r\n", res.next)
      assert_equal("Subject: multipart test\r\n", res.next)
      assert_equal("MIME-Version: 1.0\r\n", res.next)
      assert_equal("Date: Fri, 8 Nov 2013 19:31:03 +0900\r\n", res.next)
      assert_equal("Content-Type: multipart/mixed; boundary=\"1383.905529.351297\"\r\n", res.next)
      assert_equal("\r\n", res.next)
      assert_equal(" UID 3)\r\n", res.next)
      assert_equal("T007 OK FETCH completed\r\n", res.next)

      assert_equal("* 1 FETCH (FLAGS (\\Seen \\Recent) RFC822 {212}\r\n", res.next)
      assert_equal("To: foo@nonet.org\r\n", res.next)
      assert_equal("From: bar@nonet.org\r\n", res.next)
      assert_equal("Subject: test\r\n", res.next)
      assert_equal("MIME-Version: 1.0\r\n", res.next)
      assert_equal("Content-Type: text/plain; charset=us-ascii\r\n", res.next)
      assert_equal("Content-Transfer-Encoding: 7bit\r\n", res.next)
      assert_equal("Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)\r\n", res.next)
      assert_equal("\r\n", res.next)
      assert_equal("Hello world.\r\n", res.next)
      assert_equal(")\r\n", res.next)
      assert_equal("T008 OK FETCH completed\r\n", res.next)

      assert_equal("* 2 FETCH (BODY[1] \"Multipart test.\")\r\n", res.next)
      assert_equal("T009 OK FETCH completed\r\n", res.next)

      assert_equal("* 1 FETCH (UID 2 RFC822 {212}\r\n", res.next)
      assert_equal("To: foo@nonet.org\r\n", res.next)
      assert_equal("From: bar@nonet.org\r\n", res.next)
      assert_equal("Subject: test\r\n", res.next)
      assert_equal("MIME-Version: 1.0\r\n", res.next)
      assert_equal("Content-Type: text/plain; charset=us-ascii\r\n", res.next)
      assert_equal("Content-Transfer-Encoding: 7bit\r\n", res.next)
      assert_equal("Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)\r\n", res.next)
      assert_equal("\r\n", res.next)
      assert_equal("Hello world.\r\n", res.next)
      assert_equal(")\r\n", res.next)
      assert_equal("T010 OK FETCH completed\r\n", res.next)

      assert_equal("* 2 FETCH (UID 3 BODY[1] \"Multipart test.\")\r\n", res.next)
      assert_equal("T011 OK FETCH completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T012 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))
    end

    def test_command_loop_store
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        @mail_store.add_msg(@inbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end

      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 STORE 1 +FLAGS (\Answered)
T002 LOGIN foo open_sesame
T003 STORE 1 +FLAGS (\Answered)
T004 SELECT INBOX
T005 STORE 1 +FLAGS (\Answered)
T006 STORE 1:2 +FLAGS (\Flagged)
T007 STORE 1:3 +FLAGS (\Deleted)
T008 STORE 1:4 +FLAGS (\Seen)
T009 STORE 1:5 +FLAGS (\Draft)
T010 STORE 1:* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T011 STORE 1 -FLAGS (\Answered)
T012 STORE 1:2 -FLAGS (\Flagged)
T013 STORE 1:3 -FLAGS (\Deleted)
T014 STORE 1:4 -FLAGS (\Seen)
T015 STORE 1:5 -FLAGS (\Draft)
T016 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Recent)\r\n", res.next)
      assert_equal("T005 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Flagged \\Recent)\r\n", res.next)
      assert_equal("T006 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Flagged \\Deleted \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Deleted \\Recent)\r\n", res.next)
      assert_equal("T007 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Flagged \\Deleted \\Seen \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Deleted \\Seen \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Seen \\Recent)\r\n", res.next)
      assert_equal("T008 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 5 FETCH FLAGS (\\Draft \\Recent)\r\n", res.next)
      assert_equal("T009 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 5 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("T010 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("T011 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("T012 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Answered \\Flagged \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("T013 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Answered \\Flagged \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Draft \\Recent)\r\n", res.next)
      assert_equal("T014 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Answered \\Flagged \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Recent)\r\n", res.next)
      assert_equal("* 5 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Recent)\r\n", res.next)
      assert_equal("T015 OK STORE completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T016 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_store_silent
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        @mail_store.add_msg(@inbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end

      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 STORE 1 +FLAGS.SILENT (\Answered)
T002 LOGIN foo open_sesame
T003 STORE 1 +FLAGS.SILENT (\Answered)
T004 SELECT INBOX
T005 STORE 1 +FLAGS.SILENT (\Answered)
T006 STORE 1:2 +FLAGS.SILENT (\Flagged)
T007 STORE 1:3 +FLAGS.SILENT (\Deleted)
T008 STORE 1:4 +FLAGS.SILENT (\Seen)
T009 STORE 1:5 +FLAGS.SILENT (\Draft)
T010 STORE 1:* FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
T011 STORE 1 -FLAGS.SILENT (\Answered)
T012 STORE 1:2 -FLAGS.SILENT (\Flagged)
T013 STORE 1:3 -FLAGS.SILENT (\Deleted)
T014 STORE 1:4 -FLAGS.SILENT (\Seen)
T015 STORE 1:5 -FLAGS.SILENT (\Draft)
T016 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("T005 OK STORE completed\r\n", res.next)

      assert_equal("T006 OK STORE completed\r\n", res.next)

      assert_equal("T007 OK STORE completed\r\n", res.next)

      assert_equal("T008 OK STORE completed\r\n", res.next)

      assert_equal("T009 OK STORE completed\r\n", res.next)

      assert_equal("T010 OK STORE completed\r\n", res.next)

      assert_equal("T011 OK STORE completed\r\n", res.next)

      assert_equal("T012 OK STORE completed\r\n", res.next)

      assert_equal("T013 OK STORE completed\r\n", res.next)

      assert_equal("T014 OK STORE completed\r\n", res.next)

      assert_equal("T015 OK STORE completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T016 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_uid_store
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        @mail_store.add_msg(@inbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end

      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 UID STORE 1 +FLAGS (\Answered)
T002 LOGIN foo open_sesame
T003 UID STORE 1 +FLAGS (\Answered)
T004 SELECT INBOX
T005 UID STORE 1 +FLAGS (\Answered)
T006 UID STORE 1,3 +FLAGS (\Flagged)
T007 UID STORE 1,3,5 +FLAGS (\Deleted)
T008 UID STORE 1,3,5,7 +FLAGS (\Seen)
T009 UID STORE 1,3,5,7,9 +FLAGS (\Draft)
T010 UID STORE 1:* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T011 UID STORE 1 -FLAGS (\Answered)
T012 UID STORE 1,3 -FLAGS (\Flagged)
T013 UID STORE 1,3,5 -FLAGS (\Deleted)
T014 UID STORE 1,3,5,7 -FLAGS (\Seen)
T015 UID STORE 1,3,5,7,9 -FLAGS (\Draft)
T016 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Recent)\r\n", res.next)
      assert_equal("T005 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Flagged \\Recent)\r\n", res.next)
      assert_equal("T006 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Flagged \\Deleted \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Deleted \\Recent)\r\n", res.next)
      assert_equal("T007 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Flagged \\Deleted \\Seen \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Deleted \\Seen \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Seen \\Recent)\r\n", res.next)
      assert_equal("T008 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 5 FETCH FLAGS (\\Draft \\Recent)\r\n", res.next)
      assert_equal("T009 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 5 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("T010 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Flagged \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("T011 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Deleted \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("T012 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Answered \\Flagged \\Seen \\Draft \\Recent)\r\n", res.next)
      assert_equal("T013 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Draft \\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Answered \\Flagged \\Draft \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Draft \\Recent)\r\n", res.next)
      assert_equal("T014 OK STORE completed\r\n", res.next)

      assert_equal("* 1 FETCH FLAGS (\\Recent)\r\n", res.next)
      assert_equal("* 2 FETCH FLAGS (\\Answered \\Recent)\r\n", res.next)
      assert_equal("* 3 FETCH FLAGS (\\Answered \\Flagged \\Recent)\r\n", res.next)
      assert_equal("* 4 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Recent)\r\n", res.next)
      assert_equal("* 5 FETCH FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Recent)\r\n", res.next)
      assert_equal("T015 OK STORE completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T016 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_uid_store_silent
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        @mail_store.add_msg(@inbox_id, msg_src.next)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end

      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 UID STORE 1 +FLAGS.SILENT (\Answered)
T002 LOGIN foo open_sesame
T003 UID STORE 1 +FLAGS.SILENT (\Answered)
T004 SELECT INBOX
T005 UID STORE 1 +FLAGS.SILENT (\Answered)
T006 UID STORE 1,3 +FLAGS.SILENT (\Flagged)
T007 UID STORE 1,3,5 +FLAGS.SILENT (\Deleted)
T008 UID STORE 1,3,5,7 +FLAGS.SILENT (\Seen)
T009 UID STORE 1,3,5,7,9 +FLAGS.SILENT (\Draft)
T010 UID STORE 1:* FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
T011 UID STORE 1 -FLAGS.SILENT (\Answered)
T012 UID STORE 1,3 -FLAGS.SILENT (\Flagged)
T013 UID STORE 1,3,5 -FLAGS.SILENT (\Deleted)
T014 UID STORE 1,3,5,7 -FLAGS.SILENT (\Seen)
T015 UID STORE 1,3,5,7,9 -FLAGS.SILENT (\Draft)
T016 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("T005 OK STORE completed\r\n", res.next)

      assert_equal("T006 OK STORE completed\r\n", res.next)

      assert_equal("T007 OK STORE completed\r\n", res.next)

      assert_equal("T008 OK STORE completed\r\n", res.next)

      assert_equal("T009 OK STORE completed\r\n", res.next)

      assert_equal("T010 OK STORE completed\r\n", res.next)

      assert_equal("T011 OK STORE completed\r\n", res.next)

      assert_equal("T012 OK STORE completed\r\n", res.next)

      assert_equal("T013 OK STORE completed\r\n", res.next)

      assert_equal("T014 OK STORE completed\r\n", res.next)

      assert_equal("T015 OK STORE completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T016 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_copy
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        msg_id = @mail_store.add_msg(@inbox_id, msg_src.next)
        @mail_store.set_msg_flag(@inbox_id, msg_id, 'flagged', true)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      work_id = @mail_store.add_mbox('WORK')
      assert_equal([], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(0, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'recent'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 COPY 2:4 WORK
T002 LOGIN foo open_sesame
T003 COPY 2:4 WORK
T004 SELECT INBOX
T005 COPY 2:4 WORK
T006 COPY 2:4 WORK
T007 COPY 100 WORK
T008 COPY 1:* nobox
T009 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("T005 OK COPY completed\r\n", res.next)

      assert_equal("T006 OK COPY completed\r\n", res.next)

      assert_equal("T007 OK COPY completed\r\n", res.next)

      assert_match(/^T008 NO \[TRYCREATE\]/, res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T009 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'recent')) # clear by logout.

      assert_equal([ 3, 5, 7 ], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'recent')) # clear by logout.
    end

    def test_command_loop_uid_copy
      msg_src = Enumerator.new{|y|
        s = 'a'
        loop do
          y << s
          s = s.succ
        end
      }

      10.times do
        msg_id = @mail_store.add_msg(@inbox_id, msg_src.next)
        @mail_store.set_msg_flag(@inbox_id, msg_id, 'flagged', true)
      end
      @mail_store.each_msg_id(@inbox_id) do |msg_id|
        if (msg_id % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, msg_id, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'recent'))

      work_id = @mail_store.add_mbox('WORK')
      assert_equal([], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(0, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'recent'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 UID COPY 3,5,7 WORK
T002 LOGIN foo open_sesame
T003 UID COPY 3,5,7 WORK
T004 SELECT INBOX
T005 UID COPY 3,5,7 WORK
T006 UID COPY 3,5,7 WORK
T007 UID COPY 100 WORK
T008 UID COPY 1:* nobox
T009 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", res.next)

      assert_match(/^T001 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^T003 NO /, res.peek)
      assert_no_match(/\[TRYCREATE\]/, res.next)

      res.next while (res.peek =~ /^\* /)
      assert_equal("T004 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_equal("T005 OK COPY completed\r\n", res.next)

      assert_equal("T006 OK COPY completed\r\n", res.next)

      assert_equal("T007 OK COPY completed\r\n", res.next)

      assert_match(/^T008 NO \[TRYCREATE\]/, res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T009 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_id(@inbox_id).to_a)
      assert_equal(5, @mail_store.mbox_msgs(@inbox_id))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'answered'))
      assert_equal(5, @mail_store.mbox_flags(@inbox_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(@inbox_id, 'recent')) # clear by logout.

      assert_equal([ 3, 5, 7 ], @mail_store.each_msg_id(work_id).to_a)
      assert_equal(3, @mail_store.mbox_msgs(work_id))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'answered'))
      assert_equal(3, @mail_store.mbox_flags(work_id, 'flagged'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'deleted'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'seen'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'draft'))
      assert_equal(0, @mail_store.mbox_flags(work_id, 'recent')) # clear by logout.
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
