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
    include ProtocolFetchMailSample
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

    def expunge(*uid_list)
      for uid in uid_list
        @mail_store.set_msg_flag(@inbox_id, uid, 'deleted', true)
      end
      @mail_store.expunge_mbox(@inbox_id)
      nil
    end
    private :expunge

    def make_fetch_parser(read_only: false)
      yield if block_given?
      @folder = @mail_store.open_folder(@inbox_id, read_only: read_only).reload
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

    def assert_fetch(msg_idx, expected_message_data_array, encoding: 'ascii-8bit')
      assert_strenc_equal(encoding,
                          message_data_list(expected_message_data_array),
                          @fetch.call(@folder[msg_idx]))
    end
    private :assert_fetch

    def get_msg_flag(msg_idx, flag_name)
      @mail_store.msg_flag(@inbox_id, @folder[msg_idx].uid, flag_name)
    end
    private :get_msg_flag

    def set_msg_flag(msg_idx, flag_name, flag_value)
      @mail_store.set_msg_flag(@inbox_id, @folder[msg_idx].uid, flag_name, flag_value)
      nil
    end
    private :set_msg_flag

    def add_mail_simple
      make_mail_simple
      @mail_store.add_msg(@inbox_id, @simple_mail.raw_source, Time.new(2013, 11, 8, 6, 47, 50, '+09:00'))
    end
    private :add_mail_simple

    def add_mail_multipart
      make_mail_multipart
      @mail_store.add_msg(@inbox_id, @mpart_mail.raw_source, Time.new(2013, 11, 8, 19, 31, 03, '+09:00'))
    end
    private :add_mail_multipart

    def add_mail_mime_subject
      make_mail_mime_subject
      @mail_store.add_msg(@inbox_id, @mime_subject_mail.raw_source, Time.new(2013, 11, 8, 19, 31, 03, '+09:00'))
    end
    private :add_mail_mime_subject

    def add_mail_empty
      make_mail_empty
      @mail_store.add_msg(@inbox_id, @empty_mail.raw_source)
    end
    private :add_mail_empty

    def add_mail_no_body
      make_mail_no_body
      @mail_store.add_msg(@inbox_id, @no_body_mail.raw_source)
    end
    private :add_mail_no_body

    def add_mail_address_header_pattern
      make_mail_address_header_pattern
      @mail_store.add_msg(@inbox_id, @address_header_pattern_mail.raw_source)
    end
    private :add_mail_address_header_pattern

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

      error = assert_raise(RIMS::SyntaxError) {
        @parser.parse(make_body('BODY[MIME]'))
      }
      assert_match(/need for section index/, error.message)

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
      parse_fetch_attribute(make_body('BODY.PEEK[]')) {
        assert_fetch(0, [ "BODY[] #{literal(@simple_mail.raw_source)}" ])
      }
    end

    def test_parse_body_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }
      parse_fetch_attribute(make_body('BODY[]')) {
        assert_equal(false, get_msg_flag(0, 'seen'))
        assert_fetch(0, [ "BODY[] #{literal(@simple_mail.raw_source)}" ])
        assert_equal(false, get_msg_flag(0, 'seen'))
      }
    end

    def test_parse_body_partial
      make_fetch_parser{
        uid = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, uid, 'seen', true)
      }

      msg_txt = @simple_mail.raw_source
      assert(100 < msg_txt.bytesize && msg_txt.bytesize < 1000)
      msg_last_char_idx = msg_txt.bytesize - 1

      parse_fetch_attribute(make_body('BODY[]<0.100>')) {
        assert_fetch(0, [ "BODY[]<0> #{literal(msg_txt.byteslice(0, 100))}" ])
      }

      parse_fetch_attribute(make_body('BODY[]<0.1000>')) {
        assert_fetch(0, [ "BODY[]<0> #{literal(msg_txt)}" ])
      }

      parse_fetch_attribute(make_body("BODY[]<0.#{2**256}>")) { # `2**256' may be Bignum
        assert_fetch(0, [ "BODY[]<0> #{literal(msg_txt)}" ])
      }

      parse_fetch_attribute(make_body('BODY[]<100.100>')) {
        assert_fetch(0, [ "BODY[]<100> #{literal(msg_txt.byteslice(100, 100))}" ])
      }

      parse_fetch_attribute(make_body("BODY[]<#{msg_last_char_idx}.1>")) {
        assert_fetch(0, [ "BODY[]<#{msg_last_char_idx}> #{literal(msg_txt[msg_last_char_idx, 1])}" ])
      }

      parse_fetch_attribute(make_body("BODY[]<#{msg_last_char_idx + 1}.1>")) {
        assert_fetch(0, [ "BODY[]<#{msg_last_char_idx + 1}> NIL" ])
      }

      parse_fetch_attribute(make_body('BODY[]<0.0>')) {
        assert_fetch(0, [ 'BODY[]<0> ""' ])
      }

      parse_fetch_attribute(make_body('BODY[]<100.0>')) {
        assert_fetch(0, [ 'BODY[]<100> ""' ])
      }

      parse_fetch_attribute(make_body("BODY[]<#{msg_last_char_idx}.0>")) {
        assert_fetch(0, [ %Q'BODY[]<#{msg_last_char_idx}> ""' ])
      }

      parse_fetch_attribute(make_body("BODY[]<#{msg_last_char_idx + 1}.0>")) {
        assert_fetch(0, [ "BODY[]<#{msg_last_char_idx + 1}> NIL" ])
      }
    end

    def test_parse_bodystructure
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
        add_mail_empty
        add_mail_no_body
      }

      for fetch_att_bodystruct in %w[ BODY BODYSTRUCTURE ]
        parse_fetch_attribute(fetch_att_bodystruct) {
          assert_fetch(0, [
                         "#{fetch_att_bodystruct} " +
                         encode_list([ 'TEXT',
                                       'PLAIN',
                                       %w[ charset us-ascii ],
                                       nil,
                                       nil,
                                       '7BIT',
                                       @simple_mail.raw_source.bytesize,
                                       @simple_mail.raw_source.each_line.count
                                     ])
                       ])
          assert_fetch(1, [
                         "#{fetch_att_bodystruct} " +
                         encode_list([ [ 'TEXT', 'PLAIN', %w[ charset us-ascii], nil, nil, nil,
                                         @mpart_mail.parts[0].raw_source.bytesize,
                                         @mpart_mail.parts[0].raw_source.each_line.count
                                       ],
                                       [ 'APPLICATION', 'OCTET-STREAM', [], nil, nil, nil,
                                         @mpart_mail.parts[1].raw_source.bytesize
                                       ],
                                       [ 'MESSAGE', 'RFC822', [], nil, nil, nil,
                                         @mpart_mail.parts[2].raw_source.bytesize,
                                         [ 'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                           [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                         ],
                                         [ [ 'TEXT', 'PLAIN', %w[ charset us-ascii ], nil, nil, nil,
                                             @mpart_mail.parts[2].message.parts[0].raw_source.bytesize,
                                             @mpart_mail.parts[2].message.parts[0].raw_source.each_line.count
                                           ],
                                           [ 'APPLICATION', 'OCTET-STREAM', [], nil, nil, nil,
                                             @mpart_mail.parts[2].message.parts[1].raw_source.bytesize
                                           ],
                                           'MIXED'
                                         ],
                                         @mpart_mail.parts[2].raw_source.each_line.count
                                       ],
                                       [ [ 'IMAGE', 'GIF', [], nil, nil, nil,
                                           @mpart_mail.parts[3].parts[0].raw_source.bytesize
                                         ],
                                         [ 'MESSAGE', 'RFC822', [], nil, nil, nil,
                                           @mpart_mail.parts[3].parts[1].raw_source.bytesize,
                                           [ 'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                             [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                           ],
                                           [ [ 'TEXT', 'PLAIN', %w[ charset us-ascii ], nil, nil, nil,
                                               @mpart_mail.parts[3].parts[1].message.parts[0].raw_source.bytesize,
                                               @mpart_mail.parts[3].parts[1].message.parts[0].raw_source.each_line.count
                                             ],
                                             [ [ 'TEXT', 'PLAIN', %w[ charset us-ascii ], nil, nil, nil,
                                                 @mpart_mail.parts[3].parts[1].message.parts[1].parts[0].raw_source.bytesize,
                                                 @mpart_mail.parts[3].parts[1].message.parts[1].parts[0].raw_source.each_line.count
                                               ],
                                               [ 'TEXT', 'HTML', %w[ charset us-ascii ], nil, nil, nil,
                                                 @mpart_mail.parts[3].parts[1].message.parts[1].parts[1].raw_source.bytesize,
                                                 @mpart_mail.parts[3].parts[1].message.parts[1].parts[1].raw_source.each_line.count
                                               ],
                                               'ALTERNATIVE'
                                             ],
                                             'MIXED'
                                           ],
                                           @mpart_mail.parts[3].parts[1].raw_source.each_line.count
                                         ],
                                         'MIXED',
                                       ],
                                       'MIXED'
                                     ])
                       ])
          assert_fetch(2, [
                         "#{fetch_att_bodystruct} " +
                         encode_list([ 'APPLICATION',
                                       'OCTET-STREAM',
                                       [],
                                       nil,
                                       nil,
                                       nil,
                                       @empty_mail.raw_source.bytesize
                                     ])
                       ])
          assert_fetch(3, [
                         "#{fetch_att_bodystruct} " +
                         encode_list([ 'APPLICATION',
                                       'OCTET-STREAM',
                                       [],
                                       nil,
                                       nil,
                                       nil,
                                       @no_body_mail.raw_source.bytesize
                                     ])
                       ])
        }
      end
    end

    def test_parse_envelope
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
        add_mail_mime_subject
        add_mail_empty
        add_mail_no_body
        add_mail_address_header_pattern
      }
      parse_fetch_attribute('ENVELOPE') {
        assert_fetch(0, [
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
        assert_fetch(2, [
                       'ENVELOPE',
                       [ '"Fri, 8 Nov 2013 19:31:03 +0900"',        # Date
                         '"=?ISO-2022-JP?B?GyRCJEYkOSRIGyhC?="',    # Subject
                         '((NIL NIL "foo" "nonet.com") ("bar" NIL "bar" "nonet.com"))', # From
                         '((NIL NIL "foo" "nonet.com"))',           # Sender
                         '((NIL NIL "foo" "nonet.com"))',           # Reply-To
                         '((NIL NIL "alice" "test.com") ("bob" NIL "bob" "test.com"))', # To
                         '(("Kate" NIL "kate" "test.com"))',        # Cc
                         '((NIL NIL "foo" "nonet.com"))',           # Bcc
                         '"<20131106081723.5KJU1774292@smtp.test.com>"', # In-Reply-To
                         '"<20131107214750.445A1255B9F@smtp.nonet.com>"' # Message-Id
                       ]
                     ])
        assert_fetch(3, [ 'ENVELOPE (NIL NIL NIL NIL NIL NIL NIL NIL NIL NIL)' ])
        assert_fetch(4, [ 'ENVELOPE (NIL NIL NIL NIL NIL NIL NIL NIL NIL NIL)' ])
        assert_fetch(5, [
                       'ENVELOPE',
                       [ '"Fri,  8 Nov 2013 06:47:50 +0900 (JST)"', # Date
                         '"test"',                                  # Subject
                         '((NIL NIL "bar" "nonet.org"))',           # From
                         'NIL',                                     # Sender
                         'NIL',                                     # Reply-To
                         '(("foo@nonet.org" NIL "foo" "nonet.org"))', # To
                         'NIL',                                     # Cc
                         'NIL',                                     # Bcc
                         'NIL',                                     # In-Reply-To
                         'NIL'                                      # Message-Id
                       ]
                     ])
      }
    end

    def test_parse_fast
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      parse_fetch_attribute('FAST') {
        assert_fetch(0, [
                       'FLAGS (\Recent)',
                       'INTERNALDATE "08-Nov-2013 06:47:50 +0900"',
                       "RFC822.SIZE #{@simple_mail.raw_source.bytesize}"
                     ])
        assert_fetch(1, [
                       'FLAGS (\Recent)',
                       'INTERNALDATE "08-Nov-2013 19:31:03 +0900"',
                       "RFC822.SIZE #{@mpart_mail.raw_source.bytesize}"
                     ])
      }
    end

    def test_parse_flags
      make_fetch_parser{
        add_mail_simple
        add_mail_simple
        add_mail_simple
        add_mail_simple
        add_mail_simple
        add_mail_simple
        add_mail_simple
        add_mail_simple
      }

      set_msg_flag(0, 'recent', false)

      set_msg_flag(1, 'recent', true)

      set_msg_flag(2, 'recent', false)
      set_msg_flag(2, 'answered', true)

      set_msg_flag(3, 'recent', false)
      set_msg_flag(3, 'flagged', true)

      set_msg_flag(4, 'recent', false)
      set_msg_flag(4, 'deleted', true)

      set_msg_flag(5, 'recent', false)
      set_msg_flag(5, 'seen', true)

      set_msg_flag(6, 'recent', false)
      set_msg_flag(6, 'draft', true)

      set_msg_flag(7, 'recent', true)
      set_msg_flag(7, 'answered', true)
      set_msg_flag(7, 'flagged', true)
      set_msg_flag(7, 'deleted', true)
      set_msg_flag(7, 'seen', true)
      set_msg_flag(7, 'draft', true)

      parse_fetch_attribute('FLAGS') {
        assert_fetch(0, [ 'FLAGS ()' ])
        assert_fetch(1, [ 'FLAGS (\Recent)' ])
        assert_fetch(2, [ 'FLAGS (\Answered)' ])
        assert_fetch(3, [ 'FLAGS (\Flagged)' ])
        assert_fetch(4, [ 'FLAGS (\Deleted)' ])
        assert_fetch(5, [ 'FLAGS (\Seen)' ])
        assert_fetch(6, [ 'FLAGS (\Draft)' ])
        assert_fetch(7, [
                       'FLAGS',
                       RIMS::MailStore::MSG_FLAG_NAMES.map{|n| "\\#{n.capitalize}" }
                     ])
      }
    end

    def test_parse_full
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      parse_fetch_attribute('FULL') {
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
                       ],
                       'BODY',
                       encode_list([ 'TEXT',
                                     'PLAIN',
                                     %w[ charset us-ascii ],
                                     nil,
                                     nil,
                                     '7BIT',
                                     @simple_mail.raw_source.bytesize,
                                     @simple_mail.raw_source.each_line.count
                                   ])
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
                       ],
                       'BODY',
                       encode_list([ [ 'TEXT', 'PLAIN', %w[ charset us-ascii], nil, nil, nil,
                                       @mpart_mail.parts[0].raw_source.bytesize,
                                       @mpart_mail.parts[0].raw_source.each_line.count
                                     ],
                                     [ 'APPLICATION', 'OCTET-STREAM', [], nil, nil, nil,
                                       @mpart_mail.parts[1].raw_source.bytesize
                                     ],
                                     [ 'MESSAGE', 'RFC822', [], nil, nil, nil,
                                       @mpart_mail.parts[2].raw_source.bytesize,
                                       [ 'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                         [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                       ],
                                       [ [ 'TEXT', 'PLAIN', %w[ charset us-ascii ], nil, nil, nil,
                                           @mpart_mail.parts[2].message.parts[0].raw_source.bytesize,
                                           @mpart_mail.parts[2].message.parts[0].raw_source.each_line.count
                                         ],
                                         [ 'APPLICATION', 'OCTET-STREAM', [], nil, nil, nil,
                                           @mpart_mail.parts[2].message.parts[1].raw_source.bytesize
                                         ],
                                         'MIXED'
                                       ],
                                       @mpart_mail.parts[2].raw_source.each_line.count
                                     ],
                                     [
                                       [ 'IMAGE', 'GIF', [], nil, nil, nil,
                                         @mpart_mail.parts[3].parts[0].raw_source.bytesize
                                       ],
                                       [ 'MESSAGE', 'RFC822', [], nil, nil, nil,
                                         @mpart_mail.parts[3].parts[1].raw_source.bytesize,
                                         [ 'Fri, 8 Nov 2013 19:31:03 +0900', 'inner multipart',
                                           [ [ nil, nil, 'foo', 'nonet.com' ] ], nil, nil, [ [ nil, nil, 'bar', 'nonet.com' ] ], nil, nil, nil, nil
                                         ],
                                         [ [ 'TEXT', 'PLAIN', %w[ charset us-ascii ], nil, nil, nil,
                                             @mpart_mail.parts[3].parts[1].message.parts[0].raw_source.bytesize,
                                             @mpart_mail.parts[3].parts[1].message.parts[0].raw_source.each_line.count
                                           ],
                                           [ [ 'TEXT', 'PLAIN', %w[ charset us-ascii ], nil, nil, nil,
                                               @mpart_mail.parts[3].parts[1].message.parts[1].parts[0].raw_source.bytesize,
                                               @mpart_mail.parts[3].parts[1].message.parts[1].parts[0].raw_source.each_line.count
                                             ],
                                             [ 'TEXT', 'HTML', %w[ charset us-ascii ], nil, nil, nil,
                                               @mpart_mail.parts[3].parts[1].message.parts[1].parts[1].raw_source.bytesize,
                                               @mpart_mail.parts[3].parts[1].message.parts[1].parts[1].raw_source.each_line.count
                                             ],
                                             'ALTERNATIVE'
                                           ],
                                           'MIXED'
                                         ],
                                         @mpart_mail.parts[3].parts[1].raw_source.each_line.count
                                       ],
                                       'MIXED',
                                     ],
                                     'MIXED'
                                   ])
                       ])
      }
    end

    def test_parse_internaldate
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      parse_fetch_attribute('INTERNALDATE') {
        assert_fetch(0, [ 'INTERNALDATE "08-Nov-2013 06:47:50 +0900"' ])
        assert_fetch(1, [ 'INTERNALDATE "08-Nov-2013 19:31:03 +0900"' ])
      }
    end

    def test_parse_rfc822
      make_fetch_parser{
        add_mail_simple
      }
      parse_fetch_attribute('RFC822') {
        assert_equal(false, get_msg_flag(0, 'seen'))
        assert_fetch(0, [
                       'FLAGS (\Seen \Recent)',
                       "RFC822 #{literal(@simple_mail.raw_source)}"
                     ])
        assert_equal(true, get_msg_flag(0, 'seen'))
        assert_fetch(0, [
                       "RFC822 #{literal(@simple_mail.raw_source)}"
                     ])
        assert_equal(true, get_msg_flag(0, 'seen'))
      }
    end

    def test_parse_rfc822_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }
      parse_fetch_attribute('RFC822') {
        assert_equal(false, get_msg_flag(0, 'seen'))
        assert_fetch(0, [ "RFC822 #{literal(@simple_mail.raw_source)}" ])
        assert_equal(false, get_msg_flag(0, 'seen'))
      }
    end

    def test_parse_rfc822_header
      make_fetch_parser{
        add_mail_simple
      }
      parse_fetch_attribute('RFC822.HEADER') {
        assert_equal(false, get_msg_flag(0, 'seen'))
        assert_fetch(0, [ "RFC822.HEADER #{literal(@simple_mail.header.raw_source)}" ])
        assert_equal(false, get_msg_flag(0, 'seen'))
      }
    end

    def test_parse_rfc822_size
      make_fetch_parser{
        add_mail_simple
      }
      parse_fetch_attribute('RFC822.SIZE') {
        assert_fetch(0, [ "RFC822.SIZE #{@simple_mail.raw_source.bytesize}" ])
      }
    end

    def test_parse_rfc822_text
      make_fetch_parser{
        add_mail_simple
      }
      parse_fetch_attribute('RFC822.TEXT') {
        assert_equal(false, get_msg_flag(0, 'seen'))
        assert_fetch(0, [
                       'FLAGS (\Seen \Recent)',
                       "RFC822.TEXT #{literal(@simple_mail.body.raw_source)}"
                     ])
        assert_equal(true, get_msg_flag(0, 'seen'))
        assert_fetch(0, [
                       "RFC822.TEXT #{literal(@simple_mail.body.raw_source)}"
                     ])
        assert_equal(true, get_msg_flag(0, 'seen'))
      }
    end

    def test_parse_rfc822_text_read_only
      make_fetch_parser(read_only: true) {
        add_mail_simple
      }
      parse_fetch_attribute('RFC822.TEXT') {
        assert_equal(false, get_msg_flag(0, 'seen'))
        assert_fetch(0, [ "RFC822.TEXT #{literal(@simple_mail.body.raw_source)}" ])
        assert_equal(false, get_msg_flag(0, 'seen'))
      }
    end

    def test_parse_uid
      make_fetch_parser{
        add_mail_simple
        add_mail_simple
        add_mail_multipart
        expunge(2)
        assert_equal([ 1, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      parse_fetch_attribute('UID') {
        assert_fetch(0, [ 'UID 1' ])
        assert_fetch(1, [ 'UID 3' ])
      }
    end

    def test_parse_group
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      parse_fetch_attribute([ :group ]) {
        assert_fetch(0, [ '()' ])
        assert_fetch(1, [ '()' ])
      }
      parse_fetch_attribute([ :group, 'RFC822.SIZE' ]) {
        assert_fetch(0, [ "(RFC822.SIZE #{@simple_mail.raw_source.bytesize})" ])
        assert_fetch(1, [ "(RFC822.SIZE #{@mpart_mail.raw_source.bytesize})" ])
      }
    end
  end

  class ProtocolFetchParserUtilsTest < Test::Unit::TestCase
    include ProtocolFetchMailSample

    def test_encode_header
      assert_equal("To: foo@nonet.org\r\n" +
                   "From: bar@nonet.org\r\n" +
                   "\r\n",
                   RIMS::Protocol::FetchParser::Utils.encode_header([ %w[ To foo@nonet.org ],
                                                                      %w[ From bar@nonet.org ]
                                                                    ]))
    end

    def test_get_body_section
      make_mail_simple
      make_mail_multipart

      assert_equal(@simple_mail,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, []))
      assert_equal(@simple_mail,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, [ 1 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, [ 1, 1 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, [ 2 ]))

      assert_equal(@mpart_mail.raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, []).raw_source)
      assert_equal(@mpart_mail.parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 1 ]).raw_source)
      assert_equal(@mpart_mail.parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 2 ]).raw_source)
      assert_equal(@mpart_mail.parts[2].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3 ]).raw_source)
      assert_equal(@mpart_mail.parts[2].message.parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3, 1 ]).raw_source)
      assert_equal(@mpart_mail.parts[2].message.parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3, 2 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 1 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[1].message.parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 1 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[1].message.parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[1].message.parts[1].parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 1 ]).raw_source)
      assert_equal(@mpart_mail.parts[3].parts[1].message.parts[1].parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 2 ]).raw_source)
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 5 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 3, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 3 ]))

      error = assert_raise(RIMS::SyntaxError) {
        RIMS::Protocol::FetchParser::Utils.get_body_section(@simple_mail, [ 0 ])
      }
      assert_match(/not a none-zero body section number/, error.message)

      error = assert_raise(RIMS::SyntaxError) {
        RIMS::Protocol::FetchParser::Utils.get_body_section(@mpart_mail, [ 4, 2, 2, 0 ])
      }
      assert_match(/not a none-zero body section number/, error.message)
    end

    def test_get_body_content
      make_mail_simple
      make_mail_multipart

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
