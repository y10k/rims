# -*- coding: utf-8 -*-

require 'logger'
require 'rims'
require 'set'
require 'stringio'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolFetchParserTest < Test::Unit::TestCase
    include AssertUtility
    include RIMS::Protocol::FetchParser::Utils

    def setup
      @kv_store = {}
      @kvs_open = proc{|path| RIMS::Hash_KeyValueStore.new(@kv_store[path] = {}) }
      @mail_store = RIMS::MailStore.new(RIMS::DB::Meta.new(@kvs_open.call('meta')),
                                        RIMS::DB::Message.new(@kvs_open.call('msg'))) {|mbox_id|
        RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
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

    def parse_fetch_attribute(fetch_att_str)
      @fetch = @parser.parse(fetch_att_str)
      begin
        yield
      ensure
        @fetch = nil
      end
    end
    private :parse_fetch_attribute

    def make_body(description)
      reader = RIMS::Protocol::RequestReader.new(StringIO.new('', 'r'), StringIO.new('', 'w'), Logger.new(STDOUT))
      reader.parse(reader.scan_line(description))[0]
    end
    private :make_body

    def get_msg_flag(msg_idx, flag_name)
      @mail_store.msg_flag(@inbox_id, @folder.msg_list[msg_idx].uid, flag_name)
    end
    private :get_msg_flag

    def set_msg_flag(msg_idx, flag_name, flag_value)
      @mail_store.set_msg_flag(@inbox_id, @folder.msg_list[msg_idx].uid, flag_name, flag_value)
      nil
    end
    private :set_msg_flag

    def assert_fetch(msg_idx, expected_message_data_array, encoding: 'ascii-8bit')
      assert_strenc_equal(encoding,
                          message_data_list(expected_message_data_array),
                          @fetch.call(@folder.msg_list[msg_idx]))
    end
    private :assert_fetch

    def add_mail_simple
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
    private :add_mail_simple

    def add_mail_multipart
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
    private :add_mail_multipart

    def add_mail_mime_subject
      @mime_subject_mail = RIMS::RFC822::Message.new(<<-'EOF')
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
      @empty_mail = RIMS::RFC822::Message.new('')
      @mail_store.add_msg(@inbox_id, @empty_mail.raw_source)
    end

    def add_mail_no_body
      @no_body_mail = RIMS::RFC822::Message.new('foo')
      @mail_store.add_msg(@inbox_id, @no_body_mail.raw_source)
    end

    def test_parse_all
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      parse_fetch_attribute('ALL') {
        assert_fetch(0, [
                       'FLAGS (\Recent)',
                       'INTERNALDATE "08-Nov-2013 06:47:50 +0900"',
                       "RFC822.SIZE #{@simple_mail.raw_source.bytesize}",
                       'ENVELOPE',
                       [ '"Fri,  8 Nov 2013 06:47:50 +0900 (JST)"', # Date
                         '"test"',                                  # Subject
                         '((NIL NIL "bar" "nonet.org"))',           # From
                         'NIL',                                     # Sender
                         'NIL',                                     # Reply-To
                         '((NIL NIL "foo" "nonet.org"))',           # To
                         'NIL',                                     # Cc
                         'NIL',                                     # Bcc
                         'NIL',                                     # In-Reply-To
                         'NIL'                                      # Message-Id
                       ]
                     ])
        assert_fetch(1, [
                       'FLAGS (\Recent)',
                       'INTERNALDATE "08-Nov-2013 19:31:03 +0900"',
                       "RFC822.SIZE #{@mpart_mail.raw_source.bytesize}",
                       'ENVELOPE',
                       [ '"Fri, 8 Nov 2013 19:31:03 +0900"',        # Date
                         '"multipart test"',                        # Subject
                         '((NIL NIL "foo" "nonet.com"))',           # From
                         'NIL',                                     # Sender
                         'NIL',                                     # Reply-To
                         '((NIL NIL "bar" "nonet.com"))',           # To
                         'NIL',                                     # Cc
                         'NIL',                                     # Bcc
                         'NIL',                                     # In-Reply-To
                         'NIL'                                      # Message-Id
                       ]
                     ])
      }
    end

    def test_parse_body
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
        add_mail_empty
        add_mail_no_body
      }

      4.times do |i|
        set_msg_flag(i, 'seen', true)
      end

      parse_fetch_attribute(make_body('BODY[]')) {
        assert_fetch(0, [ "BODY[] #{literal(@simple_mail.raw_source)}" ])
        assert_fetch(1, [ "BODY[] #{literal(@mpart_mail.raw_source)}" ])
        assert_fetch(2, [ 'BODY[] ""' ])
        assert_fetch(3, [ %Q'BODY[] "#{@no_body_mail.raw_source}"' ])
      }

      parse_fetch_attribute(make_body('BODY[TEXT]')) {
        assert_fetch(0, [ "BODY[TEXT] #{literal(@simple_mail.body.raw_source)}" ])
        assert_fetch(1, [ "BODY[TEXT] #{literal(@mpart_mail.body.raw_source)}" ])
        assert_fetch(2, [ 'BODY[TEXT] ""' ])
        assert_fetch(3, [ 'BODY[TEXT] ""' ])
      }

      parse_fetch_attribute(make_body('BODY[HEADER]')) {
        assert_fetch(0, [ "BODY[HEADER] #{literal(@simple_mail.header.raw_source)}" ])
        assert_fetch(1, [ "BODY[HEADER] #{literal(@mpart_mail.header.raw_source)}" ])
        assert_fetch(2, [ 'BODY[HEADER] ""' ])
        assert_fetch(3, [ %Q'BODY[HEADER] "#{@no_body_mail.header.raw_source}"' ])
      }

      parse_fetch_attribute(make_body('BODY[HEADER.FIELDS (From To)]')) {
        assert_fetch(0, [
                       'BODY[HEADER.FIELDS (From To)] ' +
                       literal(make_header_text(@simple_mail.header, select_list: %w[ From To ]))
                     ])
        assert_fetch(1, [
                       'BODY[HEADER.FIELDS (From To)] ' +
                       literal(make_header_text(@mpart_mail.header, select_list: %w[ From To ]))
                     ])
        assert_fetch(2, [ 'BODY[HEADER.FIELDS (From To)] ' + literal("\r\n") ])
        assert_fetch(3, [ 'BODY[HEADER.FIELDS (From To)] ' + literal("\r\n") ])
      }

      parse_fetch_attribute(make_body('BODY[HEADER.FIELDS.NOT (From To Subject)]')) {
        assert_fetch(0, [
                       'BODY[HEADER.FIELDS.NOT (From To Subject)] ' +
                       literal(make_header_text(@simple_mail.header, reject_list: %w[ From To Subject]))
                     ])
        assert_fetch(1, [
                       'BODY[HEADER.FIELDS.NOT (From To Subject)] ' +
                       literal(make_header_text(@mpart_mail.header, reject_list: %w[ From To Subject]))
                     ])
        assert_fetch(2, [ 'BODY[HEADER.FIELDS.NOT (From To Subject)] ' + literal("\r\n") ])
        assert_fetch(3, [ 'BODY[HEADER.FIELDS.NOT (From To Subject)] ' + literal("\r\n") ])
      }

      parse_fetch_attribute(make_body('BODY[1]')) {
        assert_fetch(0, [ "BODY[1] #{literal(@simple_mail.body.raw_source)}" ])
        assert_fetch(1, [ %Q'BODY[1] "#{@mpart_mail.parts[0].body.raw_source}"' ])
      }

      parse_fetch_attribute(make_body('BODY[3]')) {
        assert_fetch(0, [ 'BODY[3] NIL' ])
        assert_fetch(1, [ "BODY[3] #{literal(@mpart_mail.parts[2].body.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[3.1]')) {
        assert_fetch(0, [ 'BODY[3.1] NIL' ])
        assert_fetch(1, [ %Q'BODY[3.1] "#{@mpart_mail.parts[2].message.parts[0].body.raw_source}"' ])
      }

      parse_fetch_attribute(make_body('BODY[4.2.2]')) {
        assert_fetch(0, [ 'BODY[4.2.2] NIL' ])
        assert_fetch(1, [ "BODY[4.2.2] #{literal(@mpart_mail.parts[3].parts[1].message.parts[1].body.raw_source)}" ])
      }

      assert_raise(RIMS::SyntaxError) {
        @parser.parse(make_body('BODY[MIME]'))
      }

      parse_fetch_attribute(make_body('BODY[1.MIME]')) {
        assert_fetch(0, [ "BODY[1.MIME] #{literal(@simple_mail.header.raw_source)}" ])
        assert_fetch(1, [ "BODY[1.MIME] #{literal(@mpart_mail.parts[0].header.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[3.MIME]')) {
        assert_fetch(0, [ 'BODY[3.MIME] NIL' ])
        assert_fetch(1, [ "BODY[3.MIME] #{literal(@mpart_mail.parts[2].header.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[3.1.MIME]')) {
        assert_fetch(0, [ 'BODY[3.1.MIME] NIL' ])
        assert_fetch(1, [ "BODY[3.1.MIME] #{literal(@mpart_mail.parts[2].message.parts[0].header.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[4.2.2.MIME]')) {
        assert_fetch(0, [ 'BODY[4.2.2.MIME] NIL' ])
        assert_fetch(1, [ "BODY[4.2.2.MIME] #{literal(@mpart_mail.parts[3].parts[1].message.parts[1].header.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[1.TEXT]')) {
        assert_fetch(0, [ 'BODY[1.TEXT] NIL' ])
        assert_fetch(1, [ 'BODY[1.TEXT] NIL' ])
      }

      parse_fetch_attribute(make_body('BODY[3.TEXT]')) {
        assert_fetch(0, [ 'BODY[3.TEXT] NIL' ])
        assert_fetch(1, [ "BODY[3.TEXT] #{literal(@mpart_mail.parts[2].message.body.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[3.1.TEXT]')) {
        assert_fetch(0, [ 'BODY[3.1.TEXT] NIL' ])
        assert_fetch(1, [ 'BODY[3.1.TEXT] NIL' ])
      }

      parse_fetch_attribute(make_body('BODY[4.2.TEXT]')) {
        assert_fetch(0, [ 'BODY[4.2.TEXT] NIL' ])
        assert_fetch(1, [ "BODY[4.2.TEXT] #{literal(@mpart_mail.parts[3].parts[1].message.body.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[1.HEADER]')) {
        assert_fetch(0, [ 'BODY[1.HEADER] NIL' ])
        assert_fetch(1, [ 'BODY[1.HEADER] NIL' ])
      }

      parse_fetch_attribute(make_body('BODY[3.HEADER]')) {
        assert_fetch(0, [ 'BODY[3.HEADER] NIL' ])
        assert_fetch(1, [ "BODY[3.HEADER] #{literal(@mpart_mail.parts[2].message.header.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[3.1.HEADER]')) {
        assert_fetch(0, [ 'BODY[3.1.HEADER] NIL' ])
        assert_fetch(1, [ 'BODY[3.1.HEADER] NIL' ])
      }

      parse_fetch_attribute(make_body('BODY[4.2.HEADER]')) {
        assert_fetch(0, [ 'BODY[4.2.HEADER] NIL' ])
        assert_fetch(1, [ "BODY[4.2.HEADER] #{literal(@mpart_mail.parts[3].parts[1].message.header.raw_source)}" ])
      }

      parse_fetch_attribute(make_body('BODY[1.HEADER.FIELDS (To)]')) {
        assert_fetch(0, [ 'BODY[1.HEADER.FIELDS (To)] NIL' ])
        assert_fetch(1, [ 'BODY[1.HEADER.FIELDS (To)] NIL' ])
      }

      parse_fetch_attribute(make_body('BODY[3.HEADER.FIELDS (To)]')) {
        assert_fetch(0, [ 'BODY[3.HEADER.FIELDS (To)] NIL' ])
        assert_fetch(1, [
                       'BODY[3.HEADER.FIELDS (To)] ' +
                       literal(make_header_text(@mpart_mail.parts[2].message.header, select_list: %w[ To ]))
                     ])
      }

      parse_fetch_attribute(make_body('BODY[3.1.HEADER.FIELDS (To)]')) {
        assert_fetch(0, [ 'BODY[3.1.HEADER.FIELDS (To)] NIL' ])
        assert_fetch(1, [ 'BODY[3.1.HEADER.FIELDS (To)] NIL' ])
      }

      parse_fetch_attribute(make_body('BODY[4.2.HEADER.FIELDS (To)]')) {
        assert_fetch(0, [ 'BODY[4.2.HEADER.FIELDS (To)] NIL' ])
        assert_fetch(1, [
                       'BODY[4.2.HEADER.FIELDS (To)] ' +
                       literal(make_header_text(@mpart_mail.parts[3].parts[1].message.header, select_list: %w[ To ]))
                     ])
      }

      parse_fetch_attribute(make_body('BODY[1.HEADER.FIELDS.NOT (To From Subject)]')) {
        assert_fetch(0, [ 'BODY[1.HEADER.FIELDS.NOT (To From Subject)] NIL' ])
        assert_fetch(1, [ 'BODY[1.HEADER.FIELDS.NOT (To From Subject)] NIL' ])
      }

      parse_fetch_attribute(make_body('BODY[3.HEADER.FIELDS.NOT (To From Subject)]')) {
        assert_fetch(0, [ 'BODY[3.HEADER.FIELDS.NOT (To From Subject)] NIL' ])
        assert_fetch(1, [
                       'BODY[3.HEADER.FIELDS.NOT (To From Subject)] ' +
                       literal(make_header_text(@mpart_mail.parts[2].message.header, reject_list: %w[ To From Subject ]))
                     ])
      }

      parse_fetch_attribute(make_body('BODY[3.1.HEADER.FIELDS.NOT (To From Subject)]')) {
        assert_fetch(0, [ 'BODY[3.1.HEADER.FIELDS.NOT (To From Subject)] NIL' ])
        assert_fetch(1, [ 'BODY[3.1.HEADER.FIELDS.NOT (To From Subject)] NIL' ])
      }

      parse_fetch_attribute(make_body('BODY[4.2.HEADER.FIELDS.NOT (To From Subject)]')) {
        assert_fetch(0, [ 'BODY[4.2.HEADER.FIELDS.NOT (To From Subject)] NIL' ])
        assert_fetch(1, [
                       'BODY[4.2.HEADER.FIELDS.NOT (To From Subject)] ' +
                       literal(make_header_text(@mpart_mail.parts[3].parts[1].message.header, reject_list: %w[ To From Subject ]))
                     ])
      }
    end

    def test_parse_body_enabled_seen_flag
      make_fetch_parser{
        add_mail_simple
      }

      parse_fetch_attribute(make_body('BODY[]')) {
        assert_equal(false, get_msg_flag(0, 'seen'))
        assert_fetch(0, [
                       'FLAGS (\Seen \Recent)',
                       "BODY[] #{literal(@simple_mail.raw_source)}"
                     ])
        assert_equal(true, get_msg_flag(0, 'seen'))
        assert_fetch(0, [
                       "BODY[] #{literal(@simple_mail.raw_source)}"
                     ])
        assert_equal(true, get_msg_flag(0, 'seen'))
      }
    end

    def test_parse_body_peek
      make_fetch_parser{
        add_mail_simple
      }

      fetch = @parser.parse(make_body('BODY.PEEK[]'))
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "BODY[] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
    end

    def test_parse_body_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }

      fetch = @parser.parse(make_body('BODY[]'))
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "BODY[] {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
    end

    def test_parse_body_partial
      make_fetch_parser{
        uid = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, uid, 'seen', true)
      }

      s = @simple_mail.raw_source
      assert(100 < s.bytesize && s.bytesize < 1000)

      fetch = @parser.parse(make_body('BODY[]<0.100>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<0> {100}\r\n#{s.byteslice(0, 100)}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<0.1000>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<0> {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<0.4294967295>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<0> {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<0.18446744073709551615>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<0> {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<100.100>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<100> {100}\r\n#{s.byteslice(100, 100)}", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body("BODY[]<#{s.bytesize - 1}.1>"))
      assert_strenc_equal('ascii-8bit', "BODY[]<#{s.bytesize - 1}> {1}\r\n\n", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body("BODY[]<#{s.bytesize}.1>"))
      assert_strenc_equal('ascii-8bit', "BODY[]<#{s.bytesize}> NIL", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<0.0>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<0> \"\"", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body('BODY[]<100.0>'))
      assert_strenc_equal('ascii-8bit', "BODY[]<100> \"\"", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body("BODY[]<#{s.bytesize - 1}.0>"))
      assert_strenc_equal('ascii-8bit', "BODY[]<#{s.bytesize - 1}> \"\"", fetch.call(@folder.msg_list[0]))

      fetch = @parser.parse(make_body("BODY[]<#{s.bytesize}.0>"))
      assert_strenc_equal('ascii-8bit', "BODY[]<#{s.bytesize}> NIL", fetch.call(@folder.msg_list[0]))
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
                          encode_list([ 'text',
                                        'plain',
                                        %w[ charset us-ascii ],
                                        nil,
                                        nil,
                                        '7bit',
                                        203,
                                        9
                                      ]),
                          fetch_body.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'BODYSTRUCTURE ' +
                          encode_list([ 'text',
                                        'plain',
                                        %w[ charset us-ascii ],
                                        nil,
                                        nil,
                                        '7bit',
                                        203,
                                        9
                                      ]),
                          fetch_bodystructure.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'BODY ' +
                          encode_list([ [ 'text', 'plain', %w[ charset us-ascii], nil, nil, nil, 59, 3 ],
                                        [ 'application', 'octet-stream', [], nil, nil, nil, 50 ],
                                        [
                                          'message', 'rfc822', [], nil, nil, nil, 382,
                                          [
                                            'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                            [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                          ],
                                          [
                                            [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 56, 3 ],
                                            [ 'application', 'octet-stream', [], nil, nil, nil, 50 ],
                                            'mixed'
                                          ],
                                          18
                                        ],
                                        [
                                          [ 'image', 'gif', [], nil, nil, nil, 24 ],
                                          [
                                            'message', 'rfc822', [], nil, nil, nil, 612,
                                            [
                                              'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                              [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                            ],
                                            [
                                              [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 48, 3 ],
                                              [
                                                [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 64, 3 ],
                                                [ 'text', 'html', %w[ charset us-ascii ], nil, nil, nil, 90, 5 ],
                                                'alternative'
                                              ],
                                              'mixed'
                                            ],
                                            28
                                          ],
                                          'mixed',
                                        ],
                                        'mixed'
                                      ]),
                          fetch_body.call(@folder.msg_list[1]))
      assert_strenc_equal('ascii-8bit',
                          'BODYSTRUCTURE ' +
                          encode_list([ [ 'text', 'plain', %w[ charset us-ascii], nil, nil, nil, 59, 3 ],
                                        [ 'application', 'octet-stream', [], nil, nil, nil, 50 ],
                                        [
                                          'message', 'rfc822', [], nil, nil, nil, 382,
                                          [
                                            'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                           [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                          ],
                                          [
                                            [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 56, 3 ],
                                            [ 'application', 'octet-stream', [], nil, nil, nil, 50 ],
                                            'mixed'
                                          ],
                                          18
                                        ],
                                        [
                                          [ 'image', 'gif', [], nil, nil, nil, 24 ],
                                          [
                                            'message', 'rfc822', [], nil, nil, nil, 612,
                                            [
                                              'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                              [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                            ],
                                            [
                                              [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 48, 3 ],
                                              [
                                                [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 64, 3 ],
                                                [ 'text', 'html', %w[ charset us-ascii ], nil, nil, nil, 90, 5 ],
                                                'alternative'
                                              ],
                                              'mixed'
                                            ],
                                            28
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
                            '"Fri,  8 Nov 2013 06:47:50 +0900 (JST)"', # Date
                            '"test"',                                  # Subject
                            '((NIL NIL "bar" "nonet.org"))',           # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '((NIL NIL "foo" "nonet.org"))',           # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +')',
                          fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'ENVELOPE (' + [
                            '"Fri, 8 Nov 2013 19:31:03 +0900"',        # Date
                            '"multipart test"',                        # Subject
                            '((NIL NIL "foo" "nonet.com"))',           # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '((NIL NIL "bar" "nonet.com"))',           # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +')',
                          fetch.call(@folder.msg_list[1]))
      assert_strenc_equal('ascii-8bit',
                          'ENVELOPE (' + [
                            '"Fri, 8 Nov 2013 19:31:03 +0900"',        # Date
                            '"=?ISO-2022-JP?B?GyRCJEYkOSRIGyhC?="',    # Subject
                            '((NIL NIL "foo" "nonet.com") ("bar" NIL "bar" "nonet.com"))', # From
                            '((NIL NIL "foo" "nonet.com"))',           # Sender
                            '((NIL NIL "foo" "nonet.com"))',           # Reply-To
                            '((NIL NIL "alice" "test.com") ("bob" NIL "bob" "test.com"))', # To
                            '(("Kate" NIL "kate" "test.com"))',        # Cc
                            '((NIL NIL "foo" "nonet.com"))',           # Bcc
                            '"<20131106081723.5KJU1774292@smtp.testt.com>"',# In-Reply-To
                            '"<20131107214750.445A1255B9F@smtp.nonet.com>"' # Message-Id
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
                          'INTERNALDATE "08-Nov-2013 06:47:50 +0900" ' +
                          'RFC822.SIZE 203',
                          fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (\Recent) ' +
                          'INTERNALDATE "08-Nov-2013 19:31:03 +0900" ' +
                          'RFC822.SIZE 1545',
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
                          'INTERNALDATE "08-Nov-2013 06:47:50 +0900" ' +
                          'RFC822.SIZE 203 ' +
                          'ENVELOPE (' + [
                            '"Fri,  8 Nov 2013 06:47:50 +0900 (JST)"', # Date
                            '"test"',                                  # Subject
                            '((NIL NIL "bar" "nonet.org"))',           # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '((NIL NIL "foo" "nonet.org"))',           # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +') ' +
                          'BODY ' +
                          encode_list([ 'text',
                                        'plain',
                                        %w[ charset us-ascii ],
                                        nil,
                                        nil,
                                        '7bit',
                                        203,
                                        9
                                      ]),
                          fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit',
                          'FLAGS (\Recent) ' +
                          'INTERNALDATE "08-Nov-2013 19:31:03 +0900" ' +
                          'RFC822.SIZE 1545 ' +
                          'ENVELOPE (' + [
                            '"Fri, 8 Nov 2013 19:31:03 +0900"',        # Date
                            '"multipart test"',                        # Subject
                            '((NIL NIL "foo" "nonet.com"))',           # From
                            'NIL',                                     # Sender
                            'NIL',                                     # Reply-To
                            '((NIL NIL "bar" "nonet.com"))',           # To
                            'NIL',                                     # Cc
                            'NIL',                                     # Bcc
                            'NIL',                                     # In-Reply-To
                            'NIL'                                      # Message-Id
                          ].join(' ') +') ' +
                          'BODY ' +
                          encode_list([ [ 'text', 'plain', %w[ charset us-ascii], nil, nil, nil, 59, 3 ],
                                        [ 'application', 'octet-stream', [], nil, nil, nil, 50 ],
                                        [
                                          'message', 'rfc822', [], nil, nil, nil, 382,
                                          [
                                            'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                            [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                          ],
                                          [
                                            [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 56, 3 ],
                                            [ 'application', 'octet-stream', [], nil, nil, nil, 50 ],
                                            'mixed'
                                          ],
                                          18
                                        ],
                                        [
                                          [ 'image', 'gif', [], nil, nil, nil, 24 ],
                                          [
                                            'message', 'rfc822', [], nil, nil, nil, 612,
                                            [
                                              'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                              [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                            ],
                                            [
                                              [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 48, 3 ],
                                              [
                                                [ 'text', 'plain', %w[ charset us-ascii ], nil, nil, nil, 64, 3 ],
                                                [ 'text', 'html', %w[ charset us-ascii ], nil, nil, nil, 90, 5 ],
                                                'alternative'
                                              ],
                                              'mixed'
                                            ],
                                            28
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
      assert_strenc_equal('ascii-8bit', 'INTERNALDATE "08-Nov-2013 06:47:50 +0900"', fetch.call(@folder.msg_list[0]))
      assert_strenc_equal('ascii-8bit', 'INTERNALDATE "08-Nov-2013 19:31:03 +0900"', fetch.call(@folder.msg_list[1]))
    end

    def test_parse_rfc822
      make_fetch_parser{
        add_mail_simple
      }

      fetch = @parser.parse('RFC822')
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "FLAGS (\\Seen \\Recent) RFC822 {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822 {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
    end

    def test_parse_rfc822_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }

      fetch = @parser.parse('RFC822')
      s = @simple_mail.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822 {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
    end

    def test_parse_rfc822_header
      make_fetch_parser{
        add_mail_simple
      }

      fetch = @parser.parse('RFC822.HEADER')
      s = @simple_mail.header.raw_source
      s += "\r\n" unless (s =~ /\r?\n$/)
      s += "\r\n" unless (s =~ /\r?\n\r?\n$/)
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822.HEADER {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
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
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "FLAGS (\\Seen \\Recent) RFC822.TEXT {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822.TEXT {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(true, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
    end

    def test_parse_rfc822_text_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }

      fetch = @parser.parse('RFC822.TEXT')
      s = @simple_mail.body.raw_source
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
      assert_strenc_equal('ascii-8bit', "RFC822.TEXT {#{s.bytesize}}\r\n#{s}", fetch.call(@folder.msg_list[0]))
      assert_equal(false, @mail_store.msg_flag(@inbox_id, @folder.msg_list[0].uid, 'seen'))
    end

    def test_parse_uid
      make_fetch_parser{
        add_mail_simple
        id = add_mail_simple
        add_mail_multipart

        @mail_store.set_msg_flag(@inbox_id, id, 'deleted', true)
        @mail_store.expunge_mbox(@inbox_id)
        assert_equal([ 1, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
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
    end

    def test_encode_header
      s = ''
      s << "To: foo@nonet.org\r\n"
      s << "From: bar@nonet.org\r\n"
      s << "\r\n"
      assert_equal(s, RIMS::Protocol::FetchParser::Utils.encode_header(%w[ To From ].map{|n| [ n, @simple_mail.header[n] ] }))
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
      assert_equal(RIMS::RFC822::Message.new(@mpart_mail.parts[2].body.raw_source).parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3, 1 ]).raw_source)
      assert_equal(RIMS::RFC822::Message.new(@mpart_mail.parts[2].body.raw_source).parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3, 2 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 1 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2 ]).raw_source)
      assert_equal(RIMS::RFC822::Message.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 1 ]).raw_source)
      assert_equal(RIMS::RFC822::Message.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2 ]).raw_source)
      assert_equal(RIMS::RFC822::Message.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[1].parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 1 ]).raw_source)
      assert_equal(RIMS::RFC822::Message.new(@mpart_mail.parts[3].parts[1].body.raw_source).parts[1].parts[1].raw_source,
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
      assert_equal('test', RIMS::Protocol::FetchParser::Utils.get_body_content(@simple_mail, :header)['Subject'])
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_content(@simple_mail, :header, nest_mail: true))
      assert_equal('multipart test', RIMS::Protocol::FetchParser::Utils.get_body_content(@mpart_mail, :header)['Subject'])
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_content(@mpart_mail, :header, nest_mail: true))
      assert_equal('inner multipart', RIMS::Protocol::FetchParser::Utils.get_body_content(@mpart_mail.parts[2], :header, nest_mail: true)['Subject'])
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
