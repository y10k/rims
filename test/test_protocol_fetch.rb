# -*- coding: utf-8 -*-

require 'logger'
require 'rims'
require 'set'
require 'stringio'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolFetchParserTest < Test::Unit::TestCase
    include RIMS::Protocol::FetchParser::Utils

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
      @inbox_id = @mail_store.add_mbox('INBOX')
    end

    def make_fetch_parser(read_only: false)
      yield if block_given?
      if (read_only) then
        @folder = @mail_store.examine_mbox(@inbox_id)
      else
        @folder = @mail_store.select_mbox(@inbox_id)
      end
      @parser = RIMS::Protocol::FetchParser.new(@mail_store, @folder)
    end
    private :make_fetch_parser

    def add_mail_simple
      @simple_mail = Mail.new(<<-'EOF')
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
    private :add_mail_simple

    def add_mail_multipart
      @mpart_mail = Mail.new(<<-'EOF')
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
    private :add_mail_multipart

    def add_mail_mime_subject
      @mime_subject_mail = Mail.new(<<-'EOF')
Date: Fri, 8 Nov 2013 19:31:03 +0900
Subject: =?ISO-2022-JP?B?GyRCJEYkOSRIGyhC?=
From: foo@nonet.com, bar <bar@nonet.com>
Sender: foo@nonet.com
Reply-To: foo@nonet.com
To: alice@test.com, bob <bob@test.com>
Cc: Kate <kate@test.com>
Bcc: foo@nonet.com
In-Reply-To: <20131106081723.5KJU1774292@smtp.testt.com>
Message-Id: <20131107214750.445A1255B9F@smtp.nonet.com>

Hello world.
      EOF
      @mail_store.add_msg(@inbox_id, @mime_subject_mail.raw_source, Time.parse('2013-11-08 19:31:03 +0900'))
    end
    private :add_mail_mime_subject

    def add_mail_empty
      @empty_mail = Mail.new('')
      @mail_store.add_msg(@inbox_id, @empty_mail.raw_source)
    end

    def add_mail_no_body
      @no_body_mail = Mail.new('foo')
      @mail_store.add_msg(@inbox_id, @no_body_mail.raw_source)
    end

    def make_body(description)
      reader = RIMS::Protocol::RequestReader.new(StringIO.new('', 'r'), StringIO.new('', 'w'), Logger.new(STDOUT))
      reader.parse([ description ])[0]
    end
    private :make_body

    def assert_strenc_equal(expected_enc, expected_str, expr_str)
      assert_equal(Encoding.find(expected_enc), expr_str.encoding)
      assert_equal(expected_str.dup.force_encoding(expected_enc), expr_str)
    end
    private :assert_strenc_equal

    def test_parse_all
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      fetch = @parser.parse('ALL')
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (\Recent) ' +
                          'INTERNALDATE "08-11-2013 06:47:50 +0900" ' +
                          'RFC822.SIZE 212 ' +
                          'ENVELOPE (' + [
                            '"Fri, 08 Nov 2013 06:47:50 +0900"',       # Date
                            '"test"',                                  # Subject
                            '("bar@nonet.org")',                       # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '("foo@nonet.org")',                       # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +')',
                          fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (\Recent) ' +
                          'INTERNALDATE "08-11-2013 19:31:03 +0900" ' +
                          'RFC822.SIZE 1616 ' +
                          'ENVELOPE (' + [
                            '"Fri, 08 Nov 2013 19:31:03 +0900"',       # Date
                            '"multipart test"',                        # Subject
                            '("foo@nonet.com")',                       # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '("bar@nonet.com")',                       # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +')',
                          fetch.call(@folder.msg_list[1]))
    end

    def test_parse_body
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }

      fetch = @parser.parse(make_body('BODY[]'))
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "FLAGS (\\Seen \\Recent) BODY[] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "BODY[] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))

      fetch = @parser.parse(make_body('BODY[TEXT]'))
      s = @simple_mail.body.raw_source
      assert_strenc_equal('ascii-8bit', "BODY[TEXT] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[HEADER]'))
      s = @simple_mail.header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_strenc_equal('ascii-8bit', "BODY[HEADER] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      s = @mpart_mail.header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[1].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "FLAGS (\\Seen \\Recent) BODY[HEADER] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[1].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "BODY[HEADER] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[1].id, 'seen'))

      fetch = @parser.parse(make_body('BODY[HEADER.FIELDS (From To)]'))
      s = %w[ From To ].map{|n| "#{n}: #{@simple_mail[n].value}" }.join("\r\n") + "\r\n" * 2
      assert_strenc_equal('ascii-8bit', "BODY[HEADER.FIELDS (From To)] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      s = %w[ From To ].map{|n| "#{n}: #{@mpart_mail[n].value}" }.join("\r\n") + "\r\n" * 2
      assert_strenc_equal('ascii-8bit', "BODY[HEADER.FIELDS (From To)] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[HEADER.FIELDS.NOT (From To Subject)]'))
      not_fields = %w[ from to subject ].to_set
      s = @simple_mail.header.reject{|i| not_fields.include? i.name.downcase }.map{|i| "#{i.name}: #{i.value}" }.join("\r\n") + "\r\n" * 2
      assert_strenc_equal('ascii-8bit', "BODY[HEADER.FIELDS.NOT (From To Subject)] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      s = @mpart_mail.header.reject{|i| not_fields.include? i.name.downcase }.map{|i| "#{i.name}: #{i.value}" }.join("\r\n") + "\r\n" * 2
      assert_strenc_equal('ascii-8bit', "BODY[HEADER.FIELDS.NOT (From To Subject)] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[1]'))
      s = @simple_mail.body.raw_source
      assert_strenc_equal('ascii-8bit', "BODY[1] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      s = @mpart_mail.parts[0].body.raw_source
      assert_strenc_equal('ascii-8bit', %Q'BODY[1] "#{s}"', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3]'))
      assert_strenc_equal('ascii-8bit', "BODY[3] NIL", fetch.call(@folder.msg_list[0]))
      s = @mpart_mail.parts[2].body.raw_source
      assert_strenc_equal('ascii-8bit', "BODY[3] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.1]'))
      assert_strenc_equal('ascii-8bit', "BODY[3.1] NIL", fetch.call(@folder.msg_list[0]))
      s = Mail.new(@mpart_mail.parts[2].body.raw_source).parts[0].body.raw_source
      assert_strenc_equal('ascii-8bit', %Q'BODY[3.1] "#{s}"', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[4.2.2]'))
      assert_strenc_equal('ascii-8bit', "BODY[4.2.2] NIL", fetch.call(@folder.msg_list[0]))
      s = Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[1].body.raw_source
      assert_strenc_equal('ascii-8bit', "BODY[4.2.2] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[1.MIME]'))
      s = @simple_mail.header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_strenc_equal('ascii-8bit', "BODY[1.MIME] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      s = @mpart_mail.parts[0].header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_strenc_equal('ascii-8bit', "BODY[1.MIME] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.MIME]'))
      assert_strenc_equal('ascii-8bit', 'BODY[3.MIME] NIL', fetch.call(@folder.msg_list[0]))
      s = @mpart_mail.parts[2].header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_strenc_equal('ascii-8bit', "BODY[3.MIME] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.1.MIME]'))
      assert_strenc_equal('ascii-8bit', 'BODY[3.1.MIME] NIL', fetch.call(@folder.msg_list[0]))
      s = Mail.new(@mpart_mail.parts[2].body.raw_source).parts[0].header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_strenc_equal('ascii-8bit', "BODY[3.1.MIME] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[4.2.2.MIME]'))
      assert_strenc_equal('ascii-8bit', 'BODY[4.2.2.MIME] NIL', fetch.call(@folder.msg_list[0]))
      s = Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[1].header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_strenc_equal('ascii-8bit', "BODY[4.2.2.MIME] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[1.TEXT]'))
      assert_strenc_equal('ascii-8bit', "BODY[1.TEXT] NIL", fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'BODY[1.TEXT] NIL', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.TEXT]'))
      assert_strenc_equal('ascii-8bit', "BODY[3.TEXT] NIL", fetch.call(@folder.msg_list[0]))
      s = Mail.new(@mpart_mail.parts[2].body.raw_source).body.raw_source
      assert_strenc_equal('ascii-8bit', "BODY[3.TEXT] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.1.TEXT]'))
      assert_strenc_equal('ascii-8bit', "BODY[3.1.TEXT] NIL", fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'BODY[3.1.TEXT] NIL', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[4.2.TEXT]'))
      assert_strenc_equal('ascii-8bit', "BODY[4.2.TEXT] NIL", fetch.call(@folder.msg_list[0]))
      s = Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source).body.raw_source
      assert_strenc_equal('ascii-8bit', "BODY[4.2.TEXT] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[1.HEADER]'))
      assert_strenc_equal('ascii-8bit', 'BODY[1.HEADER] NIL', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'BODY[1.HEADER] NIL', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.HEADER]'))
      assert_strenc_equal('ascii-8bit', 'BODY[3.HEADER] NIL', fetch.call(@folder.msg_list[0]))
      s = Mail.new(@mpart_mail.parts[2].body.raw_source).header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_strenc_equal('ascii-8bit', "BODY[3.HEADER] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.1.HEADER]'))
      assert_strenc_equal('ascii-8bit', 'BODY[3.1.HEADER] NIL', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'BODY[3.1.HEADER] NIL', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[4.2.HEADER]'))
      assert_strenc_equal('ascii-8bit', "BODY[4.2.HEADER] NIL", fetch.call(@folder.msg_list[0]))
      s = Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source).header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_strenc_equal('ascii-8bit', "BODY[4.2.HEADER] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[1.HEADER.FIELDS (To)]'))
      assert_strenc_equal('ascii-8bit', 'BODY[1.HEADER.FIELDS (To)] NIL', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'BODY[1.HEADER.FIELDS (To)] NIL', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.HEADER.FIELDS (To)]'))
      assert_strenc_equal('ascii-8bit', 'BODY[3.HEADER.FIELDS (To)] NIL', fetch.call(@folder.msg_list[0]))
      m = Mail.new(@mpart_mail.parts[2].body.raw_source)
      s = %w[ To ].map{|n| "#{n}: #{m[n].value}" }.join("\r\n") + "\r\n" * 2
      assert_strenc_equal('ascii-8bit', "BODY[3.HEADER.FIELDS (To)] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.1.HEADER.FIELDS (To)]'))
      assert_strenc_equal('ascii-8bit', 'BODY[3.1.HEADER.FIELDS (To)] NIL', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'BODY[3.1.HEADER.FIELDS (To)] NIL', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[4.2.HEADER.FIELDS (To)]'))
      assert_strenc_equal('ascii-8bit', 'BODY[4.2.HEADER.FIELDS (To)] NIL', fetch.call(@folder.msg_list[0]))
      m = Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source)
      s = %w[ To ].map{|n| "#{n}: #{m[n].value}" }.join("\r\n") + "\r\n" * 2
      assert_strenc_equal('ascii-8bit', "BODY[4.2.HEADER.FIELDS (To)] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[1.HEADER.FIELDS.NOT (To From Subject)]'))
      assert_strenc_equal('ascii-8bit', 'BODY[1.HEADER.FIELDS.NOT (To From Subject)] NIL', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'BODY[1.HEADER.FIELDS.NOT (To From Subject)] NIL', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.HEADER.FIELDS.NOT (To From Subject)]'))
      assert_strenc_equal('ascii-8bit', 'BODY[3.HEADER.FIELDS.NOT (To From Subject)] NIL', fetch.call(@folder.msg_list[0]))
      not_fields = %w[ to from subject ].to_set
      m = Mail.new(@mpart_mail.parts[2].body.raw_source)
      s = m.header.reject{|i| not_fields.include? i.name.downcase }.map{|i| "#{i.name}: #{i.value}" }.join("\r\n") + "\r\n" * 2
      assert_strenc_equal('ascii-8bit', "BODY[3.HEADER.FIELDS.NOT (To From Subject)] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[3.1.HEADER.FIELDS.NOT (To From Subject)]'))
      assert_strenc_equal('ascii-8bit', 'BODY[3.1.HEADER.FIELDS.NOT (To From Subject)] NIL', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'BODY[3.1.HEADER.FIELDS.NOT (To From Subject)] NIL', fetch.call(@folder.msg_list[1]))

      fetch = @parser.parse(make_body('BODY[4.2.HEADER.FIELDS.NOT (To From Subject)]'))
      assert_strenc_equal('ascii-8bit', 'BODY[4.2.HEADER.FIELDS.NOT (To From Subject)] NIL', fetch.call(@folder.msg_list[0]))
      not_fields = %w[ to from subject ].to_set
      m = Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source)
      s = m.header.reject{|i| not_fields.include? i.name.downcase }.map{|i| "#{i.name}: #{i.value}" }.join("\r\n") + "\r\n" * 2
      assert_strenc_equal('ascii-8bit', "BODY[4.2.HEADER.FIELDS.NOT (To From Subject)] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[1]))

      assert_raise(RIMS::SyntaxError) {
        @parser.parse(make_body('BODY[MIME]'))
      }
    end

    def test_parse_body_peek
      make_fetch_parser{
        add_mail_simple
      }

      fetch = @parser.parse(make_body('BODY.PEEK[]'))
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "BODY[] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
    end

    def test_parse_body_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }

      fetch = @parser.parse(make_body('BODY[]'))
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "BODY[] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
    end

    def test_parse_body_partial
      make_fetch_parser{
        msg_id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, msg_id, 'seen', true)
      }

      s = @simple_mail.raw_source

      fetch = @parser.parse(make_body('BODY[]<0.100>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<0> {100}\r\n#{s.byteslice(0, 100)}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<0.1000>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<0> {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<100.100>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<100> {100}\r\n#{s.byteslice(100, 100)}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<211.1>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<211> {1}\r\n\n", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<212.1>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<212> NIL", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<0.0>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<0> \"\"", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<100.0>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<100> \"\"", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<211.0>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<211> \"\"", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<212.0>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<212> NIL", fetch.call(@folder.msg_list[0]))
    end

    def test_parse_bodystructure
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
        add_mail_empty
        add_mail_no_body
      }
      fetch_body = @parser.parse('BODY')
      fetch_bodystructure = @parser.parse('BODYSTRUCTURE')
      assert_strenc_equal('ascii-8bit',
                          'BODY ' +
                          encode_list([ 'TEXT',
                                        'plain',
                                        %w[ charset us-ascii ],
                                        nil,
                                        nil,
                                        '7bit',
                                        212,
                                        9
                                      ]),
                          fetch_body.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'BODYSTRUCTURE ' +
                          encode_list([ 'TEXT',
                                        'plain',
                                        %w[ charset us-ascii ],
                                        nil,
                                        nil,
                                        '7bit',
                                        212,
                                        9
                                      ]),
                          fetch_bodystructure.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'BODY ' +
                          encode_list([ [ 'TEXT', 'plain', %w[ charset us-ascii], nil, nil, nil, 63, 4 ],
                                        [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                        [
                                          'MESSAGE', 'RFC822', [], nil, nil, nil, 401,
                                          [
                                            'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                            %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                          ],
                                          [
                                            [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 60, 4 ],
                                            [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                            'mixed'
                                          ],
                                          19
                                        ],
                                        [
                                          [ 'image', 'gif', [], nil, nil, nil, 27 ],
                                          [
                                            'MESSAGE', 'RFC822', [], nil, nil, nil, 641,
                                            [
                                              'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                              %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                            ],
                                            [
                                              [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 52, 4 ],
                                              [
                                                [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 68, 4 ],
                                                [ 'TEXT', 'html', %w[ charset us-ascii ], nil, nil, nil, 96, 6 ],
                                                'alternative'
                                              ],
                                              'mixed'
                                            ],
                                            29
                                          ],
                                          'mixed',
                                        ],
                                        'mixed'
                                      ]),
                          fetch_body.call(@folder.msg_list[1]))
      assert_strenc_equal('ascii-8bit',
                          'BODYSTRUCTURE ' +
                          encode_list([ [ 'TEXT', 'plain', %w[ charset us-ascii], nil, nil, nil, 63, 4 ],
                                        [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                        [
                                          'MESSAGE', 'RFC822', [], nil, nil, nil, 401,
                                          [
                                            'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                            %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                          ],
                                          [
                                            [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 60, 4 ],
                                            [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                            'mixed'
                                          ],
                                          19
                                        ],
                                        [
                                          [ 'image', 'gif', [], nil, nil, nil, 27 ],
                                          [
                                            'MESSAGE', 'RFC822', [], nil, nil, nil, 641,
                                            [
                                              'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                              %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                            ],
                                            [
                                              [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 52, 4 ],
                                              [
                                                [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 68, 4 ],
                                                [ 'TEXT', 'html', %w[ charset us-ascii ], nil, nil, nil, 96, 6 ],
                                                'alternative'
                                              ],
                                              'mixed'
                                            ],
                                            29
                                          ],
                                          'mixed',
                                        ],
                                        'mixed'
                                      ]),
                          fetch_bodystructure.call(@folder.msg_list[1]))
      assert_strenc_equal('ascii-8bit',
                          'BODY ' +
                          encode_list([ 'application',
                                        'octet-stream',
                                        [],
                                        nil,
                                        nil,
                                        nil,
                                        0
                                      ]),
                          fetch_body.call(@folder.msg_list[2]))
      assert_strenc_equal('ascii-8bit',
                          'BODYSTRUCTURE ' +
                          encode_list([ 'application',
                                        'octet-stream',
                                        [],
                                        nil,
                                        nil,
                                        nil,
                                        0
                                      ]),
                          fetch_bodystructure.call(@folder.msg_list[2]))
      assert_strenc_equal('ascii-8bit',
                          'BODY ' +
                          encode_list([ 'application',
                                        'octet-stream',
                                        [],
                                        nil,
                                        nil,
                                        nil,
                                        3
                                      ]),
                          fetch_body.call(@folder.msg_list[3]))
      assert_strenc_equal('ascii-8bit',
                          'BODYSTRUCTURE ' +
                          encode_list([ 'application',
                                        'octet-stream',
                                        [],
                                        nil,
                                        nil,
                                        nil,
                                        3
                                      ]),
                          fetch_bodystructure.call(@folder.msg_list[3]))
    end

    def test_parse_envelope
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
        add_mail_mime_subject
        add_mail_empty
        add_mail_no_body
      }
      fetch = @parser.parse('ENVELOPE')
      assert_strenc_equal('ascii-8bit',
                          'ENVELOPE (' + [
                            '"Fri, 08 Nov 2013 06:47:50 +0900"',       # Date
                            '"test"',                                  # Subject
                            '("bar@nonet.org")',                       # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '("foo@nonet.org")',                       # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +')',
                          fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'ENVELOPE (' + [
                            '"Fri, 08 Nov 2013 19:31:03 +0900"',       # Date
                            '"multipart test"',                        # Subject
                            '("foo@nonet.com")',                       # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '("bar@nonet.com")',                       # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +')',
                          fetch.call(@folder.msg_list[1]))
      assert_strenc_equal('ascii-8bit',
                          'ENVELOPE (' + [
                            '"Fri, 08 Nov 2013 19:31:03 +0900"',       # Date
                            '"=?ISO-2022-JP?B?GyRCJEYkOSRIGyhC?="',    # Subject
                            '("foo@nonet.com" "bar@nonet.com")',       # From
                            '("foo@nonet.com")',                       # Sender
                            '("foo@nonet.com")',                       # Reply-To
                            '("alice@test.com" "bob@test.com")',       # To
                            '("kate@test.com")',                       # Cc
                            '("foo@nonet.com")',                       # Bcc
                            '"20131106081723.5KJU1774292@smtp.testt.com"',# In-Reply-To
                            '"20131107214750.445A1255B9F@smtp.nonet.com"' # Message-Id
                          ].join(' ') +')',
                          fetch.call(@folder.msg_list[2]))
      assert_strenc_equal('ascii-8bit',
                          'ENVELOPE (NIL NIL NIL NIL NIL NIL NIL NIL NIL NIL)',
                          fetch.call(@folder.msg_list[3]))
      assert_strenc_equal('ascii-8bit',
                          'ENVELOPE (NIL NIL NIL NIL NIL NIL NIL NIL NIL NIL)',
                          fetch.call(@folder.msg_list[4]))
    end

    def test_parse_fast
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      fetch = @parser.parse('FAST')
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (\Recent) ' +
                          'INTERNALDATE "08-11-2013 06:47:50 +0900" ' +
                          'RFC822.SIZE 212',
                          fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (\Recent) ' +
                          'INTERNALDATE "08-11-2013 19:31:03 +0900" ' +
                          'RFC822.SIZE 1616',
                          fetch.call(@folder.msg_list[1]))
    end

    def test_parse_flags
      make_fetch_parser{
        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'answered', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'flagged', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'deleted', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'seen', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'draft', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'answered', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'flagged', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'deleted', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'seen', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'draft', true)
      }
      fetch = @parser.parse('FLAGS')
      assert_strenc_equal('ascii-8bit', 'FLAGS ()', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'FLAGS (\Recent)', fetch.call(@folder.msg_list[1]))
      assert_strenc_equal('ascii-8bit', 'FLAGS (\Answered)', fetch.call(@folder.msg_list[2]))
      assert_strenc_equal('ascii-8bit', 'FLAGS (\Flagged)', fetch.call(@folder.msg_list[3]))
      assert_strenc_equal('ascii-8bit', 'FLAGS (\Deleted)', fetch.call(@folder.msg_list[4]))
      assert_strenc_equal('ascii-8bit', 'FLAGS (\Seen)', fetch.call(@folder.msg_list[5]))
      assert_strenc_equal('ascii-8bit', 'FLAGS (\Draft)', fetch.call(@folder.msg_list[6]))
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (' + RIMS::MailStore::MSG_FLAG_NAMES.map{|n| "\\#{n.capitalize}" }.join(' ') + ')',
                          fetch.call(@folder.msg_list[7]))
    end

    def test_parse_full
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      fetch = @parser.parse('FULL')
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (\Recent) ' +
                          'INTERNALDATE "08-11-2013 06:47:50 +0900" ' +
                          'RFC822.SIZE 212 ' +
                          'ENVELOPE (' + [
                            '"Fri, 08 Nov 2013 06:47:50 +0900"',       # Date
                            '"test"',                                  # Subject
                            '("bar@nonet.org")',                       # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '("foo@nonet.org")',                       # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +') ' +
                          'BODY ' +
                          encode_list([ 'TEXT',
                                        'plain',
                                        %w[ charset us-ascii ],
                                        nil,
                                        nil,
                                        '7bit',
                                        212,
                                        9
                                      ]),
                          fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (\Recent) ' +
                          'INTERNALDATE "08-11-2013 19:31:03 +0900" ' +
                          'RFC822.SIZE 1616 ' +
                          'ENVELOPE (' + [
                            '"Fri, 08 Nov 2013 19:31:03 +0900"',       # Date
                            '"multipart test"',                        # Subject
                            '("foo@nonet.com")',                       # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '("bar@nonet.com")',                       # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +') ' +
                          'BODY ' +
                          encode_list([ [ 'TEXT', 'plain', %w[ charset us-ascii], nil, nil, nil, 63, 4 ],
                                        [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                        [
                                          'MESSAGE', 'RFC822', [], nil, nil, nil, 401,
                                          [
                                            'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                            %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                          ],
                                          [
                                            [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 60, 4 ],
                                            [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                            'mixed'
                                          ],
                                          19
                                        ],
                                        [
                                          [ 'image', 'gif', [], nil, nil, nil, 27 ],
                                          [
                                            'MESSAGE', 'RFC822', [], nil, nil, nil, 641,
                                            [
                                              'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                              %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                            ],
                                            [
                                              [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 52, 4 ],
                                              [
                                                [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 68, 4 ],
                                                [ 'TEXT', 'html', %w[ charset us-ascii ], nil, nil, nil, 96, 6 ],
                                                'alternative'
                                              ],
                                              'mixed'
                                            ],
                                            29
                                          ],
                                          'mixed',
                                        ],
                                        'mixed'
                                      ]),
                          fetch.call(@folder.msg_list[1]))
    end

    def test_parse_internaldate
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      fetch = @parser.parse('INTERNALDATE')
      assert_strenc_equal('ascii-8bit', 'INTERNALDATE "08-11-2013 06:47:50 +0900"', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'INTERNALDATE "08-11-2013 19:31:03 +0900"', fetch.call(@folder.msg_list[1]))
    end

    def test_parse_rfc822
      make_fetch_parser{
        add_mail_simple
      }

      fetch = @parser.parse('RFC822')
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "FLAGS (\\Seen \\Recent) RFC822 {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822 {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
    end

    def test_parse_rfc822_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }

      fetch = @parser.parse('RFC822')
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822 {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
    end

    def test_parse_rfc822_header
      make_fetch_parser{
        add_mail_simple
      }

      fetch = @parser.parse('RFC822.HEADER')
      s = @simple_mail.header.raw_source
      s += "\r\n" unless (s =~ /\r\n$/)
      s += "\r\n" unless (s =~ /\r\n\r\n$/)
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822.HEADER {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
    end

    def test_parse_rfc822_size
      make_fetch_parser{
        add_mail_simple
      }
      fetch = @parser.parse('RFC822.SIZE')
      s = @simple_mail.raw_source
      assert_strenc_equal('ascii-8bit', "RFC822.SIZE #{s.bytesize}", fetch.call(@folder.msg_list[0]))
    end

    def test_parse_rfc822_text
      make_fetch_parser{
        add_mail_simple
      }

      fetch = @parser.parse('RFC822.TEXT')
      s = @simple_mail.body.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "FLAGS (\\Seen \\Recent) RFC822.TEXT {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822.TEXT {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
    end

    def test_parse_rfc822_text_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }

      fetch = @parser.parse('RFC822.TEXT')
      s = @simple_mail.body.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822.TEXT {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].id, 'seen'))
    end

    def test_parse_uid
      make_fetch_parser{
        add_mail_simple
        id = add_mail_simple
        add_mail_multipart

        @mail_store.set_msg_flag(@inbox_id, id, 'deleted', true)
        @mail_store.expunge_mbox(@inbox_id)
        assert_equal([ 1, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      }

      fetch = @parser.parse('UID')
      assert_strenc_equal('ascii-8bit', 'UID 1', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'UID 3', fetch.call(@folder.msg_list[1]))
    end

    def test_parse_group_empty
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      fetch = @parser.parse([ :group ])
      assert_strenc_equal('ascii-8bit', '()', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', '()', fetch.call(@folder.msg_list[1]))
    end
  end

  class ProtocolFetchParserUtilsTest < Test::Unit::TestCase
    def setup
      @simple_mail = Mail.new(<<-'EOF')
To: foo@nonet.org
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
      EOF

      @mpart_mail = Mail.new(<<-'EOF')
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
    end

    def test_encode_header
      s = ''
      s << "To: foo@nonet.org\r\n"
      s << "From: bar@nonet.org\r\n"
      s << "\r\n"
      assert_equal(s, RIMS::Protocol::FetchParser::Utils.encode_header(%w[ to from ].map{|n| @simple_mail[n] }))
    end

    def test_get_body_section
      assert_equal(@simple_mail, RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, []))
      assert_equal(@simple_mail, RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, [ 1 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, [ 1, 1 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, [ 2 ]))

      assert_equal(@mpart_mail.raw_source, RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, []).raw_source)
      assert_equal(@mpart_mail.parts[0].raw_source, RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 1 ]).raw_source)
      assert_equal(@mpart_mail.parts[1].raw_source, RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 2 ]).raw_source)
      assert_equal(@mpart_mail.parts[2].raw_source, RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3 ]).raw_source)
      assert_equal(Mail.new(@mpart_mail.parts[2].body.raw_source).parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3, 1 ]).raw_source)
      assert_equal(Mail.new(@mpart_mail.parts[2].body.raw_source).parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3, 2 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 1 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2 ]).raw_source)
      assert_equal(Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 1 ]).raw_source)
      assert_equal(Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2 ]).raw_source)
      assert_equal(Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[1].parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 1 ]).raw_source)
      assert_equal(Mail.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[1].parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 2 ]).raw_source)
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 5 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 3 ]))

      assert_raise(RIMS::SyntaxError) {
        RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, [ 0 ])
      }
      assert_raise(RIMS::SyntaxError) {
        RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 0 ])
      }
    end

    def test_get_body_content
      assert_equal('test', RIMS::Protocol::FetchParser::Utils.get_body_content(@simple_mail, :subject))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_content(@simple_mail, :subject, nest_mail: true))
      assert_equal('multipart test', RIMS::Protocol::FetchParser::Utils.get_body_content(@mpart_mail, :subject))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_content(@mpart_mail, :subject, nest_mail: true))
      assert_equal('inner multipart', RIMS::Protocol::FetchParser::Utils.get_body_content(@mpart_mail.parts[2], :subject, nest_mail: true))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
