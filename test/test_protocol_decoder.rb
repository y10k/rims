# -*- coding: utf-8 -*-

require 'logger'
require 'net/imap'
require 'rims'
require 'stringio'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolDecoderTest < Test::Unit::TestCase
    include RIMS::Test::AssertUtility

    UTF8_MBOX_NAME = '~peter/mail/日本語/台北'.freeze
    UTF7_MBOX_NAME = '~peter/mail/&ZeVnLIqe-/&U,BTFw-'.b.freeze

    def encode_utf7(utf8_str)
      Net::IMAP.encode_utf7(utf8_str) # -> utf7_str
    end
    private :encode_utf7

    def decode_utf7(utf7_str)
      Net::IMAP.decode_utf7(utf7_str) # -> utf8_str
    end
    private :decode_utf7

    class IMAPResponseAssertionDSL
      include Test::Unit::Assertions

      def initialize(response_lines, crlf_at_eol: true)
        @lines = response_lines
        @crlf_at_eol = crlf_at_eol
      end

      def fetch_line(peek_next_line: false)
        if (peek_next_line) then
          @lines.peek
        else
          @lines.next
        end
      end
      private :fetch_line

      def skip_while(&cond)
        while (cond.call(@lines.peek))
          @lines.next
        end
        self
      end

      def equal(expected_string, peek_next_line: false)
        expected_string += "\r\n" if (@crlf_at_eol && expected_string !~ /\n\z/)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_equal(expected_string, line)
        self
      end

      def strenc_equal(expected_string, peek_next_line: false)
        expected_string += "\r\n" if (@crlf_at_eol && expected_string !~ /\n\z/)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_equal(expected_string.encoding, line.encoding)
        assert_equal(expected_string, line)
        self
      end

      def match(expected_regexp, peek_next_line: false)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_match(expected_regexp, line)
        assert_match(/\r\n\z/, line) if @crlf_at_eol
        self
      end

      def no_match(expected_regexp, peek_next_line: false)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_not_nil(expected_regexp, line)
        assert_match(/\r\n\z/, line) if @crlf_at_eol
        self
      end

      def equal_lines(expected_multiline_string)
        expected_multiline_string.each_line do |line|
          self.equal(line)
        end
        self
      end
    end

    def assert_imap_response(response_lines, crlf_at_eol: true)
      dsl = IMAPResponseAssertionDSL.new(response_lines, crlf_at_eol: crlf_at_eol)
      yield(dsl)
      assert_raise(StopIteration) { response_lines.next }

      nil
    end
    private :assert_imap_response

    def setup
      @kvs = Hash.new{|h, k| h[k] = {} }
      @kvs_open = proc{|prefix, name| RIMS::Hash_KeyValueStore.new(@kvs["#{prefix}/#{name}"]) }
      @mail_store_pool = RIMS::MailStorePool.new(@kvs_open, @kvs_open, proc{|name| 'test' })
      @mail_store_holder = @mail_store_pool.get('foo')
      @mail_store = @mail_store_holder.mail_store
      @inbox_id = @mail_store.mbox_id('INBOX')
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL
      @passwd = proc{|username, password|username == 'foo' && password == 'open_sesame'}
      @decoder = RIMS::Protocol::Decoder.new(@mail_store_pool, @passwd, @logger)
      @tag = 'T000'
    end

    def reload_mail_store
      @mail_store_pool.put(@mail_store_holder)
      assert(@mail_store_pool.empty?)

      @mail_store_holder = nil
      @mail_store = nil

      begin
        yield
      ensure
        @mail_store_holder = @mail_store_pool.get('foo')
        @mail_store = @mail_store_holder.mail_store
      end
    end
    private :reload_mail_store

    def teardown
      @decoder.cleanup
      @mail_store_pool.put(@mail_store_holder)
      assert(@mail_store_pool.empty?)
      pp @kvs if $DEBUG
    end

    def tag
      @tag.dup
    end
    private :tag

    def next_tag!
      @tag.succ!.dup
    end
    private :next_tag!

    def assert_imap_command(cmd_method_symbol, *cmd_str_args, crlf_at_eol: true, **cmd_opts)
      next_tag!
      if (cmd_opts.empty?) then
        response_lines = @decoder.__send__(cmd_method_symbol, tag, *cmd_str_args).each
      else
        response_lines = @decoder.__send__(cmd_method_symbol, tag, *cmd_str_args, **cmd_opts).each
      end
      assert_imap_response(response_lines, crlf_at_eol: crlf_at_eol) {|assert|
        yield(assert)
      }
      nil
    end
    private :assert_imap_command

    def add_msg(msg_txt, *optional_args, mbox_id: @inbox_id)
      @mail_store.add_msg(mbox_id, msg_txt, *optional_args)
    end
    private :add_msg

    def get_msg_text(uid, mbox_id: @inbox_id)
      @mail_store.msg_text(mbox_id, uid)
    end
    private :get_msg_text

    def get_msg_date(uid, mbox_id: @inbox_id)
      @mail_store.msg_date(mbox_id, uid)
    end
    private :get_msg_date

    def assert_msg_text(*msg_txt_list, mbox_id: @inbox_id)
      assert_equal(msg_txt_list,
                   @mail_store.each_msg_uid(mbox_id).map{|uid|
                     get_msg_text(uid, mbox_id: mbox_id)
                   })
    end
    private :assert_msg_text

    def expunge(*uid_list)
      for uid in uid_list
        set_msg_flag(uid, 'deleted', true)
      end
      @mail_store.expunge_mbox(@inbox_id)
      nil
    end
    private :expunge

    def assert_msg_uid(*uid_list, mbox_id: @inbox_id)
      assert_equal(uid_list, @mail_store.each_msg_uid(mbox_id).to_a)
    end
    private :assert_msg_uid

    def get_msg_flag(uid, flag_name, mbox_id: @inbox_id)
      @mail_store.msg_flag(mbox_id, uid, flag_name)
    end
    private :get_msg_flag

    def set_msg_flag(uid, flag_name, flag_value, mbox_id: @inbox_id)
      @mail_store.set_msg_flag(mbox_id, uid, flag_name, flag_value)
      nil
    end
    private :set_msg_flag

    def set_msg_flags(flag_name, flag_value, *uid_list, mbox_id: @inbox_id)
      for uid in uid_list
        set_msg_flag(uid, flag_name, flag_value, mbox_id: mbox_id)
      end
      nil
    end
    private :set_msg_flags

    def assert_msg_flags(uid, answered: false, flagged: false, deleted: false, seen: false, draft: false, recent: false, mbox_id: @inbox_id)
      [ [ 'answered', answered],
        [ 'flagged', flagged ],
        [ 'deleted', deleted ],
        [ 'seen', seen ],
        [ 'draft', draft ],
        [ 'recent', recent ]
      ].each do |flag_name, flag_value|
        assert_equal([ flag_name, flag_value ],
                     [ flag_name, @mail_store.msg_flag(mbox_id, uid, flag_name) ])
      end
      nil
    end
    private :assert_msg_flags

    def assert_flag_enabled_msgs(flag_name, *uid_list, mbox_id: @inbox_id)
      assert_equal([ flag_name, uid_list ],
                   [ flag_name,
                     @mail_store.each_msg_uid(mbox_id).find_all{|uid|
                       @mail_store.msg_flag(mbox_id, uid, flag_name)
                     }
                   ])
    end
    private :assert_flag_enabled_msgs

    def assert_mbox_flag_num(answered: 0, flagged: 0, deleted: 0, seen: 0, draft: 0, recent: 0, mbox_id: @inbox_id)
      [ [ :answered, answered ],
        [ :flagged, flagged ],
        [ :deleted, deleted ],
        [ :seen, seen ],
        [ :draft, draft ],
        [ :recent, recent ]
      ].each do |flag_sym, flag_num|
        assert_equal([ flag_sym, flag_num ], [ flag_sym, @mail_store.mbox_flag_num(mbox_id, flag_sym.to_s) ])
      end
      nil
    end
    private :assert_mbox_flag_num

    def get_mbox_id_list(*mbox_name_list)
      mbox_name_list.map{|name| @mail_store.mbox_id(name) }
    end
    private :get_mbox_id_list

    def assert_mbox_exists(name)
      assert_not_nil(@mail_store.mbox_id(name))
    end
    private :assert_mbox_exists

    def assert_mbox_not_exists(name)
      assert_nil(@mail_store.mbox_id(name))
    end
    private :assert_mbox_not_exists

    def mail_store_add_mail_simple
      @simple_mail = RIMS::RFC822::Message.new(<<-'EOF')
To: foo@nonet.org
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
      EOF

      @mail_store.add_msg(@inbox_id, @simple_mail.raw_source, Time.parse('2013-11-08 06:47:50 +0900'))
    end
    private :mail_store_add_mail_simple

    def mail_store_add_mail_multipart
      @mpart_mail = RIMS::RFC822::Message.new(<<-'EOF')
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

      @mail_store.add_msg(@inbox_id, @mpart_mail.raw_source, Time.parse('2013-11-08 19:31:03 +0900'))
    end
    private :mail_store_add_mail_simple

    def make_string_source(start_string)
      Enumerator.new{|y|
        s = start_string.dup
        loop do
          y << s
          s = s.succ
        end
      }
    end
    private :make_string_source

    def test_capability
      assert_imap_command(:capability) {|assert|
        assert.equal('* CAPABILITY IMAP4rev1')
        assert.equal("#{tag} OK CAPABILITY completed")
      }
    end

    def test_logout
      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_login
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'detarame') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
    end

    def test_select
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    , 2   )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  ,     )
      assert_mbox_flag_num(seen: 1)
    end

    def test_select_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:select, UTF7_MBOX_NAME) {|assert|
        assert.equal('* 0 EXISTS')
        assert.equal('* 0 RECENT')
        assert.equal('* OK [UNSEEN 0]')
        assert.equal("* OK [UIDVALIDITY #{utf8_name_mbox_id}]")
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_examine
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)
    end

    def test_examine_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:examine, UTF7_MBOX_NAME) {|assert|
        assert.equal('* 0 EXISTS')
        assert.equal('* 0 RECENT')
        assert.equal('* OK [UNSEEN 0]')
        assert.equal("* OK [UIDVALIDITY #{utf8_name_mbox_id}]")
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_create
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:create, 'foo') {|assert|
        assert.match(/^T001 NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_nil(@mail_store.mbox_id('foo'))

      assert_imap_command(:create, 'foo') {|assert|
        assert.equal("#{tag} OK CREATE completed")
      }

      assert_not_nil(@mail_store.mbox_id('foo'))

      assert_imap_command(:create, 'inbox') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_create_utf7_mbox_name
      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_nil(@mail_store.mbox_id(UTF8_MBOX_NAME))

      assert_imap_command(:create, UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK CREATE completed")
      }

      assert_not_nil(@mail_store.mbox_id(UTF8_MBOX_NAME))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_delete
      @mail_store.add_mbox('foo')

      assert_equal(false, @decoder.auth?)

      assert_mbox_exists('foo')
      assert_imap_command(:delete, 'foo') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_mbox_exists('foo')

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_mbox_exists('foo')
      assert_imap_command(:delete, 'foo') {|assert|
        assert.equal("#{tag} OK DELETE completed")
      }
      assert_mbox_not_exists('foo')

      assert_mbox_not_exists('bar')
      assert_imap_command(:delete, 'bar') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_mbox_not_exists('bar')

      assert_mbox_exists('INBOX')
      assert_imap_command(:delete, 'inbox') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_mbox_exists('INBOX')

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_delete_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_mbox_exists(UTF8_MBOX_NAME)
      assert_imap_command(:delete, UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK DELETE completed")
      }
      assert_mbox_not_exists(UTF8_MBOX_NAME)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_rename
      mbox_id = @mail_store.add_mbox('foo')

      assert_equal(false, @decoder.auth?)

      assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))
      assert_imap_command(:rename, 'foo', 'bar') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))
      assert_imap_command(:rename, 'foo', 'bar') {|assert|
        assert.equal("#{tag} OK RENAME completed")
      }
      assert_equal([ nil, mbox_id ], get_mbox_id_list('foo', 'bar'))

      assert_imap_command(:rename, 'nobox', 'baz') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal([ @inbox_id, nil ], get_mbox_id_list('INBOX', 'baz'))
      assert_imap_command(:rename, 'INBOX', 'baz') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_equal([ @inbox_id, nil ], get_mbox_id_list('INBOX', 'baz'))

      assert_equal([ mbox_id, @inbox_id ], get_mbox_id_list('bar', 'INBOX'))
      assert_imap_command(:rename, 'bar', 'inbox') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_equal([ mbox_id, @inbox_id ], get_mbox_id_list('bar', 'INBOX'))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_rename_utf7_mbox_name
      mbox_id = @mail_store.add_mbox('foo')

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', UTF8_MBOX_NAME))
      assert_imap_command(:rename, 'foo', UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK RENAME completed")
      }
      assert_equal([ nil, mbox_id ], get_mbox_id_list('foo', UTF8_MBOX_NAME))

      assert_equal([ mbox_id, nil ], get_mbox_id_list(UTF8_MBOX_NAME, 'bar'))
      assert_imap_command(:rename, UTF7_MBOX_NAME, 'bar') {|assert|
        assert.equal("#{tag} OK RENAME completed")
      }
      assert_equal([ nil, mbox_id ], get_mbox_id_list(UTF8_MBOX_NAME, 'bar'))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_subscribe_dummy
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:subscribe, 'INBOX') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:subscribe, 'INBOX') {|assert|
        assert.equal("#{tag} OK SUBSCRIBE completed")
      }

      assert_imap_command(:subscribe, 'NOBOX') {|assert|
        assert.equal("#{tag} NO not found a mailbox")
      }
    end

    def test_subscribe_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:subscribe, UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK SUBSCRIBE completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_unsubscribe_dummy
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:unsubscribe, 'INBOX') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:unsubscribe, 'INBOX') {|assert|
        assert.equal("#{tag} NO not implemented subscribe/unsbscribe command")
      }
    end

    def test_list
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:list, '', '') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:list, '', '') {|assert|
        assert.equal('* LIST (\Noselect) NIL ""')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list, '', 'nobox') {|assert|
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list, '', '*') {|assert|
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "INBOX"')
        assert.equal("#{tag} OK LIST completed")
      }

      add_msg('')

      assert_imap_command(:list, '', '*') {|assert|
        assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        assert.equal("#{tag} OK LIST completed")
      }

      @mail_store.add_mbox('foo')

      assert_imap_command(:list, '', '*') {|assert|
        assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list, '', 'f*') {|assert|
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list, 'IN', '*') {|assert|
        assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_list_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:list,
                          encode_utf7(UTF8_MBOX_NAME[0..6]),
                          '*' + encode_utf7(UTF8_MBOX_NAME[12..14]) + '*') {|assert|
        assert.equal(%Q'* LIST (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list,
                          encode_utf7(UTF8_MBOX_NAME[0..13]),
                          '*' + encode_utf7(UTF8_MBOX_NAME[16]) + '*') {|assert|
        assert.equal(%Q'* LIST (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_status
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:status, 'nobox', [ :group, 'MESSAGES' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:status, 'nobox', [ :group, 'MESSAGES' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES' ]) {|assert|
        assert.equal('* STATUS "INBOX" (MESSAGES 0)')
        assert.equal("#{tag} OK STATUS completed")
      }

      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 0 RECENT 0 UIDNEXT 1 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
        assert.equal("#{tag} OK STATUS completed")
      }

      add_msg('')
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 1 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
        assert.equal("#{tag} OK STATUS completed")
      }

      set_msg_flag(1, 'recent', false)
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
        assert.equal("#{tag} OK STATUS completed")
      }

      set_msg_flag(1, 'seen', true)
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
        assert.equal("#{tag} OK STATUS completed")
      }

      add_msg('')
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 2 RECENT 1 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
        assert.equal("#{tag} OK STATUS completed")
      }

      expunge(2)
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
        assert.equal("#{tag} OK STATUS completed")
      }

      assert_imap_command(:status, 'INBOX', 'MESSAGES') {|assert|
        assert.match(/^#{tag} BAD /)
      }

      assert_imap_command(:status, 'INBOX', [ :group, 'DETARAME' ]) {|assert|
        assert.match(/^#{tag} BAD /)
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_status_utf7_mbox_name
      mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:status, UTF7_MBOX_NAME, [ :group, 'UIDVALIDITY', 'MESSAGES', 'RECENT', 'UNSEEN' ]) {|assert|
        assert.equal(%Q'* STATUS "#{UTF7_MBOX_NAME}" (UIDVALIDITY #{mbox_id} MESSAGES 0 RECENT 0 UNSEEN 0)')
        assert.equal("#{tag} OK STATUS completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_lsub_dummy
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:lsub, '', '*') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:lsub, '', '*') {|assert|
        assert.equal('* LSUB (\Noinferiors \Unmarked) NIL "INBOX"')
        assert.equal("#{tag} OK LSUB completed")
      }
    end

    def test_lsub_dummy_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:lsub,
                          encode_utf7(UTF8_MBOX_NAME[0..6]),
                          '*' + encode_utf7(UTF8_MBOX_NAME[12..14]) + '*') {|assert|
        assert.equal(%Q'* LSUB (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
        assert.equal("#{tag} OK LSUB completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_append
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:append, 'INBOX', 'a') {|assert|
        assert.match(/^#{tag} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }
      assert_msg_uid()

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:append, 'INBOX', 'a') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1)
      assert_equal('a', get_msg_text(1))
      assert_msg_flags(1, recent: true)

      assert_imap_command(:append, 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], 'b') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1, 2)
      assert_equal('b', get_msg_text(2))
      assert_msg_flags(2, answered: true, flagged: true, deleted: true, seen: true, draft: true, recent: true)

      assert_imap_command(:append, 'INBOX', '19-Nov-1975 12:34:56 +0900', 'c') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1, 2, 3)
      assert_equal('c', get_msg_text(3))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(3))
      assert_msg_flags(3, recent: true)

      assert_imap_command(:append, 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], '19-Nov-1975 12:34:56 +0900', 'd') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1, 2, 3, 4)
      assert_equal('d', get_msg_text(4))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(4))
      assert_msg_flags(4, answered: true, flagged: true, deleted: true, seen: true, draft: true, recent: true)

      assert_imap_command(:append, 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], '19-Nov-1975 12:34:56 +0900', :NIL, 'x') {|assert|
        assert.match(/^#{tag} BAD /)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:append, 'INBOX', '19-Nov-1975 12:34:56 +0900', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], 'x') {|assert|
        assert.match(/^#{tag} BAD /)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:append, 'INBOX', [ :group, '\Recent' ], 'x') {|assert|
        assert.match(/^#{tag} BAD /)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:append, 'INBOX', 'bad date-time', 'x') {|assert|
        assert.match(/^#{tag} BAD /)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:append, 'nobox', 'x') {|assert|
        assert.match(/^#{tag} NO \[TRYCREATE\]/)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_append_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_msg_uid(mbox_id: utf8_name_mbox_id)
      assert_imap_command(:append, UTF7_MBOX_NAME, 'Hello world.') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1, mbox_id: utf8_name_mbox_id)
      assert_equal('Hello world.', get_msg_text(1, mbox_id: utf8_name_mbox_id))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_check
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:check) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:check) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* /}
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:check) {|assert|
        assert.equal("#{tag} OK CHECK completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_close
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.equal("#{tag} OK CLOSE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    , 2   )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  ,     )
      assert_mbox_flag_num(seen: 1)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
    end

    def test_close_read_only
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.equal("#{tag} OK CLOSE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
    end

    def test_expunge
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.expunge('T001').each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.expunge('T003').each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.expunge('T005').each
      assert_imap_response(res) {|a|
        a.equal('T005 OK EXPUNGE completed')
      }

      @mail_store.add_msg(@inbox_id, 'a')
      @mail_store.add_msg(@inbox_id, 'b')
      @mail_store.add_msg(@inbox_id, 'c')

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 3, 0, 0, 0, 0, 0 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      res = @decoder.expunge('T006').each
      assert_imap_response(res) {|a|
        a.equal('T006 OK EXPUNGE completed')
      }

      for name in %w[ answered flagged seen draft ]
        @mail_store.set_msg_flag(@inbox_id, 2, name, true)
        @mail_store.set_msg_flag(@inbox_id, 3, name, true)
      end
      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 3, 2, 2, 2, 2, 1 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([    2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([    2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([    2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([    2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([    2    ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      res = @decoder.expunge('T007').each
      assert_imap_response(res) {|a|
        a.equal('* 2 EXPUNGE')
        a.equal('T007 OK EXPUNGE completed')
      }

      assert_equal(2, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 2, 1, 1, 1, 1, 0 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([      ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.set_msg_flag(@inbox_id, 3, 'deleted', true)

      assert_equal(2, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 2, 1, 1, 1, 1, 2 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      res = @decoder.expunge('T008').each
      assert_imap_response(res) {|a|
        a.equal('* 1 EXPUNGE')
        a.equal('* 2 EXPUNGE')
        a.equal('T008 OK EXPUNGE completed')
      }

      assert_equal(0, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 0 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })

      res = @decoder.logout('T009').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T009 OK LOGOUT completed')
      }
    end

    def test_expunge_read_only
      @mail_store.add_msg(@inbox_id, 'a')
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)

      assert_equal(1, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ false, false, true, false, false, true ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.msg_flag(@inbox_id, 1, name)
                   })

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.expunge('T001').each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.expunge('T003').each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      res = @decoder.examine('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-ONLY] EXAMINE completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.expunge('T005').each
      assert_imap_response(res) {|a|
        a.match(/^T005 NO /)
      }

      assert_equal(1, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ false, false, true, false, false, true ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.msg_flag(@inbox_id, 1, name)
                   })

      res = @decoder.logout('T006').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T006 OK LOGOUT completed')
      }
    end

    def test_search
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.search('T001', 'ALL').each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.search('T003', 'ALL').each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.search('T005', 'ALL').each
      assert_imap_response(res, crlf_at_eol: false) {|a|
        a.equal('* SEARCH').equal("\r\n")
        a.equal("T005 OK SEARCH completed\r\n")
      }

      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: alice\r\n\r\napple")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: alice\r\n\r\nbnana")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\norange")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\nmelon")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\npineapple")
      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)
      @mail_store.set_msg_flag(@inbox_id, 4, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5 ], @mail_store.each_msg_uid(@inbox_id).to_a)

      res = @decoder.search('T006', 'ALL').each
      assert_imap_response(res, crlf_at_eol: false) {|a|
        a.equal('* SEARCH').equal(' 1').equal(' 2').equal(' 3').equal("\r\n")
        a.equal("T006 OK SEARCH completed\r\n")
      }

      res = @decoder.search('T007', 'ALL', uid: true).each
      assert_imap_response(res, crlf_at_eol: false) {|a|
        a.equal('* SEARCH').equal(' 1').equal(' 3').equal(' 5').equal("\r\n")
        a.equal("T007 OK SEARCH completed\r\n")
      }

      res = @decoder.search('T008', 'OR', 'FROM', 'alice', 'FROM', 'bob', 'BODY', 'apple').each
      assert_imap_response(res, crlf_at_eol: false) {|a|
        a.equal('* SEARCH').equal(' 1').equal(' 3').equal("\r\n")
        a.equal("T008 OK SEARCH completed\r\n")
      }

      res = @decoder.search('T009', 'OR', 'FROM', 'alice', 'FROM', 'bob', 'BODY', 'apple', uid: true).each
      assert_imap_response(res, crlf_at_eol: false) {|a|
        a.equal('* SEARCH').equal(' 1').equal(' 5').equal("\r\n")
        a.equal("T009 OK SEARCH completed\r\n")
      }

      res = @decoder.logout('T010').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T010 OK LOGOUT completed')
      }
    end

    def test_fetch
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      mail_store_add_mail_simple
      mail_store_add_mail_multipart

      assert_equal([ 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.fetch('T001', '1:*', 'FAST').each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.fetch('T003', '1:*', 'FAST').each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.fetch('T005', '1:*', 'FAST').each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 1 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-Nov-2013 06:47:50 +0900\" RFC822.SIZE #{@simple_mail.raw_source.bytesize})".b)
        a.strenc_equal("* 2 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-Nov-2013 19:31:03 +0900\" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})".b)
        a.equal('T005 OK FETCH completed')
      }

      res = @decoder.fetch('T006', '1:*', [ :group, 'FAST' ]).each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 1 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-Nov-2013 06:47:50 +0900\" RFC822.SIZE #{@simple_mail.raw_source.bytesize})".b)
        a.strenc_equal("* 2 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-Nov-2013 19:31:03 +0900\" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})".b)
        a.equal('T006 OK FETCH completed')
      }

      res = @decoder.fetch('T007', '1:*', [ :group, 'FLAGS', 'RFC822.HEADER', 'UID' ]).each
      assert_imap_response(res) {|a|
        s = @simple_mail.header.raw_source
        s += "\r\n" unless (s =~ /\r?\n\z/)
        s += "\r\n" unless (s =~ /\r?\n\r?\n\z/)
        a.strenc_equal("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n#{s} UID 2)".b)

        s = @mpart_mail.header.raw_source
        s += "\r\n" unless (s =~ /\r?\n\z/)
        s += "\r\n" unless (s =~ /\r?\n\r?\n\z/)
        a.strenc_equal("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n#{s} UID 3)".b)

        a.equal('T007 OK FETCH completed')
      }

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.fetch('T008', '1', 'RFC822').each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 1 FETCH (FLAGS (\\Seen \\Recent) RFC822 {#{@simple_mail.raw_source.bytesize}}\r\n#{@simple_mail.raw_source})".b)
        a.equal('T008 OK FETCH completed')
      }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      body = RIMS::Protocol.body(symbol: 'BODY', option: 'PEEK', section: '1', section_list: [ '1' ])
      res = @decoder.fetch('T009', '2', [ :body, body ]).each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 2 FETCH (BODY[1] \"#{@mpart_mail.parts[0].body.raw_source}\")".b)
        a.equal('T009 OK FETCH completed')
      }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.fetch('T010', '2', 'RFC822', uid: true).each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 1 FETCH (UID 2 RFC822 {#{@simple_mail.raw_source.bytesize}}\r\n#{@simple_mail.raw_source})".b)
        a.equal('T010 OK FETCH completed')
      }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      body = RIMS::Protocol.body(symbol: 'BODY', option: 'PEEK', section: '1', section_list: [ '1' ])
      res = @decoder.fetch('T011', '3', [ :group, 'UID', [ :body, body ] ], uid: true).each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 2 FETCH (UID 3 BODY[1] \"#{@mpart_mail.parts[0].body.raw_source}\")".b)
        a.equal('T011 OK FETCH completed')
      }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.logout('T012').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T012 OK LOGOUT completed')
      }
    end

    def test_fetch_read_only
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      mail_store_add_mail_simple
      mail_store_add_mail_multipart

      assert_equal([ 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.fetch('T001', '1:*', 'FAST').each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.fetch('T003', '1:*', 'FAST').each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      res = @decoder.examine('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-ONLY] EXAMINE completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.fetch('T005', '1:*', 'FAST').each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 1 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-Nov-2013 06:47:50 +0900\" RFC822.SIZE #{@simple_mail.raw_source.bytesize})".b)
        a.strenc_equal("* 2 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-Nov-2013 19:31:03 +0900\" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})".b)
        a.equal('T005 OK FETCH completed')
      }

      res = @decoder.fetch('T006', '1:*', [ :group, 'FAST' ]).each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 1 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-Nov-2013 06:47:50 +0900\" RFC822.SIZE #{@simple_mail.raw_source.bytesize})".b)
        a.strenc_equal("* 2 FETCH (FLAGS (\\Recent) INTERNALDATE \"08-Nov-2013 19:31:03 +0900\" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})".b)
        a.equal('T006 OK FETCH completed')
      }

      res = @decoder.fetch('T007', '1:*', [ :group, 'FLAGS', 'RFC822.HEADER', 'UID' ]).each
      assert_imap_response(res) {|a|
        s = @simple_mail.header.raw_source
        s += "\r\n" unless (s =~ /\r?\n\z/)
        s += "\r\n" unless (s =~ /\r?\n\r?\n\z/)
        a.strenc_equal("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n#{s} UID 2)".b)

        s = @mpart_mail.header.raw_source
        s += "\r\n" unless (s =~ /\r?\n\z/)
        s += "\r\n" unless (s =~ /\r?\n\r?\n\z/)
        a.strenc_equal("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n#{s} UID 3)".b)

        a.equal('T007 OK FETCH completed')
      }

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.fetch('T008', '1', 'RFC822').each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 1 FETCH (RFC822 {#{@simple_mail.raw_source.bytesize}}\r\n#{@simple_mail.raw_source})".b)
        a.equal('T008 OK FETCH completed')
      }

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      body = RIMS::Protocol.body(symbol: 'BODY', option: 'PEEK', section: '1', section_list: [ '1' ])
      res = @decoder.fetch('T009', '2', [ :body, body ]).each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 2 FETCH (BODY[1] \"#{@mpart_mail.parts[0].body.raw_source}\")".b)
        a.equal('T009 OK FETCH completed')
      }

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.fetch('T010', '2', 'RFC822', uid: true).each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 1 FETCH (UID 2 RFC822 {#{@simple_mail.raw_source.bytesize}}\r\n#{@simple_mail.raw_source})".b)
        a.equal('T010 OK FETCH completed')
      }

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      body = RIMS::Protocol.body(symbol: 'BODY', option: 'PEEK', section: '1', section_list: [ '1' ])
      res = @decoder.fetch('T011', '3', [ :group, 'UID', [ :body, body ] ], uid: true).each
      assert_imap_response(res) {|a|
        a.strenc_equal("* 2 FETCH (UID 3 BODY[1] \"#{@mpart_mail.parts[0].body.raw_source}\")".b)
        a.equal('T011 OK FETCH completed')
      }

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      res = @decoder.logout('T012').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T012 OK LOGOUT completed')
      }
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
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS', [ :group, '\Answered' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS', [ :group, '\Answered' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS', [ :group, '\Answered' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Recent)')
        a.equal('T005 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T006', '1:2', '+FLAGS', [ :group, '\Flagged' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Recent)')
        a.equal('T006 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T007', '1:3', '+FLAGS', [ :group, '\Deleted' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Recent)')
        a.equal('T007 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T008', '1:4', '+FLAGS', [ :group, '\Seen' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)')
        a.equal('* 4 FETCH FLAGS (\Seen \Recent)')
        a.equal('T008 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 4, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7    ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T009', '1:5', '+FLAGS', [ :group, '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)')
        a.equal('* 5 FETCH FLAGS (\Draft \Recent)')
        a.equal('T009 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 4, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7    ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T010', '1:*', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('T010 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 5, 5, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T011', '1', '-FLAGS', [ :group, '\Answered' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('T011 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 5, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T012', '1:2', '-FLAGS', [ :group, '\Flagged' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)')
        a.equal('T012 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T013', '1:3', '-FLAGS', [ :group, '\Deleted' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)')
        a.equal('T013 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T014', '1:4', '-FLAGS', [ :group, '\Seen' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)')
        a.equal('T014 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 1, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([             9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T015', '1:5', '-FLAGS', [ :group, '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        a.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        a.equal('T015 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 1, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([             9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.logout('T016').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T016 OK LOGOUT completed')
      }
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
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS.SILENT', [ :group, '\Answered' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS.SILENT', [ :group, '\Answered' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS.SILENT', [ :group, '\Answered' ]).each
      assert_imap_response(res) {|a|
        a.equal('T005 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T006', '1:2', '+FLAGS.SILENT', [ :group, '\Flagged' ]).each
      assert_imap_response(res) {|a|
        a.equal('T006 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T007', '1:3', '+FLAGS.SILENT', [ :group, '\Deleted' ]).each
      assert_imap_response(res) {|a|
        a.equal('T007 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T008', '1:4', '+FLAGS.SILENT', [ :group, '\Seen' ]).each
      assert_imap_response(res) {|a|
        a.equal('T008 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 4, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7    ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T009', '1:5', '+FLAGS.SILENT', [ :group, '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.equal('T009 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 4, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7    ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T010', '1:*', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.equal('T010 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 5, 5, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T011', '1', '-FLAGS.SILENT', [ :group, '\Answered' ]).each
      assert_imap_response(res) {|a|
        a.equal('T011 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 5, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T012', '1:2', '-FLAGS.SILENT', [ :group, '\Flagged' ]).each
      assert_imap_response(res) {|a|
        a.equal('T012 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T013', '1:3', '-FLAGS.SILENT', [ :group, '\Deleted' ]).each
      assert_imap_response(res) {|a|
        a.equal('T013 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T014', '1:4', '-FLAGS.SILENT', [ :group, '\Seen' ]).each
      assert_imap_response(res) {|a|
        a.equal('T014 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 1, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([             9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T015', '1:5', '-FLAGS.SILENT', [ :group, '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.equal('T015 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 1, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([             9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.logout('T016').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T016 OK LOGOUT completed')
      }
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
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS', [ :group, '\Answered' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS', [ :group, '\Answered' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS', [ :group, '\Answered' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Recent)')
        a.equal('T005 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T006', '1,3', '+FLAGS', [ :group, '\Flagged' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Recent)')
        a.equal('T006 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T007', '1,3,5', '+FLAGS', [ :group, '\Deleted' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Recent)')
        a.equal('T007 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T008', '1,3,5,7', '+FLAGS', [ :group, '\Seen' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)')
        a.equal('* 4 FETCH FLAGS (\Seen \Recent)')
        a.equal('T008 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 4, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7    ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T009', '1,3,5,7,9', '+FLAGS', [ :group, '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)')
        a.equal('* 5 FETCH FLAGS (\Draft \Recent)')
        a.equal('T009 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 4, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7    ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T010', '1:*', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('T010 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 5, 5, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T011', '1', '-FLAGS', [ :group, '\Answered' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('T011 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 5, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T012', '1,3', '-FLAGS', [ :group, '\Flagged' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)')
        a.equal('T012 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T013', '1,3,5', '-FLAGS', [ :group, '\Deleted' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)')
        a.equal('T013 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T014', '1,3,5,7', '-FLAGS', [ :group, '\Seen' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)')
        a.equal('T014 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 1, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([             9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T015', '1,3,5,7,9', '-FLAGS', [ :group, '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('* 1 FETCH FLAGS (\Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        a.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        a.equal('T015 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 1, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([             9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.logout('T016').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T016 OK LOGOUT completed')
      }
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
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T005 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T006', '1,3', '+FLAGS.SILENT', [ :group, '\Flagged' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T006 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T007', '1,3,5', '+FLAGS.SILENT', [ :group, '\Deleted' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T007 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T008', '1,3,5,7', '+FLAGS.SILENT', [ :group, '\Seen' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T008 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 4, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7    ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T009', '1,3,5,7,9', '+FLAGS.SILENT', [ :group, '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T009 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 2, 3, 4, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1             ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3          ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5       ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7    ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T010', '1:*', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T010 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 5, 5, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T011', '1', '-FLAGS.SILENT', [ :group, '\Answered' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T011 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 5, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T012', '1,3', '-FLAGS.SILENT', [ :group, '\Flagged' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T012 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 5, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T013', '1,3,5', '-FLAGS.SILENT', [ :group, '\Deleted' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T013 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 5, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T014', '1,3,5,7', '-FLAGS.SILENT', [ :group, '\Seen' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T014 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 1, 5, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([             9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.store('T015', '1,3,5,7,9', '-FLAGS.SILENT', [ :group, '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T015 OK STORE completed')
      }

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 4, 3, 2, 1, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([          7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([             9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      res = @decoder.logout('T016').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T016 OK LOGOUT completed')
      }
    end

    def test_store_read_only
      @mail_store.add_msg(@inbox_id, '')

      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ false, false, false, false, false, true ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.msg_flag(@inbox_id, 1, name)
                   })

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T001', '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /)
      }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.store('T003', '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /)
      }

      res = @decoder.examine('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-ONLY] EXAMINE completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.store('T005', '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T005 NO /)
      }

      res = @decoder.store('T006', '1', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted',  '\Seen','\Draft' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T006 NO /)
      }

      res = @decoder.store('T007', '1', '-FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T007 NO /)
      }

      res = @decoder.store('T008', '1', '+FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T008 NO /)
      }

      res = @decoder.store('T009', '1', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T009 NO /)
      }

      res = @decoder.store('T010', '1', '-FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]).each
      assert_imap_response(res) {|a|
        a.match(/^T010 NO /)
      }

      res = @decoder.store('T011', '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T011 NO /)
      }

      res = @decoder.store('T012', '1', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T012 NO /)
      }

      res = @decoder.store('T013', '1', '-FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T013 NO /)
      }

      res = @decoder.store('T014', '1', '+FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T014 NO /)
      }

      res = @decoder.store('T015', '1', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T015 NO /)
      }

      res = @decoder.store('T016', '1', '-FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T016 NO /)
      }

      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ false, false, false, false, false, true ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.msg_flag(@inbox_id, 1, name)
                   })

      res = @decoder.logout('T017').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T017 OK LOGOUT completed')
      }
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
        uid = @mail_store.add_msg(@inbox_id, msg_src.next)
        @mail_store.set_msg_flag(@inbox_id, uid, 'flagged', true)
      end
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      work_id = @mail_store.add_mbox('WORK')

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(0, @mail_store.mbox_msg_num(work_id))
      assert_equal([], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.copy('T001', '2:4', 'WORK').each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.copy('T003', '2:4', 'WORK').each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(0, @mail_store.mbox_msg_num(work_id))
      assert_equal([], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal(0, @mail_store.mbox_flag_num(work_id, 'recent'))

      res = @decoder.copy('T005', '2:4', 'WORK').each
      assert_imap_response(res) {|a|
        a.equal('T005 OK COPY completed')
      }

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(3, @mail_store.mbox_msg_num(work_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 3, 0, 0, 0, 3 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'answered') })
      assert_equal([ 1, 2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'flagged') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'deleted') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'draft') })
      assert_equal([ 1, 2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'recent') })

      # duplicted message copy
      res = @decoder.copy('T006', '2:4', 'WORK').each
      assert_imap_response(res) {|a|
        a.equal('T006 OK COPY completed')
      }

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(6, @mail_store.mbox_msg_num(work_id))
      assert_equal([ 1, 2, 3, 4, 5, 6 ], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 6, 0, 0, 0, 6 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'answered') })
      assert_equal([ 1, 2, 3, 4, 5, 6 ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'flagged') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'deleted') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'seen') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'draft') })
      assert_equal([ 1, 2, 3, 4, 5, 6 ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'recent') })

      # copy of empty messge set
      res = @decoder.copy('T007', '100', 'WORK').each
      assert_imap_response(res) {|a|
        a.equal('T007 OK COPY completed')
      }

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(6, @mail_store.mbox_msg_num(work_id))
      assert_equal([ 1, 2, 3, 4, 5, 6 ], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 6, 0, 0, 0, 6 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'answered') })
      assert_equal([ 1, 2, 3, 4, 5, 6 ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'flagged') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'deleted') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'seen') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'draft') })
      assert_equal([ 1, 2, 3, 4, 5, 6 ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'recent') })

      res = @decoder.copy('T008', '1:*', 'nobox').each
      assert_imap_response(res) {|a|
        a.match(/^T008 NO \[TRYCREATE\]/)
      }

      res = @decoder.logout('T009').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T009 OK LOGOUT completed')
      }
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
        uid = @mail_store.add_msg(@inbox_id, msg_src.next)
        @mail_store.set_msg_flag(@inbox_id, uid, 'flagged', true)
      end
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      work_id = @mail_store.add_mbox('WORK')

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(0, @mail_store.mbox_msg_num(work_id))
      assert_equal([], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.copy('T001', '3,5,7', 'WORK', uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T001 NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.copy('T003', '3,5,7', 'WORK', uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T003 NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(0, @mail_store.mbox_msg_num(work_id))
      assert_equal([], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal(0, @mail_store.mbox_flag_num(work_id, 'recent'))

      res = @decoder.copy('T005', '3,5,7', 'WORK', uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T005 OK COPY completed')
      }

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(3, @mail_store.mbox_msg_num(work_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 3, 0, 0, 0, 3 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'answered') })
      assert_equal([ 1, 2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'flagged') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'deleted') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'draft') })
      assert_equal([ 1, 2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'recent') })

      # duplicted message copy
      res = @decoder.copy('T006', '3,5,7', 'WORK', uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T006 OK COPY completed')
      }

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      # copy of empty messge set
      res = @decoder.copy('T007', '100', 'WORK', uid: true).each
      assert_imap_response(res) {|a|
        a.equal('T007 OK COPY completed')
      }

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(6, @mail_store.mbox_msg_num(work_id))
      assert_equal([ 1, 2, 3, 4, 5, 6 ], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 6, 0, 0, 0, 6 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'answered') })
      assert_equal([ 1, 2, 3, 4, 5, 6 ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'flagged') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'deleted') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'seen') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'draft') })
      assert_equal([ 1, 2, 3, 4, 5, 6 ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'recent') })

      res = @decoder.copy('T008', '1:*', 'nobox', uid: true).each
      assert_imap_response(res) {|a|
        a.match(/^T008 NO \[TRYCREATE\]/)
      }

      res = @decoder.logout('T009').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T009 OK LOGOUT completed')
      }
    end

    def test_copy_utf7_mbox_name
      @mail_store.add_msg(@inbox_id, 'Hello world.')
      mbox_id = @mail_store.add_mbox('~peter/mail/日本語/台北')

      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([], @mail_store.each_msg_uid(mbox_id).to_a)

      res = @decoder.login('T001', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T001 OK LOGIN completed')
      }

      res = @decoder.select('T002', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T002 OK [READ-WRITE] SELECT completed')
      }

      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([], @mail_store.each_msg_uid(mbox_id).to_a)

      res = @decoder.copy('T003', '1', '~peter/mail/&ZeVnLIqe-/&U,BTFw-').each
      assert_imap_response(res) {|a|
        a.equal('T003 OK COPY completed')
      }

      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1 ], @mail_store.each_msg_uid(mbox_id).to_a)
      assert_equal('Hello world.', @mail_store.msg_text(mbox_id, 1))

      res = @decoder.logout('T004').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T004 OK LOGOUT completed')
      }
    end

    def test_noop
      @mail_store.add_msg(@inbox_id, '')

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.noop('T001').each
      assert_imap_response(res) {|a|
        a.equal('T001 OK NOOP completed')
      }

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.equal('T002 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.noop('T003').each
      assert_imap_response(res) {|a|
        a.equal('T003 OK NOOP completed')
      }

      res = @decoder.select('T004', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* /}
        a.equal('T004 OK [READ-WRITE] SELECT completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.noop('T005').each
      assert_imap_response(res) {|a|
        a.equal('* 1 EXISTS')
        a.equal('* 1 RECENTS')
        a.equal('T005 OK NOOP completed')
      }

      res = @decoder.close('T006').each
      assert_imap_response(res) {|a|
        a.equal('T006 OK CLOSE completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.noop('T007').each
      assert_imap_response(res) {|a|
        a.equal('T007 OK NOOP completed')
      }

      res = @decoder.examine('T008', 'INBOX').each
      assert_imap_response(res) {|a|
        a.skip_while{|line| line =~ /^\* /}
        a.equal('T008 OK [READ-ONLY] EXAMINE completed')
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.noop('T009').each
      assert_imap_response(res) {|a|
        a.equal('* 1 EXISTS')
        a.equal('* 0 RECENTS')
        a.equal('T009 OK NOOP completed')
      }

      res = @decoder.logout('T010').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T010 OK LOGOUT completed')
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
    end

    def test_db_recovery
      @mail_store_pool.put(@mail_store_holder)
      assert(@mail_store_pool.empty?)
      meta_db = RIMS::DB::Meta.new(RIMS::Hash_KeyValueStore.new(@kvs['test/meta']))
      meta_db.dirty = true
      meta_db.close
      @mail_store_holder = @mail_store_pool.get('foo')
      @mail_store = @mail_store_holder.mail_store

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T001', 'foo', 'open_sesame').each
      assert_imap_response(res) {|a|
        a.match(/^\* OK \[ALERT\] recovery/)
        a.equal('T001 OK LOGIN completed')
      }

      assert_equal(true, @decoder.auth?)

      res = @decoder.logout('T002').each
      assert_imap_response(res) {|a|
        a.match(/^\* BYE /)
        a.equal('T002 OK LOGOUT completed')
      }

      assert_equal(false, @decoder.auth?)
    end

    def test_command_loop_empty
      output = StringIO.new('', 'w')
      RIMS::Protocol::Decoder.repl(@decoder, StringIO.new(''.b, 'r'), output, @logger)
      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", output.string)

      output = StringIO.new('', 'w')
      RIMS::Protocol::Decoder.repl(@decoder, StringIO.new("\n\t\n \r\n ".b, 'r'), output, @logger)
      assert_equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.\r\n", output.string)
    end

    def test_command_loop_capability
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 CAPABILITY
T002 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('* CAPABILITY IMAP4rev1')
        a.equal('T001 OK CAPABILITY completed')
        a.match(/^\* BYE /)
        a.equal('T002 OK LOGOUT completed')
      }
    end

    def test_command_loop_login
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo detarame
T002 LOGIN foo open_sesame
T003 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.match('T002 OK LOGIN completed')
        a.match(/^\* BYE /)
        a.equal('T003 OK LOGOUT completed')
      }
    end

    def test_command_loop_select
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 2, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 2, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 2, 0, 1 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([       3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 2    ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1       ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 SELECT INBOX
T002 LOGIN foo open_sesame
T003 SELECT INBOX
T004 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.equal('* 3 EXISTS')
        a.equal('* 1 RECENT')
        a.equal('* OK [UNSEEN 1]')
        a.equal('* OK [UIDVALIDITY 1]')
        a.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        a.equal('T003 OK [READ-WRITE] SELECT completed')
        a.match(/^\* BYE /)
        a.equal('T004 OK LOGOUT completed')
      }

      assert_equal(2, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 1, 0, 0 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 2    ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
    end

    def test_command_loop_select_utf7_mbox_name
      mbox_id = @mail_store.add_mbox('~peter/mail/日本語/台北')

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 SELECT "~peter/mail/&ZeVnLIqe-/&U,BTFw-"
T003 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.equal('* 0 EXISTS')
        a.equal('* 0 RECENT')
        a.equal('* OK [UNSEEN 0]')
        a.equal("* OK [UIDVALIDITY #{mbox_id}]")
        a.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        a.equal('T002 OK [READ-WRITE] SELECT completed')
        a.match(/^\* BYE /)
        a.equal('T003 OK LOGOUT completed')
      }
    end

    def test_command_loop_examine
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 2, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 2, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 2, 0, 1 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([       3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 2    ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1       ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 EXAMINE INBOX
T002 LOGIN foo open_sesame
T003 EXAMINE INBOX
T004 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.equal('* 3 EXISTS')
        a.equal('* 1 RECENT')
        a.equal('* OK [UNSEEN 1]')
        a.equal('* OK [UIDVALIDITY 1]')
        a.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        a.equal('T003 OK [READ-ONLY] EXAMINE completed')
        a.match(/^\* BYE /)
        a.equal('T004 OK LOGOUT completed')
      }

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 2, 0, 1 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([       3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 2    ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1       ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
    end

    def test_command_loop_examine_utf7_mbox_name
      mbox_id = @mail_store.add_mbox('~peter/mail/日本語/台北')

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 EXAMINE "~peter/mail/&ZeVnLIqe-/&U,BTFw-"
T003 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.equal('* 0 EXISTS')
        a.equal('* 0 RECENT')
        a.equal('* OK [UNSEEN 0]')
        a.equal("* OK [UIDVALIDITY #{mbox_id}]")
        a.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        a.equal('T002 OK [READ-ONLY] EXAMINE completed')
        a.match(/^\* BYE /)
        a.equal('T003 OK LOGOUT completed')
      }
    end

    def test_command_loop_create
      assert_nil(@mail_store.mbox_id('foo'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 CREATE foo
T002 LOGIN foo open_sesame
T003 CREATE foo
T004 CREATE inbox
T005 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.equal('T003 OK CREATE completed')
        a.match(/^T004 NO /)
        a.match(/^\* BYE /)
        a.equal('T005 OK LOGOUT completed')
      }

      assert_not_nil(@mail_store.mbox_id('foo'))
    end

    def test_command_loop_create_utf7_mbox_name
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 CREATE "~peter/mail/&ZeVnLIqe-/&U,BTFw-"
T003 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.equal('T002 OK CREATE completed')
        a.match(/^\* BYE /)
        a.equal('T003 OK LOGOUT completed')
      }

      assert_not_nil(@mail_store.mbox_id('~peter/mail/日本語/台北'))
    end

    def test_command_loop_delete
      @mail_store.add_mbox('foo')
      assert_not_nil(@mail_store.mbox_id('inbox'))
      assert_not_nil(@mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('bar'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 DELETE foo
T002 LOGIN foo open_sesame
T003 DELETE foo
T004 DELETE bar
T005 DELETE inbox
T006 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.equal('T003 OK DELETE completed')
        a.match(/^T004 NO /)
        a.match(/^T005 NO /)
        a.match(/^\* BYE /)
        a.equal('T006 OK LOGOUT completed')
      }

      assert_not_nil(@mail_store.mbox_id('inbox'))
      assert_nil(@mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('bar'))
    end

    def test_command_loop_delete_utf7_mbox_name
      @mail_store.add_mbox('~peter/mail/日本語/台北')
      assert_not_nil(@mail_store.mbox_id('~peter/mail/日本語/台北'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 DELETE "~peter/mail/&ZeVnLIqe-/&U,BTFw-"
T003 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.equal('T002 OK DELETE completed')
        a.match(/^\* BYE /)
        a.equal('T003 OK LOGOUT completed')
      }

      assert_nil(@mail_store.mbox_id('~peter/mail/日本語/台北'))
    end

    def test_command_loop_rename
      mbox_id = @mail_store.add_mbox('foo')

      assert_equal(mbox_id, @mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('bar'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 RENAME foo bar
T002 LOGIN foo open_sesame
T003 RENAME foo bar
T004 RENAME nobox baz
T005 RENAME INBOX baz
T006 RENAME bar inbox
T007 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.equal('T003 OK RENAME completed')
        a.match(/^T004 NO /)
        a.match(/^T005 NO /)
        a.match(/^T006 NO /)
        a.match(/^\* BYE /)
        a.equal('T007 OK LOGOUT completed')
      }

      assert_nil(@mail_store.mbox_id('foo'))
      assert_equal(mbox_id, @mail_store.mbox_id('bar'))
      assert_equal('INBOX', @mail_store.mbox_name(@inbox_id))
    end

    def test_command_loop_rename_utf7_mbox_name
      @mail_store.add_mbox('foo')

      assert_not_nil(@mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('~peter/mail/日本語/台北'))
      assert_nil(@mail_store.mbox_id('bar'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 RENAME foo "~peter/mail/&ZeVnLIqe-/&U,BTFw-"
T003 RENAME "~peter/mail/&ZeVnLIqe-/&U,BTFw-" bar
T004 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.equal('T002 OK RENAME completed')
        a.equal('T003 OK RENAME completed')
        a.match(/^\* BYE /)
        a.equal('T004 OK LOGOUT completed')
      }

      assert_nil(@mail_store.mbox_id('foo'))
      assert_nil(@mail_store.mbox_id('~peter/mail/日本語/台北'))
      assert_not_nil(@mail_store.mbox_id('bar'))
    end

    def test_command_loop_list
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_mbox('foo')

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LIST "" ""
T002 LOGIN foo open_sesame
T003 LIST "" ""
T007 LIST "" *
T008 LIST "" f*
T009 LIST IN *
T010 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.equal('* LIST (\Noselect) NIL ""')
        a.equal('T003 OK LIST completed')
        a.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        a.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
        a.equal('T007 OK LIST completed')
        a.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
        a.equal('T008 OK LIST completed')
        a.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        a.equal('T009 OK LIST completed')
        a.match(/^\* BYE /)
        a.equal('T010 OK LOGOUT completed')
      }
    end

    def test_command_loop_list_utf7_mbox_name
      @mail_store.add_mbox('~peter/mail/日本語/台北')

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 LIST "~peter/" "*&ZeVnLIqe-*"
T003 LIST "~peter/mail/&ZeVnLA-" "*&U,A-*"
T004 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.equal('* LIST (\Noinferiors \Unmarked) NIL "~peter/mail/&ZeVnLIqe-/&U,BTFw-"')
        a.equal('T002 OK LIST completed')
        a.equal('* LIST (\Noinferiors \Unmarked) NIL "~peter/mail/&ZeVnLIqe-/&U,BTFw-"')
        a.equal('T003 OK LIST completed')
        a.match(/^\* BYE /)
        a.equal('T004 OK LOGOUT completed')
      }
    end

    def test_command_loop_status
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
      @mail_store.add_msg(@inbox_id, 'bar')

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 STATUS nobox (MESSAGES)
T002 LOGIN foo open_sesame
T003 STATUS nobox (MESSAGES)
T009 STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)
T011 STATUS INBOX MESSAGES
T012 STATUS INBOX (DETARAME)
T013 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.equal("* STATUS \"INBOX\" (MESSAGES 2 RECENT 1 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
        a.equal('T009 OK STATUS completed')
        a.match(/^T011 BAD /)
        a.match(/^T012 BAD /)
        a.match(/^\* BYE /)
        a.equal('T013 OK LOGOUT completed')
      }
    end

    def test_command_loop_status_utf7_mbox_name
      mbox_id = @mail_store.add_mbox('~peter/mail/日本語/台北')

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 STATUS "~peter/mail/&ZeVnLIqe-/&U,BTFw-" (UIDVALIDITY MESSAGES RECENT UNSEEN)
T003 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.equal("* STATUS \"~peter/mail/&ZeVnLIqe-/&U,BTFw-\" (UIDVALIDITY #{mbox_id} MESSAGES 0 RECENT 0 UNSEEN 0)")
        a.equal('T002 OK STATUS completed')
        a.match(/^\* BYE /)
        a.equal('T003 OK LOGOUT completed')
      }
    end

    def test_command_loop_append
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        a.equal('T002 OK LOGIN completed')
        a.equal('T003 OK APPEND completed')
        a.equal('T004 OK APPEND completed')
        a.match(/^\+ /)
        a.equal('T005 OK APPEND completed')
        a.equal('T006 OK APPEND completed')
        a.match(/^T007 BAD /)
        a.match(/^T008 BAD /)
        a.match(/^T009 BAD /)
        a.match(/^T010 BAD /)
        a.match(/^T011 NO \[TRYCREATE\]/)
        a.match(/^\* BYE /)
        a.equal('T012 OK LOGOUT completed')
      }

      assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal('a', @mail_store.msg_text(@inbox_id, 1))
      assert_equal('b', @mail_store.msg_text(@inbox_id, 2))
      assert_equal('c', @mail_store.msg_text(@inbox_id, 3))
      assert_equal('d', @mail_store.msg_text(@inbox_id, 4))
      assert_equal([    2,    4 ], [ 1, 2, 3, 4 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([    2,    4 ], [ 1, 2, 3, 4 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([    2,    4 ], [ 1, 2, 3, 4 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([    2,    4 ], [ 1, 2, 3, 4 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([    2,    4 ], [ 1, 2, 3, 4 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 2, 3, 4 ], [ 1, 2, 3, 4 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), @mail_store.msg_date(@inbox_id, 3))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), @mail_store.msg_date(@inbox_id, 4))
    end

    def test_command_loop_append_utf7_mbox_name
      mbox_id = @mail_store.add_mbox('~peter/mail/日本語/台北')
      assert_equal([], @mail_store.each_msg_uid(mbox_id).to_a)

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 APPEND "~peter/mail/&ZeVnLIqe-/&U,BTFw-" "Hello world."
T003 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.equal('T002 OK APPEND completed')
        a.match(/^\* BYE /)
        a.equal('T003 OK LOGOUT completed')
      }

      assert_equal([ 1 ], @mail_store.each_msg_uid(mbox_id).to_a)
      assert_equal('Hello world.', @mail_store.msg_text(mbox_id, 1))
    end

    def test_command_loop_check
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 CHECK
T002 LOGIN foo open_sesame
T003 CHECK
T004 SELECT INBOX
T005 CHECK
T006 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('T005 OK CHECK completed')
        a.match(/^\* BYE /)
        a.equal('T006 OK LOGOUT completed')
      }
    end

    def test_command_loop_close
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 2, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 2, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 2, 0, 1 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([       3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 2    ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1       ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 CLOSE
T002 LOGIN foo open_sesame
T003 CLOSE
T004 SELECT INBOX
T005 CLOSE
T006 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.equal('* 3 EXISTS')
        a.equal('* 1 RECENT')
        a.equal('* OK [UNSEEN 1]')
        a.equal('* OK [UIDVALIDITY 1]')
        a.equal('* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)')
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('T005 OK CLOSE completed')
        a.match(/^\* BYE /)
        a.equal('T006 OK LOGOUT completed')
      }

      assert_equal(2, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 1, 0, 0 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 2    ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([      ], [ 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
    end

    def test_command_loop_close_read_only
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 2, 'recent', false)
      @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 2, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 2, 0, 1 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([       3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 2    ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1       ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 CLOSE
T002 LOGIN foo open_sesame
T003 CLOSE
T004 EXAMINE INBOX
T005 CLOSE
T006 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.equal('* 3 EXISTS')
        a.equal('* 1 RECENT')
        a.equal('* OK [UNSEEN 1]')
        a.equal('* OK [UIDVALIDITY 1]')
        a.equal('* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)')
        a.equal('T004 OK [READ-ONLY] EXAMINE completed')
        a.equal('T005 OK CLOSE completed')
        a.match(/^\* BYE /)
        a.equal('T006 OK LOGOUT completed')
      }

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 1, 0, 0, 2, 0, 1 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([       3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([ 1, 2    ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([         ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1       ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
    end

    def test_command_loop_expunge
      @mail_store.add_msg(@inbox_id, 'a')
      @mail_store.add_msg(@inbox_id, 'b')
      @mail_store.add_msg(@inbox_id, 'c')
      for name in %w[ answered flagged seen draft ]
        @mail_store.set_msg_flag(@inbox_id, 2, name, true)
        @mail_store.set_msg_flag(@inbox_id, 3, name, true)
      end
      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)

      assert_equal(3, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 3, 2, 2, 2, 2, 1 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([ 1, 2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })
      assert_equal([    2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([    2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([    2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([    2, 3 ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([    2    ], [ 1, 2, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 EXPUNGE
T002 LOGIN foo open_sesame
T003 EXPUNGE
T004 SELECT INBOX
T007 EXPUNGE
T009 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('* 2 EXPUNGE')
        a.equal('T007 OK EXPUNGE completed')
        a.match(/^\* BYE /)
        a.equal('T009 OK LOGOUT completed')
      }

      assert_equal(2, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 1, 1, 1, 1, 0 ],
                   %w[ recent answered flagged seen draft deleted ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([      ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([    3 ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([      ], [ 1, 3 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
    end

    def test_command_loop_expunge_read_only
      @mail_store.add_msg(@inbox_id, 'a')
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)

      assert_equal(1, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ false, false, true, false, false, true ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.msg_flag(@inbox_id, 1, name)
                   })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 EXPUNGE
T002 LOGIN foo open_sesame
T003 EXPUNGE
T004 EXAMINE INBOX
T005 EXPUNGE
T006 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-ONLY] EXAMINE completed')
        a.match(/^T005 NO /)
        a.match(/^\* BYE /)
        a.equal('T006 OK LOGOUT completed')
      }

      assert_equal(1, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ false, false, true, false, false, true ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.msg_flag(@inbox_id, 1, name)
                   })
    end

    def test_command_loop_search
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: alice\r\n\r\napple")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: alice\r\n\r\nbnana")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\norange")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\nmelon")
      @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nFrom: bob\r\n\r\npineapple")
      @mail_store.set_msg_flag(@inbox_id, 2, 'deleted', true)
      @mail_store.set_msg_flag(@inbox_id, 4, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      assert_equal([ 1, 3, 5 ], @mail_store.each_msg_uid(@inbox_id).to_a)

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('* SEARCH 1 2 3')
        a.equal('T006 OK SEARCH completed')
        a.equal('* SEARCH 1 3 5')
        a.equal('T007 OK SEARCH completed')
        a.equal('* SEARCH 1 3')
        a.equal('T008 OK SEARCH completed')
        a.equal('* SEARCH 1 5')
        a.equal('T009 OK SEARCH completed')
        a.match(/^\* BYE /)
        a.equal('T010 OK LOGOUT completed')
      }
    end

    def test_command_loop_fetch
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      mail_store_add_mail_simple
      mail_store_add_mail_multipart

      assert_equal([ 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE 203)')
        a.equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE 1545)')
        a.equal('T005 OK FETCH completed')
        a.equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE 203)')
        a.equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE 1545)')
        a.equal('T006 OK FETCH completed')

        s = @simple_mail.header.raw_source
        s += "\r\n" unless (s =~ /\r?\n\z/)
        s += "\r\n" unless (s =~ /\r?\n\r?\n\z/)
        a.equal("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n")
        s.each_line do |line|
          a.equal(line)
        end
        a.equal(' UID 2)')

        s = @mpart_mail.header.raw_source
        s += "\r\n" unless (s =~ /\r?\n\z/)
        s += "\r\n" unless (s =~ /\r?\n\r?\n\z/)
        a.equal("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n")
        s.each_line do |line|
          a.equal(line)
        end
        a.equal(' UID 3)')

        a.equal('T007 OK FETCH completed')

        s = @simple_mail.raw_source
        a.equal("* 1 FETCH (FLAGS (\\Seen \\Recent) RFC822 {#{s.bytesize}}\r\n")
        s.each_line do |line|
          a.equal(line)
        end
        a.equal(')')

        a.equal('T008 OK FETCH completed')
        a.equal("* 2 FETCH (BODY[1] \"#{@mpart_mail.parts[0].body.raw_source}\")")
        a.equal('T009 OK FETCH completed')

        s = @simple_mail.raw_source
        a.equal("* 1 FETCH (UID 2 RFC822 {#{s.bytesize}}\r\n")
        s.each_line do |line|
          a.equal(line)
        end
        a.equal(')')

        a.equal('T010 OK FETCH completed')
        a.equal("* 2 FETCH (UID 3 BODY[1] \"#{@mpart_mail.parts[0].body.raw_source}\")")
        a.equal('T011 OK FETCH completed')
        a.match(/^\* BYE /)
        a.equal('T012 OK LOGOUT completed')
      }

      assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))
    end

    def test_command_loop_fetch_read_only
      @mail_store.add_msg(@inbox_id, '')
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.expunge_mbox(@inbox_id)
      mail_store_add_mail_simple
      mail_store_add_mail_multipart

      assert_equal([ 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 FETCH 1:* FAST
T002 LOGIN foo open_sesame
T003 FETCH 1:* FAST
T004 EXAMINE INBOX
T005 FETCH 1:* FAST
T006 FETCH 1:* (FAST)
T007 FETCH 1:* (FLAGS RFC822.HEADER UID)
T008 FETCH 1 RFC822
T009 FETCH 2 BODY.PEEK[1]
T010 UID FETCH 2 RFC822
T011 UID FETCH 3 (UID BODY.PEEK[1])
T012 LOGOUT
      EOF


      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-ONLY] EXAMINE completed')
        a.equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE 203)')
        a.equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE 1545)')
        a.equal('T005 OK FETCH completed')
        a.equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE 203)')
        a.equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE 1545)')
        a.equal('T006 OK FETCH completed')

        s = @simple_mail.header.raw_source
        s += "\r\n" unless (s =~ /\r?\n\z/)
        s += "\r\n" unless (s =~ /\r?\n\r?\n\z/)
        a.equal("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n")
        s.each_line do |line|
          a.equal(line)
        end
        a.equal(' UID 2)')

        s = @mpart_mail.header.raw_source
        s += "\r\n" unless (s =~ /\r?\n\z/)
        s += "\r\n" unless (s =~ /\r?\n\r?\n\z/)
        a.equal("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER {#{s.bytesize}}\r\n")
        s.each_line do |line|
          a.equal(line)
        end
        a.equal(' UID 3)')

        a.equal('T007 OK FETCH completed')

        s = @simple_mail.raw_source
        a.equal("* 1 FETCH (RFC822 {#{s.bytesize}}\r\n")
        s.each_line do |line|
          a.equal(line)
        end
        a.equal(')')

        a.equal('T008 OK FETCH completed')
        a.equal("* 2 FETCH (BODY[1] \"#{@mpart_mail.parts[0].body.raw_source}\")")
        a.equal('T009 OK FETCH completed')

        s = @simple_mail.raw_source
        a.equal("* 1 FETCH (UID 2 RFC822 {#{s.bytesize}}\r\n")
        s.each_line do |line|
          a.equal(line)
        end
        a.equal(')')

        a.equal('T010 OK FETCH completed')
        a.equal("* 2 FETCH (UID 3 BODY[1] \"#{@mpart_mail.parts[0].body.raw_source}\")")
        a.equal('T011 OK FETCH completed')
        a.match(/^\* BYE /)
        a.equal('T012 OK LOGOUT completed')
      }

      assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
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
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Recent)')
        a.equal('T005 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Recent)')
        a.equal('T006 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Recent)')
        a.equal('T007 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)')
        a.equal('* 4 FETCH FLAGS (\Seen \Recent)')
        a.equal('T008 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)')
        a.equal('* 5 FETCH FLAGS (\Draft \Recent)')
        a.equal('T009 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('T010 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('T011 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)')
        a.equal('T012 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)')
        a.equal('T013 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)')
        a.equal('T014 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        a.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        a.equal('T015 OK STORE completed')
        a.match(/^\* BYE /)
        a.equal('T016 OK LOGOUT completed')
      }

      assert_equal([ 1, 3, 5,      ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 2, 1, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5,      ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5,      ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') }) # expunge by LOGOUT
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT
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
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('T005 OK STORE completed')
        a.equal('T006 OK STORE completed')
        a.equal('T007 OK STORE completed')
        a.equal('T008 OK STORE completed')
        a.equal('T009 OK STORE completed')
        a.equal('T010 OK STORE completed')
        a.equal('T011 OK STORE completed')
        a.equal('T012 OK STORE completed')
        a.equal('T013 OK STORE completed')
        a.equal('T014 OK STORE completed')
        a.equal('T015 OK STORE completed')
        a.match(/^\* BYE /)
        a.equal('T016 OK LOGOUT completed')
      }

      assert_equal([ 1, 3, 5,      ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 2, 1, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5,      ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5,      ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') }) # expunge by LOGOUT
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT
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
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Recent)')
        a.equal('T005 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Recent)')
        a.equal('T006 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Recent)')
        a.equal('T007 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)')
        a.equal('* 4 FETCH FLAGS (\Seen \Recent)')
        a.equal('T008 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)')
        a.equal('* 5 FETCH FLAGS (\Draft \Recent)')
        a.equal('T009 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('T010 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        a.equal('T011 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)')
        a.equal('T012 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)')
        a.equal('T013 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Draft \Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)')
        a.equal('T014 OK STORE completed')
        a.equal('* 1 FETCH FLAGS (\Recent)')
        a.equal('* 2 FETCH FLAGS (\Answered \Recent)')
        a.equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)')
        a.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        a.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        a.equal('T015 OK STORE completed')
        a.match(/^\* BYE /)
        a.equal('T016 OK LOGOUT completed')
      }

      assert_equal([ 1, 3, 5,      ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 2, 1, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5,      ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5,      ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') }) # expunge by LOGOUT
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT
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
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)

      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('T005 OK STORE completed')
        a.equal('T006 OK STORE completed')
        a.equal('T007 OK STORE completed')
        a.equal('T008 OK STORE completed')
        a.equal('T009 OK STORE completed')
        a.equal('T010 OK STORE completed')
        a.equal('T011 OK STORE completed')
        a.equal('T012 OK STORE completed')
        a.equal('T013 OK STORE completed')
        a.equal('T014 OK STORE completed')
        a.equal('T015 OK STORE completed')
        a.match(/^\* BYE /)
        a.equal('T016 OK LOGOUT completed')
      }

      assert_equal([ 1, 3, 5,      ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 2, 1, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([    3, 5,      ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([       5,      ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') }) # expunge by LOGOUT
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([               ], [ 1, 3, 5,      ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT
    end

    def test_command_loop_store_read_only
      @mail_store.add_msg(@inbox_id, '')

      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ false, false, false, false, false, true ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.msg_flag(@inbox_id, 1, name)
                   })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T002 LOGIN foo open_sesame
T003 STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T004 EXAMINE INBOX
T005 STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T006 STORE 1 FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T007 STORE 1 -FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T008 STORE 1 +FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
T009 STORE 1 FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
T010 STORE 1 0FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
T011 UID STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T012 UID STORE 1 FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T013 UID STORE 1 -FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
T014 UID STORE 1 +FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
T015 UID STORE 1 FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
T016 UID STORE 1 -FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
T017 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-ONLY] EXAMINE completed')
        a.match(/^T005 NO /)
        a.match(/^T006 NO /)
        a.match(/^T007 NO /)
        a.match(/^T008 NO /)
        a.match(/^T009 NO /)
        a.match(/^T010 NO /)
        a.match(/^T011 NO /)
        a.match(/^T012 NO /)
        a.match(/^T013 NO /)
        a.match(/^T014 NO /)
        a.match(/^T015 NO /)
        a.match(/^T016 NO /)
        a.match(/^\* BYE /)
        a.equal('T017 OK LOGOUT completed')
      }

      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ false, false, false, false, false, true ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.msg_flag(@inbox_id, 1, name)
                   })
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
        uid = @mail_store.add_msg(@inbox_id, msg_src.next)
        @mail_store.set_msg_flag(@inbox_id, uid, 'flagged', true)
      end
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      work_id = @mail_store.add_mbox('WORK')

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(0, @mail_store.mbox_msg_num(work_id))
      assert_equal([], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('T005 OK COPY completed')
        a.equal('T006 OK COPY completed')
        a.equal('T007 OK COPY completed')
        a.match(/^T008 NO \[TRYCREATE\]/)
        a.match(/^\* BYE /)
        a.equal('T009 OK LOGOUT completed')
      }

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT

      assert_equal(6, @mail_store.mbox_msg_num(work_id))
      assert_equal([ 1, 2, 3, 4, 5, 6 ], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 6, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'answered') })
      assert_equal([ 1, 2, 3, 4, 5, 6 ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'flagged') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'deleted') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'seen') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'draft') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'recent') }) # clear by LOGOUT
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
        uid = @mail_store.add_msg(@inbox_id, msg_src.next)
        @mail_store.set_msg_flag(@inbox_id, uid, 'flagged', true)
      end
      @mail_store.each_msg_uid(@inbox_id) do |uid|
        if (uid % 2 == 0) then
          @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
        end
      end
      @mail_store.expunge_mbox(@inbox_id)
      work_id = @mail_store.add_mbox('WORK')

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 5 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') })

      assert_equal(0, @mail_store.mbox_msg_num(work_id))
      assert_equal([], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 0, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
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

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^T001 NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        a.equal('T002 OK LOGIN completed')
        a.match(/^T003 NO /)
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('T005 OK COPY completed')
        a.equal('T006 OK COPY completed')
        a.equal('T007 OK COPY completed')
        a.match(/^T008 NO \[TRYCREATE\]/)
        a.match(/^\* BYE /)
        a.equal('T009 OK LOGOUT completed')
      }

      assert_equal(5, @mail_store.mbox_msg_num(@inbox_id))
      assert_equal([ 1, 3, 5, 7, 9 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([ 0, 5, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(@inbox_id, name)
                   })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'answered') })
      assert_equal([ 1, 3, 5, 7, 9 ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'flagged') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'deleted') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'seen') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'draft') })
      assert_equal([               ], [ 1, 3, 5, 7, 9 ].find_all{|id| @mail_store.msg_flag(@inbox_id, id, 'recent') }) # clear by LOGOUT

      assert_equal(6, @mail_store.mbox_msg_num(work_id))
      assert_equal([ 1, 2, 3, 4, 5, 6 ], @mail_store.each_msg_uid(work_id).to_a)
      assert_equal([ 0, 6, 0, 0, 0, 0 ],
                   %w[ answered flagged deleted seen draft recent ].map{|name|
                     @mail_store.mbox_flag_num(work_id, name)
                   })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'answered') })
      assert_equal([ 1, 2, 3, 4, 5, 6 ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'flagged') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'deleted') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'seen') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'draft') })
      assert_equal([                  ], [ 1, 2, 3, 4, 5, 6 ].find_all{|id| @mail_store.msg_flag(work_id, id, 'recent') }) # clear by LOGOUT
    end

    def test_command_loop_copy_utf7_mbox_name
      @mail_store.add_msg(@inbox_id, 'Hello world.')
      mbox_id = @mail_store.add_mbox('~peter/mail/日本語/台北')

      assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      assert_equal([], @mail_store.each_msg_uid(mbox_id).to_a)

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 SELECT INBOX
T003 COPY 1 "~peter/mail/&ZeVnLIqe-/&U,BTFw-"
T004 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK LOGIN completed')
        a.skip_while{|line| line =~ /^\* / }
        a.equal('T002 OK [READ-WRITE] SELECT completed')
        a.equal('T003 OK COPY completed')
        a.match(/^\* BYE /)
        a.equal('T004 OK LOGOUT completed')
      }

      assert_equal([ 1 ], @mail_store.each_msg_uid(mbox_id).to_a)
      assert_equal('Hello world.', @mail_store.msg_text(mbox_id, 1))
    end

    def test_command_loop_noop
      @mail_store.add_msg(@inbox_id, '')

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 NOOP
T002 LOGIN foo open_sesame
T003 NOOP
T004 SELECT INBOX
T005 NOOP
T006 CLOSE
T007 NOOP
T008 EXAMINE INBOX
T009 NOOP
T010 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('T001 OK NOOP completed')
        a.equal('T002 OK LOGIN completed')
        a.equal('T003 OK NOOP completed')
        a.skip_while{|line| line =~ /^\* /}
        a.equal('T004 OK [READ-WRITE] SELECT completed')
        a.equal('* 1 EXISTS')
        a.equal('* 1 RECENTS')
        a.equal('T005 OK NOOP completed')
        a.equal('T006 OK CLOSE completed')
        a.equal('T007 OK NOOP completed')
        a.skip_while{|line| line =~ /^\* /}
        a.equal('T008 OK [READ-ONLY] EXAMINE completed')
        a.equal('* 1 EXISTS')
        a.equal('* 0 RECENTS')
        a.equal('T009 OK NOOP completed')
        a.match(/^\* BYE /)
        a.equal('T010 OK LOGOUT completed')
      }
    end

    def test_command_loop_error_handling
      @mail_store.add_msg(@inbox_id, '')

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
SYNTAX_ERROR
T001 NO_COMMAND
T002 UID NO_COMMAND
T003 UID
T004 NOOP DETARAME
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.equal('* BAD client command syntax error')
        a.equal('T001 BAD unknown command')
        a.equal('T002 BAD unknown uid command')
        a.equal('T003 BAD empty uid parameter')
        a.equal('T004 BAD invalid command parameter')
      }
    end

    def test_command_loop_db_recovery
      @mail_store_pool.put(@mail_store_holder)
      assert(@mail_store_pool.empty?)
      meta_db = RIMS::DB::Meta.new(RIMS::Hash_KeyValueStore.new(@kvs['test/meta']))
      meta_db.dirty = true
      meta_db.close
      @mail_store_holder = @mail_store_pool.get('foo')
      @mail_store = @mail_store_holder.mail_store

      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF'.b, 'r')
T001 LOGIN foo open_sesame
T002 LOGOUT
      EOF

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_imap_response(res) {|a|
        a.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        a.match(/^\* OK \[ALERT\] recovery/)
        a.equal('T001 OK LOGIN completed')
        a.match(/^\* BYE /)
        a.equal('T002 OK LOGOUT completed')
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
