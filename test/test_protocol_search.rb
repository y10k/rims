# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolSearchParserTest < Test::Unit::TestCase
    include ProtocolFetchMailSample

    def setup
      @kv_store = {}
      @kvs_open = proc{|path| RIMS::Hash_KeyValueStore.new(@kv_store[path] = {}) }
      @mail_store = RIMS::MailStore.new(RIMS::DB::Meta.new(@kvs_open.call('meta')),
                                        RIMS::DB::Message.new(@kvs_open.call('msg'))) {|mbox_id|
        RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
      @inbox_id = @mail_store.add_mbox('INBOX')
    end

    def add_msg(msg_txt, *optional_args)
      @mail_store.add_msg(@inbox_id, msg_txt, *optional_args)
    end
    private :add_msg

    def get_msg_flag(uid, flag_name)
      @mail_store.msg_flag(@inbox_id, uid, flag_name)
    end
    private :get_msg_flag

    def set_msg_flag(uid, flag_name, flag_value)
      @mail_store.set_msg_flag(@inbox_id, uid, flag_name, flag_value)
      nil
    end
    private :set_msg_flag

    def expunge(*uid_list)
      for uid in uid_list
        set_msg_flag(uid, 'deleted', true)
      end
      @mail_store.expunge_mbox(@inbox_id)
      nil
    end
    private :expunge

    def assert_msg_uid(*uid_list)
      assert_equal(uid_list, @mail_store.each_msg_uid(@inbox_id).to_a)
    end
    private :assert_msg_uid

    def assert_msg_flag(flag_name, *flag_value_list)
      uid_list = @mail_store.each_msg_uid(@inbox_id).to_a
      assert_equal(uid_list.map{|uid| get_msg_flag(uid, flag_name) }, flag_value_list)
    end
    private :assert_msg_flag

    def make_search_parser(charset: nil)
      yield
      @folder = @mail_store.open_folder(@inbox_id, read_only: true).reload
      @parser = RIMS::Protocol::SearchParser.new(@mail_store, @folder)
      @parser.charset = charset if charset
      nil
    end
    private :make_search_parser

    def parse_search_key(search_key_list)
      @cond = @parser.parse(search_key_list)
      begin
        yield
      ensure
        @cond = nil
      end
    end
    private :parse_search_key

    def assert_search_cond(msg_idx, expected_found_flag)
      assert_equal(expected_found_flag, @cond.call(@folder[msg_idx]))
    end
    private :assert_search_cond

    def assert_search_syntax_error(search_key_list, expected_error_message)
      error = assert_raise(RIMS::SyntaxError) {
        @parser.parse(search_key_list)
      }
      case (expected_error_message)
      when String
        assert_equal(expected_error_message, error.message)
      when Regexp
        assert_match(expected_error_message, error.message)
      else
        flunk
      end
    end
    private :assert_search_syntax_error

    def test_parse_all
      make_search_parser{
        add_msg('foo')
        assert_msg_uid(1)
      }

      parse_search_key([ 'ALL' ]) {
        assert_search_cond(0, true)
      }
    end

    def test_parse_answered
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'answered', true)
        assert_msg_flag('answered', true, false)
      }

      parse_search_key([ 'ANSWERED' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
      }
    end

    def test_parse_bcc
      make_search_parser{
        add_msg("Bcc: foo\r\n" +
                "\r\n" +
                "foo")
        add_msg("Bcc: bar\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'BCC', 'foo' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'BCC' ], /need for a search string/)
      assert_search_syntax_error([ 'BCC', [ :group, 'foo' ] ], /search string expected as <String> but was/)
    end

    def test_parse_before
      make_search_parser{
        add_msg('foo', Time.parse('2013-11-07 12:34:56'))
        add_msg('foo', Time.parse('2013-11-08 12:34:56'))
        add_msg('foo', Time.parse('2013-11-09 12:34:56'))
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'BEFORE', '08-Nov-2013' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'BEFORE' ], /need for a search date/)
      assert_search_syntax_error([ 'BEFORE', '99-Nov-2013' ], /search date is invalid/)
      assert_search_syntax_error([ 'BEFORE', [ :group, '08-Nov-2013'] ], /search date string expected as <String> but was/)
    end

    def test_parse_body
      make_search_parser{
        add_msg("Content-Type: text/plain\r\n" +
                "\r\n" +
                "foo")
        add_msg("Content-Type: text/plain\r\n" +
                "\r\n" +
                "bar")
        add_msg("Content-Type: message/rfc822\r\n" +
                "\r\n" +
                "foo")
        add_msg(<<-'EOF')
Content-Type: multipart/alternative; boundary="1383.905529.351297"

--1383.905529.351297
Content-Type: text/plain

foo
--1383.905529.351297
Content-Type: text/html

<html><body><p>foo</p></body></html>
--1383.905529.351297--
        EOF

        assert_msg_uid(1, 2, 3, 4)
      }

      parse_search_key([ 'BODY', 'foo' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, true)
        assert_search_cond(3, false) # ignored text part of multipart message.
      }

      assert_search_syntax_error([ 'BODY' ], /need for a search string/)
      assert_search_syntax_error([ 'BODY', [ :group, 'foo' ] ], /search string expected as <String> but was/)
    end

    def test_parse_cc
      make_search_parser{
        add_msg("Cc: foo\r\n" +
                "\r\n" +
                "foo")
        add_msg("Cc: bar\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'CC', 'foo' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'CC' ], /need for a search string/)
      assert_search_syntax_error([ 'CC', [ :group, 'foo' ] ], /search string expected as <String> but was/)
    end

    def test_parse_deleted
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'deleted', true)
        assert_msg_flag('deleted', true, false)
      }

      parse_search_key([ 'DELETED' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
      }
    end

    def test_parse_draft
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'draft', true)
        assert_msg_flag('draft', true, false)
      }

      parse_search_key([ 'DRAFT' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
      }
    end

    def test_parse_flagged
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'flagged', true)
        assert_msg_flag('flagged', true, false)
      }

      parse_search_key([ 'FLAGGED' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
      }
    end

    def test_parse_from
      make_search_parser{
        add_msg("From: foo\r\n" +
                "\r\n" +
                "foo")
        add_msg("From: bar\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'FROM', 'foo' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'FROM' ], /need for a search string/)
      assert_search_syntax_error([ 'FROM', [ :group, 'foo' ] ], /search string expected as <String> but was/)
    end

    def test_parse_header
      make_search_parser{
        add_msg("X-Foo: alice\r\n" +
                "X-Bar: bob\r\n" +
                "\r\n" +
                "foo")
        add_msg("X-Foo: bob\r\n" +
                "X-Bar: alice\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'HEADER', 'x-foo', 'alice' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }

      parse_search_key([ 'HEADER', 'x-foo', 'bob' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
        assert_search_cond(2, false)
      }

      parse_search_key([ 'HEADER', 'x-bar', 'alice' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
        assert_search_cond(2, false)
      }

      parse_search_key([ 'HEADER', 'x-bar', 'bob' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'HEADER' ], /need for a search string/)
      assert_search_syntax_error([ 'HEADER', 'Received' ], /need for a search string/)
      assert_search_syntax_error([ 'HEADER', 'Received', [ :group, 'foo' ] ], /search string expected as <String> but was/)
      assert_search_syntax_error([ 'HEADER', [ :group, 'Received' ], 'foo' ], /search string expected as <String> but was/)
    end

    def test_parse_keyword
      make_search_parser{
        add_msg('')
        assert_msg_uid(1)
      }

      parse_search_key([ 'KEYWORD', 'foo' ]) {
        assert_search_cond(0, false) # always false
      }

      assert_search_syntax_error([ 'KEYWORD' ], /need for a search string/)
      assert_search_syntax_error([ 'KEYWORD', [ :group, 'foo' ] ], /search string expected as <String> but was/)
    end

    def test_parse_larger
      make_search_parser{
        add_msg('foo')
        add_msg('1234')
        add_msg('bar')
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'LARGER', '3' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'LARGER' ], /need for a octet size/)
      assert_search_syntax_error([ 'LARGER', [ :group, '3' ] ], /octet size is expected as numeric string but was/)
      assert_search_syntax_error([ 'LARGER', 'nonum' ], /octet size is expected as numeric string but was/)
    end

    def test_parse_new
      make_search_parser{
        add_msg('foo')
        add_msg('bar')
        add_msg('baz')
        assert_msg_uid(1, 2, 3)

        set_msg_flag(3, 'recent', false)
        set_msg_flag(2, 'seen', true)
        assert_msg_flag('recent', true,  true, false)
        assert_msg_flag('seen',   false, true, false)
      }

      parse_search_key([ 'NEW' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }
    end

    def test_parse_not
      make_search_parser{
        add_msg('foo')
        add_msg('1234')
        add_msg('bar')
        assert_msg_uid(1, 2, 3)

        set_msg_flag(1, 'answered', true)
        assert_msg_flag('answered', true, false, false)
      }

      parse_search_key([ 'NOT', 'LARGER', '3' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, true)
      }

      parse_search_key([ 'NOT', 'ANSWERED' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
        assert_search_cond(2, true)
      }

      assert_search_syntax_error([ 'NOT' ], 'unexpected end of search key.')
    end

    def test_parse_old
      make_search_parser{
        add_msg('foo')
        add_msg('bar')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'recent', false)
        assert_msg_flag('recent', false, true)
      }

      parse_search_key([ 'OLD' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
      }
    end

    def test_parse_on
      make_search_parser{
        add_msg('foo', Time.parse('2013-11-07 12:34:56'))
        add_msg('foo', Time.parse('2013-11-08 12:34:56'))
        add_msg('foo', Time.parse('2013-11-09 12:34:56'))
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'ON', '08-Nov-2013' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'ON' ], /need for a search date/)
      assert_search_syntax_error([ 'ON', '99-Nov-2013' ], /search date is invalid/)
      assert_search_syntax_error([ 'ON', [ :group, '08-Nov-2013'] ], /search date string expected as <String> but was/)
    end

    def test_parse_or
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2, 3, 4)

        set_msg_flag(1, 'answered', true)
        set_msg_flag(2, 'answered', true)
        set_msg_flag(1, 'flagged', true)
        set_msg_flag(3, 'flagged', true)
        assert_msg_flag('answered', true, true,  false, false)
        assert_msg_flag('flagged',  true, false, true,  false)
      }

      parse_search_key([ 'OR', 'ANSWERED', 'FLAGGED' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, true)
        assert_search_cond(2, true)
        assert_search_cond(3, false)

      }

      assert_search_syntax_error([ 'OR' ], 'unexpected end of search key.')
      assert_search_syntax_error([ 'OR', 'ANSWERED' ], 'unexpected end of search key.')
    end

    def test_parse_recent
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'recent', false)
        assert_msg_flag('recent', false, true)
      }

      parse_search_key([ 'RECENT' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
      }
    end

    def test_parse_seen
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'seen', true)
        assert_msg_flag('seen', true, false)
      }

      parse_search_key([ 'SEEN' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
      }
    end

    def test_parse_sentbefore
      make_search_parser{
        add_msg("Date: Thu, 07 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg("Date: Fri, 08 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg("Date: Sat, 09 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3, 4)
      }

      parse_search_key([ 'SENTBEFORE', '08-Nov-2013' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
        assert_search_cond(3, false)
      }

      assert_search_syntax_error([ 'SENTBEFORE' ], /need for a search date/)
      assert_search_syntax_error([ 'SENTBEFORE', '99-Nov-2013' ], /search date is invalid/)
      assert_search_syntax_error([ 'SENTBEFORE', [ :group, '08-Nov-2013'] ], /search date string expected as <String> but was/)
    end

    def test_parse_senton
      make_search_parser{
        add_msg("Date: Thu, 07 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg("Date: Fri, 08 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg("Date: Sat, 09 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3, 4)
      }

      parse_search_key([ 'SENTON', '08-Nov-2013' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
        assert_search_cond(2, false)
        assert_search_cond(3, false)
      }

      assert_search_syntax_error([ 'SENTON' ], /need for a search date/)
      assert_search_syntax_error([ 'SENTON', '99-Nov-2013' ], /search date is invalid/)
      assert_search_syntax_error([ 'SENTON', [ :group, '08-Nov-2013'] ], /search date string expected as <String> but was/)
    end

    def test_parse_sentsince
      make_search_parser{
        add_msg("Date: Thu, 07 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg("Date: Fri, 08 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg("Date: Sat, 09 Nov 2013 12:34:56 +0900\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3, 4)
      }

      parse_search_key([ 'SENTSINCE', '08-Nov-2013' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, false)
        assert_search_cond(2, true)
        assert_search_cond(3, false)
      }

      assert_search_syntax_error([ 'SENTSINCE' ], /need for a search date/)
      assert_search_syntax_error([ 'SENTSINCE', '99-Nov-2013' ], /search date is invalid/)
      assert_search_syntax_error([ 'SENTSINCE', [ :group, '08-Nov-2013'] ], /search date string expected as <String> but was/)
    end

    def test_parse_since
      make_search_parser{
        add_msg('foo', Time.parse('2013-11-07 12:34:56'))
        add_msg('foo', Time.parse('2013-11-08 12:34:56'))
        add_msg('foo', Time.parse('2013-11-09 12:34:56'))
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'SINCE', '08-Nov-2013' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, false)
        assert_search_cond(2, true)
      }

      assert_search_syntax_error([ 'SINCE' ], /need for a search date/)
      assert_search_syntax_error([ 'SINCE', '99-Nov-2013' ], /search date is invalid/)
      assert_search_syntax_error([ 'SINCE', [ :group, '08-Nov-2013'] ], /search date string expected as <String> but was/)
    end

    def test_parse_smaller
      make_search_parser{
        add_msg('foo')
        add_msg('12')
        add_msg('bar')
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'SMALLER', '3' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'SMALLER' ], /need for a octet size/)
      assert_search_syntax_error([ 'SMALLER', [ :group, '3' ] ], /octet size is expected as numeric string but was/)
      assert_search_syntax_error([ 'SMALLER', 'nonum' ], /octet size is expected as numeric string but was/)
    end

    def test_parse_subject
      make_search_parser{
        add_msg("Subject: foo\r\n" +
                "\r\n" +
                "foo")
        add_msg("Subject: bar\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'SUBJECT', 'foo' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'SUBJECT' ], /need for a search string/)
      assert_search_syntax_error([ 'SUBJECT', [ :group, 'foo' ] ], /search string expected as <String> but was/)
    end

    def test_parse_text
      make_search_parser{
        add_msg("Content-Type: text/plain\r\n" +
                "Subject: foo\r\n" +
                "\r\n" +
                "bar")
        assert_msg_uid(1)
      }

      parse_search_key([ 'TEXT', 'jec' ]) {
        assert_search_cond(0, true)
      }
      parse_search_key([ 'TEXT', 'foo' ]) {
        assert_search_cond(0, true)
      }
      parse_search_key([ 'TEXT', 'bar' ]) {
        assert_search_cond(0, true)
      }
      parse_search_key([ 'TEXT', 'baz' ]) {
        assert_search_cond(0, false)
      }

      assert_search_syntax_error([ 'TEXT' ], /need for a search string/)
      assert_search_syntax_error([ 'TEXT', [ :group, 'foo'] ], /search string expected as <String> but was/)
    end

    def test_parse_text_multipart
      make_mail_multipart
      make_search_parser{
        add_msg(@mpart_mail.raw_source)
        assert_msg_uid(1)
      }

      parse_search_key([ 'TEXT', 'Subject: multipart test' ]) {
        assert_search_cond(0, true)
      }
      parse_search_key([ 'TEXT', 'Subject: inner multipart' ]) {
        assert_search_cond(0, true)
      }
      parse_search_key([ 'TEXT', 'Hello world.' ]) {
        assert_search_cond(0, true)
      }
      parse_search_key([ 'TEXT', 'HALO' ]) {
        assert_search_cond(0, true)
      }
      parse_search_key([ 'TEXT', 'detarame' ]) {
        assert_search_cond(0, false)
      }
    end

    def test_parse_to
      make_search_parser{
        add_msg("To: foo\r\n" +
                "\r\n" +
                "foo")
        add_msg("To: bar\r\n" +
                "\r\n" +
                "foo")
        add_msg('foo')
        assert_msg_uid(1, 2, 3)
      }

      parse_search_key([ 'TO', 'foo' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
      }

      assert_search_syntax_error([ 'TO' ], /need for a search string/)
      assert_search_syntax_error([ 'TO', [ :group, 'foo' ] ], /search string expected as <String> but was/)
    end

    def test_parse_uid
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        expunge(1, 3, 5)
        assert_msg_uid(2, 4, 6)
      }

      parse_search_key([ 'UID', '2,*' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, true)
      }

      begin
        @parser.parse([ 'UID', 'detarame' ])
      rescue
        error = $!
      end
      assert_kind_of(RIMS::SyntaxError, error)
    end

    def test_parse_unanswered
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'answered', true)
        assert_msg_flag('answered', true, false)
      }

      parse_search_key([ 'UNANSWERED' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
      }
    end

    def test_parse_undeleted
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'deleted', true)
        assert_msg_flag('deleted', true, false)
      }

      parse_search_key([ 'UNDELETED' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
      }
    end

    def test_parse_undraft
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'draft', true)
        assert_msg_flag('draft', true, false)
      }

      parse_search_key([ 'UNDRAFT' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
      }
    end

    def test_parse_unflagged
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'flagged', true)
        assert_msg_flag('flagged', true, false)
      }

      parse_search_key([ 'UNFLAGGED' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
      }
    end

    def test_parse_unkeyword
      make_search_parser{
        add_msg('')
        assert_msg_uid(1)
      }

      parse_search_key([ 'UNKEYWORD', 'foo' ]) {
        assert_search_cond(0, true) # always true
      }

      assert_search_syntax_error([ 'UNKEYWORD' ], /need for a search string/)
      assert_search_syntax_error([ 'UNKEYWORD', [ :group, 'foo' ] ], /search string expected as <String> but was/)
    end

    def test_parse_unseen
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2)

        set_msg_flag(1, 'seen', true)
        assert_msg_flag('seen', true, false)
      }

      parse_search_key([ 'UNSEEN' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
      }
    end

    def test_parse_msg_set
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        expunge(1, 3, 5)
        assert_msg_uid(2, 4, 6)
      }

      parse_search_key([ '1,*' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, true)
      }

      assert_search_syntax_error([ 'detarame' ], /unknown search key/)
    end

    def test_parse_group
      make_search_parser{
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        add_msg('foo')
        assert_msg_uid(1, 2, 3, 4)

        set_msg_flag(1, 'answered', true)
        set_msg_flag(2, 'answered', true)
        set_msg_flag(1, 'flagged', true)
        set_msg_flag(3, 'flagged', true)
        assert_msg_flag('answered', true, true,  false, false)
        assert_msg_flag('flagged',  true, false, true,  false)
      }

      parse_search_key([ 'ANSWERED', 'FLAGGED' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
        assert_search_cond(3, false)
      }

      parse_search_key([ [ :group, 'ANSWERED', 'FLAGGED' ] ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
        assert_search_cond(3, false)
      }

      assert_search_syntax_error([ [ :block, 'ANSWERED', 'FLAGGED' ] ], /unknown search key/)
    end

    def test_parse_unknown
      make_search_parser{}
      assert_search_syntax_error([ :detarame ], /unknown search key/)
    end

    def test_parse_charset_body
      make_search_parser(charset: 'utf-8') {
        add_msg("Content-Type: text/plain\r\n" +
                "\r\n" +
                "foo")
        add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
                "\r\n" +
                "foo")
        add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                "\r\n" +
                "foo")
        add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
                "\r\n" +
                "\u3053\u3093\u306B\u3061\u306F\r\n" +
                "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
                "\u3042\u3044\u3046\u3048\u304A\r\n")
        add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                "\r\n" +
                "\e$B$3$s$K$A$O\e(B\r\n\e$B$$$m$O$K$[$X$H\e(B\r\n\e$B$\"$$$&$($*\e(B\r\n")
        assert_msg_uid(1, 2, 3, 4, 5)
      }

      parse_search_key([ 'BODY', 'foo' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, true)
        assert_search_cond(2, true)
        assert_search_cond(3, false)
        assert_search_cond(4, false)
      }

      parse_search_key([ 'BODY', 'bar' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
        assert_search_cond(3, false)
        assert_search_cond(4, false)
      }

      parse_search_key([ 'BODY', "\u306F\u306B\u307B".b ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
        assert_search_cond(3, true)
        assert_search_cond(4, true)
      }
    end

    def test_parse_charset_text
      make_search_parser(charset: 'utf-8') {
        add_msg("Content-Type: text/plain\r\n" +
                "foo")
        add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
                "X-foo: dummy\r\n" +
                "\r\n" +
                "bar")
        add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                "X-dummy: foo\r\n" +
                "\r\n" +
                "bar")
        add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
                "\r\n" +
                "\u3053\u3093\u306B\u3061\u306F\r\n" +
                "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
                "\u3042\u3044\u3046\u3048\u304A\r\n")
        add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                "\r\n" +
                "\e$B$3$s$K$A$O\e(B\r\n\e$B$$$m$O$K$[$X$H\e(B\r\n\e$B$\"$$$&$($*\e(B\r\n")
        assert_msg_uid(1, 2, 3, 4, 5)
      }

      parse_search_key([ 'TEXT', 'foo' ]) {
        assert_search_cond(0, true)
        assert_search_cond(1, true)
        assert_search_cond(2, true)
        assert_search_cond(3, false)
        assert_search_cond(4, false)
      }

      parse_search_key([ 'TEXT', 'bar' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, true)
        assert_search_cond(2, true)
        assert_search_cond(3, false)
        assert_search_cond(4, false)
      }

      parse_search_key([ 'TEXT', 'baz' ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
        assert_search_cond(3, false)
        assert_search_cond(4, false)
      }

      parse_search_key([ 'TEXT', "\u306F\u306B\u307B".b ]) {
        assert_search_cond(0, false)
        assert_search_cond(1, false)
        assert_search_cond(2, false)
        assert_search_cond(3, true)
        assert_search_cond(4, true)
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
