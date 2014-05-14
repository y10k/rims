# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolSearchParserTest < Test::Unit::TestCase
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
      nil
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

    def make_search_parser
      yield
      @folder = @mail_store.select_mbox(@inbox_id)
      @parser = RIMS::Protocol::SearchParser.new(@mail_store, @folder)
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
      assert_equal(expected_found_flag, @cond.call(@folder.msg_list[msg_idx]))
    end
    private :assert_search_cond

    def assert_search_syntax_error(search_key_list)
      assert_raise(RIMS::SyntaxError) {
        @parser.parse(search_key_list)
      }
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

      assert_search_syntax_error([ 'BCC' ])
      assert_search_syntax_error([ 'BCC', [ :group, 'foo' ] ])
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

      assert_search_syntax_error([ 'BEFORE' ])
      assert_search_syntax_error([ 'BEFORE', '99-Nov-2013' ])
      assert_search_syntax_error([ 'BEFORE', [ :group, '08-Nov-2013'] ])
    end

    def test_parse_body
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\n\r\nbar")
        @mail_store.add_msg(@inbox_id, "Content-Type: message/rfc822\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, <<-'EOF')
Content-Type: multipart/alternative; boundary="1383.905529.351297"

--1383.905529.351297
Content-Type: text/plain

foo
--1383.905529.351297
Content-Type: text/html

<html><body><p>foo</p></body></html>
--1383.905529.351297--
        EOF
        assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'BODY', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))
      assert_equal(false, cond.call(@folder.msg_list[3])) # ignored text part of multipart message.
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'BODY' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'BODY', [ :group, 'foo' ] ])
      }
    end

    def test_parse_cc
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "Cc: foo\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Cc: bar\r\n\r\foo")
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'CC', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'CC' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'CC', [ :group, 'foo' ] ])
      }
    end

    def test_parse_deleted
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'deleted'))
      }
      cond = @parser.parse([ 'DELETED' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
    end

    def test_parse_draft
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'draft', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'draft'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'draft'))
      }
      cond = @parser.parse([ 'DRAFT' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
    end

    def test_parse_flagged
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'flagged', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'flagged'))
      }
      cond = @parser.parse([ 'FLAGGED' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
    end

    def test_parse_from
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "From: foo\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "From: bar\r\n\r\foo")
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'FROM', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'FROM' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'FROM', [ :group, 'foo' ] ])
      }
    end

    def test_parse_header
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "X-Foo: alice\r\nX-Bar: bob\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "X-Foo: bob\r\nX-Bar: alice\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'HEADER', 'x-foo', 'alice' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      cond = @parser.parse([ 'HEADER', 'x-foo', 'bob' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      cond = @parser.parse([ 'HEADER', 'x-bar', 'alice' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      cond = @parser.parse([ 'HEADER', 'x-bar', 'bob' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))

      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'HEADER' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'HEADER', 'Received' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'HEADER', 'Received', [ :group, 'foo' ] ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'HEADER', [ :group, 'Received' ], 'foo' ])
      }
    end

    def test_parse_keyword
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'KEYWORD', 'foo' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'KEYWORD' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'KEYWORD', [ :group, 'foo' ] ])
      }
    end

    def test_parse_larger
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, '1234')
        @mail_store.add_msg(@inbox_id, 'bar')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'LARGER', '3' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'LARGER' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'LARGER', [ :group, '3' ] ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'LARGER', 'nonum' ])
      }
    end

    def test_parse_new
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'bar')
        @mail_store.add_msg(@inbox_id, 'baz')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 3, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, 2, 'seen', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'recent'))
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'recent'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'recent'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'seen'))
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'seen'))
      }
      cond = @parser.parse([ 'NEW' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
    end

    def test_parse_not
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, '1234')
        @mail_store.add_msg(@inbox_id, 'bar')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'answered', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'answered'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'answered'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'answered'))
      }
      cond = @parser.parse([ 'NOT', 'LARGER', '3' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))
      cond = @parser.parse([ 'NOT', 'ANSWERED' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'NOT' ])
      }
    end

    def test_parse_old
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'bar')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'recent'))
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'recent'))
      }
      cond = @parser.parse([ 'OLD' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
    end

    def test_parse_on
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-07 12:34:56'))
        @mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-08 12:34:56'))
        @mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-09 12:34:56'))
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        assert_equal(Time.parse('2013-11-07 12:34:56'), @mail_store.msg_date(@inbox_id, 1))
        assert_equal(Time.parse('2013-11-08 12:34:56'), @mail_store.msg_date(@inbox_id, 2))
        assert_equal(Time.parse('2013-11-09 12:34:56'), @mail_store.msg_date(@inbox_id, 3))
      }
      cond = @parser.parse([ 'ON', '08-Nov-2013' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'ON' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'ON', '99-Nov-2013' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'ON', [ :group, '08-Nov-2013'] ])
      }
    end

    def test_parse_or
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'answered', true)
        @mail_store.set_msg_flag(@inbox_id, 2, 'answered', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'answered'))
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'answered'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'answered'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 4, 'answered'))
        @mail_store.set_msg_flag(@inbox_id, 1, 'flagged', true)
        @mail_store.set_msg_flag(@inbox_id, 3, 'flagged', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'flagged'))
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 4, 'flagged'))
      }
      cond = @parser.parse([ 'OR', 'ANSWERED', 'FLAGGED' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))
      assert_equal(false, cond.call(@folder.msg_list[3]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'OR' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'OR', 'ANSWERED' ])
      }
    end

    def test_parse_recent
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'recent', false)
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 1, 'recent'))
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'recent'))
      }
      cond = @parser.parse([ 'RECENT' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
    end

    def test_parse_seen
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'seen'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      }
      cond = @parser.parse([ 'SEEN' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
    end

    def test_parse_sentbefore
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "Date: Thu, 07 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Date: Fri, 08 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Date: Sat, 09 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'SENTBEFORE', '08-Nov-2013' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_equal(false, cond.call(@folder.msg_list[3]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTBEFORE' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTBEFORE', '99-Nov-2013' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTBEFORE', [ :group, '08-Nov-2013'] ])
      }
    end

    def test_parse_senton
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "Date: Thu, 07 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Date: Fri, 08 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Date: Sat, 09 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'SENTON', '08-Nov-2013' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_equal(false, cond.call(@folder.msg_list[3]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTON' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTON', '99-Nov-2013' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTON', [ :group, '08-Nov-2013'] ])
      }
    end

    def test_parse_sentsince
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "Date: Thu, 07 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Date: Fri, 08 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Date: Sat, 09 Nov 2013 12:34:56 +0900\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'SENTSINCE', '08-Nov-2013' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))
      assert_equal(false, cond.call(@folder.msg_list[3]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTSINCE' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTSINCE', '99-Nov-2013' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SENTSINCE', [ :group, '08-Nov-2013'] ])
      }
    end

    def test_parse_since
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-07 12:34:56'))
        @mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-08 12:34:56'))
        @mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-09 12:34:56'))
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        assert_equal(Time.parse('2013-11-07 12:34:56'), @mail_store.msg_date(@inbox_id, 1))
        assert_equal(Time.parse('2013-11-08 12:34:56'), @mail_store.msg_date(@inbox_id, 2))
        assert_equal(Time.parse('2013-11-09 12:34:56'), @mail_store.msg_date(@inbox_id, 3))
      }
      cond = @parser.parse([ 'SINCE', '08-Nov-2013' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SINCE' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SINCE', '99-Nov-2013' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SINCE', [ :group, '08-Nov-2013'] ])
      }
    end

    def test_parse_smaller
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, '12')
        @mail_store.add_msg(@inbox_id, 'bar')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'SMALLER', '3' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SMALLER' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SMALLER', [ :group, '3' ] ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SMALLER', 'nonum' ])
      }
    end

    def test_parse_subject
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "Subject: foo\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "Subject: bar\r\n\r\foo")
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'SUBJECT', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SUBJECT' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'SUBJECT', [ :group, 'foo' ] ])
      }
    end

    def test_parse_text
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "Content-Type: text/plain\r\nSubject: foo\r\n\r\nbar")
        assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'TEXT', 'jec' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      cond = @parser.parse([ 'TEXT', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      cond = @parser.parse([ 'TEXT', 'bar' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      cond = @parser.parse([ 'TEXT', 'baz' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'TEXT' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'TEXT', [ :group, 'foo'] ])
      }
    end

    def test_parse_to
      make_search_parser{
        @mail_store.add_msg(@inbox_id, "To: foo\r\n\r\nfoo")
        @mail_store.add_msg(@inbox_id, "To: bar\r\n\r\foo")
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'TO', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'TO' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'TO', [ :group, 'foo' ] ])
      }
    end

    def test_parse_uid
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
        @mail_store.set_msg_flag(@inbox_id, 3, 'deleted', true)
        @mail_store.set_msg_flag(@inbox_id, 5, 'deleted', true)
        @mail_store.expunge_mbox(@inbox_id)
        assert_equal([ 2, 4, 6 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'UID', '2,*' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))

      begin
        @parser.parse([ 'UID', 'detarame' ])
      rescue
        error = $!
      end
      assert_kind_of(RIMS::SyntaxError, error)
    end

    def test_parse_unanswered
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'answered', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'answered'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'answered'))
      }
      cond = @parser.parse([ 'UNANSWERED' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
    end

    def test_parse_undeleted
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'deleted'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'deleted'))
      }
      cond = @parser.parse([ 'UNDELETED' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
    end

    def test_parse_undraft
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'draft', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'draft'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'draft'))
      }
      cond = @parser.parse([ 'UNDRAFT' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
    end

    def test_parse_unflagged
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'flagged', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'flagged'))
      }
      cond = @parser.parse([ 'UNFLAGGED' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
    end

    def test_parse_unkeyword
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'UNKEYWORD', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'UNKEYWORD' ])
      }
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'UNKEYWORD', [ :group, 'foo' ] ])
      }
    end

    def test_parse_unseen
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'seen'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'seen'))
      }
      cond = @parser.parse([ 'UNSEEN' ])
      assert_equal(false, cond.call(@folder.msg_list[0]))
      assert_equal(true, cond.call(@folder.msg_list[1]))
    end

    def test_parse_msg_set
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
        @mail_store.set_msg_flag(@inbox_id, 3, 'deleted', true)
        @mail_store.set_msg_flag(@inbox_id, 5, 'deleted', true)
        @mail_store.expunge_mbox(@inbox_id)
        assert_equal([ 2, 4, 6 ], @mail_store.each_msg_uid(@inbox_id).to_a)
      }
      cond = @parser.parse([ '1,*' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ 'detarame' ])
      }
    end

    def test_parse_group
      make_search_parser{
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        @mail_store.add_msg(@inbox_id, 'foo')
        assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_uid(@inbox_id).to_a)
        @mail_store.set_msg_flag(@inbox_id, 1, 'answered', true)
        @mail_store.set_msg_flag(@inbox_id, 2, 'answered', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'answered'))
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 2, 'answered'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 3, 'answered'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 4, 'answered'))
        @mail_store.set_msg_flag(@inbox_id, 1, 'flagged', true)
        @mail_store.set_msg_flag(@inbox_id, 3, 'flagged', true)
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'flagged'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'flagged'))
        assert_equal(true, @mail_store.msg_flag(@inbox_id, 3, 'flagged'))
        assert_equal(false, @mail_store.msg_flag(@inbox_id, 4, 'flagged'))
      }
      cond = @parser.parse([ 'ANSWERED', 'FLAGGED' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_equal(false, cond.call(@folder.msg_list[3]))
      cond = @parser.parse([ [ :group, 'ANSWERED', 'FLAGGED' ] ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_equal(false, cond.call(@folder.msg_list[3]))
      assert_raise(RIMS::SyntaxError) {
        @parser.parse([ [ :block, 'ANSWERED', 'FLAGGED' ] ])
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
