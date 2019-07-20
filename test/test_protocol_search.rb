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

    def make_search_parser(charset: nil)
      yield if block_given?
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

    def assert_search_cond(msg_idx, expected_found_flag, *optional)
      assert_equal(expected_found_flag, @cond.call(@folder[msg_idx]), *optional)
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

    # test data format:
    #   { search: <search key array>,
    #     charset: <charset (optional)>,
    #     messages: [
    #       [ <expected search condition>,
    #         <message text>,
    #         <message flags>,
    #         (<optional arguments for `RIMS::MailStore#add_msg'>)
    #       ],
    #       ...
    #     ]
    #   }
    data('ALL', {
           search: %w[ ALL ],
           messages: [
             [ true, 'foo', {} ]
           ]
         })
    [ [ 'ANSWERED',   %w[ ANSWERED ],   [ true,  false ] ],
      [ 'UNANSWERED', %w[ UNANSWERED ], [ false, true  ] ]
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ ' foo', { answered: true  } ],
               [  'foo', { answered: false } ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'us-ascii', %w[ BCC foo ],                [ true,  false, false, false, false, false, false ] ],
      [ 'charset',  %W[ BCC \u306F\u306B\u307B ], [ false, false, false, true,  false, true,  false ], 'utf-8' ]
    ].each do |label, search, cond_list, charset|
      data("BCC:#{label}", {
             search: search,
             charset: charset,
             messages: [
               [ "Bcc: foo\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Bcc: bar\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ 'foo',
                 {}
               ],
               [ "Bcc: =?UTF-8?B?44GE44KN44Gv44Gr44G744G444Go?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "Bcc: =?UTF-8?B?44Gh44KK44Gs44KL44KS?=\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Bcc: =?ISO-2022-JP?B?GyRCJCQkbSRPJEskWyRYJEgbKEI=?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "Bcc: =?ISO-2022-JP?B?GyRCJEEkaiRMJGskchsoQg==?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'BEFORE', %w[ BEFORE 08-Nov-2013 ], [ true,  false, false ] ],
      [ 'ON',     %w[ ON     08-Nov-2013 ], [ false, true,  false ] ],
      [ 'SINCE',  %w[ SINCE  08-Nov-2013 ], [ false, false, true  ] ]
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ 'foo', {}, Time.parse('2013-11-07 12:34:56 +0000') ],
               [ 'foo', {}, Time.parse('2013-11-08 12:34:56 +0000') ],
               [ 'foo', {}, Time.parse('2013-11-09 12:34:56 +0000') ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    data('BODY', {
           search: %w[ BODY foo ],
           messages: [
             [ true,
               "Content-Type: text/plain\r\n" +
               "\r\n" +
               "foo",
               {}
             ],
             [ false,
               "Content-Type: text/plain\r\n" +
               "\r\n" +
               "bar",
               {}
             ],
             [ true,
               "Content-Type: message/rfc822\r\n" +
               "\r\n" +
               "foo",
               {}
             ],
             [ true,
               <<-'EOF',
Content-Type: multipart/alternative; boundary="1383.905529.351297"

--1383.905529.351297
Content-Type: text/plain

foo
--1383.905529.351297
Content-Type: text/html

<html><body><p>foo</p></body></html>
--1383.905529.351297--
               EOF
               {}
             ]
           ]
         })
    [ [ 'us-ascii', %w[ CC foo ],                [ true,  false, false, false, false, false, false ] ],
      [ 'charset',  %W[ CC \u306F\u306B\u307B ], [ false, false, false, true,  false, true,  false ], 'utf-8' ]
    ].each do |label, search, cond_list, charset|
      data("CC:#{label}", {
             search: search,
             charset: charset,
             messages: [
               [ "Cc: foo\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Cc: bar\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ 'foo',
                 {}
               ],
               [ "Cc: =?UTF-8?B?44GE44KN44Gv44Gr44G744G444Go?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "Cc: =?UTF-8?B?44Gh44KK44Gs44KL44KS?=\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Cc: =?ISO-2022-JP?B?GyRCJCQkbSRPJEskWyRYJEgbKEI=?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "Cc: =?ISO-2022-JP?B?GyRCJEEkaiRMJGskchsoQg==?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'DELETED',   %w[ DELETED ],   [ true,  false ] ],
      [ 'UNDELETED', %w[ UNDELETED ], [ false, true  ] ]
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ 'foo', { deleted: true  } ],
               [ 'foo', { deleted: false } ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'DRAFT',   %w[ DRAFT ],   [ true,  false ] ],
      [ 'UNDRAFT', %w[ UNDRAFT ], [ false, true  ] ]
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ 'foo', { draft: true  } ],
               [ 'foo', { draft: false } ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'FLAGGED',   %w[ FLAGGED ],   [ true,  false ] ],
      [ 'UNFLAGGED', %w[ UNFLAGGED ], [ false, true  ] ]
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ 'foo', { flagged: true  } ],
               [ 'foo', { flagged: false } ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'us-ascii', %w[ FROM foo ],               [ true,  false, false, false, false, false, false ] ],
      [ 'charset',  %W[ FROM \u306F\u306B\u307B ],[ false, false, false, true,  false, true,  false ], 'utf-8' ]
    ].each do |label, search, cond_list, charset|
      data("FROM:#{label}", {
             search: search,
             charset: charset,
             messages: [
               [ "From: foo\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "From: bar\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ 'foo',
                 {}
               ],
               [ "From: =?UTF-8?B?44GE44KN44Gv44Gr44G744G444Go?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "From: =?UTF-8?B?44Gh44KK44Gs44KL44KS?=\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "From: =?ISO-2022-JP?B?GyRCJCQkbSRPJEskWyRYJEgbKEI=?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "From: =?ISO-2022-JP?B?GyRCJEEkaiRMJGskchsoQg==?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'x-foo_alice', %w[ HEADER x-foo alice ], [ true,  false, false ] ],
      [ 'x-foo_bob',   %w[ HEADER x-foo bob   ], [ false, true,  false ] ],
      [ 'x-foo_foo',   %w[ HEADER x-foo foo   ], [ false, false, false ] ],
      [ 'x-bar_alice', %w[ HEADER x-bar alice ], [ false, true,  false ] ],
      [ 'x-bar_bob',   %w[ HEADER x-bar bob   ], [ true,  false, false ] ],
      [ 'x-bar_foo',   %w[ HEADER x-bar foo   ], [ false, false, false ] ]
    ].each do |label, search, cond_list|
      data("HEADER:#{label}", {
             search: search,
             messages: [
               [ "X-Foo: alice\r\n" +
                 "X-Bar: bob\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "X-Foo: bob\r\n" +
                 "X-Bar: alice\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ 'foo',
                 {}
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    data('HEADER:charset', {
           search: %W[ HEADER x-foo \u306F\u306B\u307B ],
           charset: 'utf-8',
           messages: [
             [ true,
               "X-Foo: =?UTF-8?B?44GE44KN44Gv44Gr44G744G444Go?=\r\n" +
               "\r\n" +
               "foo",
               {}
             ],
             [ false,
               "X-Foo: =?UTF-8?B?44Gh44KK44Gs44KL44KS?=\r\n" +
               "\r\n" +
               "foo",
               {}
             ],
             [ true,
               "X-Foo: =?ISO-2022-JP?B?GyRCJCQkbSRPJEskWyRYJEgbKEI=?=\r\n" +
               "\r\n" +
               "foo",
               {},
             ],
             [ false,
               "X-Foo: =?ISO-2022-JP?B?GyRCJEEkaiRMJGskchsoQg==?=\r\n" +
               "\r\n" +
               "foo",
               {},
             ]
           ]
         })
    [ [ 'KEYWORD',   %w[ KEYWORD   foo ], [ false ] ], # always false
      [ 'UNKEYWORD', %w[ UNKEYWORD foo ], [ true  ] ]  # always true
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ '', {} ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'LARGER',  %w[ LARGER  3 ], [ false, false, true,  false ] ],
      [ 'SMALLER', %w[ SMALLER 3 ], [ false, true,  false, false ] ]
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ 'foo',  {} ],
               [ '12',   {} ],
               [ '1234', {} ],
               [ 'bar',  {} ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'NEW', %w[ NEW ], [ true, false, false ] ],
      [ 'OLD', %w[ OLD ], [ false, false, true ] ]
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ 'foo', { recent: true,  seen: false } ],
               [ 'bar', { recent: true,  seen: true  } ],
               [ 'baz', { recent: false, seen: false } ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'LARGER',   %w[ NOT LARGER 3 ], [ true,  false, true ] ],
      [ 'ANSWERED', %w[ NOT ANSWERED ], [ false, true,  true ] ]
    ].each do |label, search, cond_list|
      data("NOT:#{label}", {
             search: search,
             messages: [
               [ 'foo',  { answered: true  } ],
               [ '1234', { answered: false } ],
               [ 'bar',  { answered: false } ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    data('OR', {
           search: %w[ OR ANSWERED FLAGGED ],
           messages: [
             [ true,  'foo', { answered: true,  flagged: true  } ],
             [ true,  'foo', { answered: true,  flagged: false } ],
             [ true,  'foo', { answered: false, flagged: true  } ],
             [ false, 'foo', { answered: false, flagged: false } ]
           ]
         })
    data('RECENT', {
           search: %w[ RECENT ],
           messages: [
             [ false, 'foo', { recent: false } ],
             [ true,  'foo', { recent: true  } ]
           ]
         })
    [ [ 'SEEN',   %w[ SEEN ],   [ true,  false ] ],
      [ 'UNSEEN', %w[ UNSEEN ], [ false, true  ] ]
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ 'foo', { seen: true  } ],
               [ 'foo', { seen: false } ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'SENTBEFORE', %w[ SENTBEFORE 08-Nov-2013 ], [ true,  false, false, false ] ],
      [ 'SENTON',     %w[ SENTON     08-Nov-2013 ], [ false, true,  false, false ] ],
      [ 'SENTSINCE',  %w[ SENTSINCE  08-Nov-2013 ], [ false, false, true,  false ] ],
    ].each do |label, search, cond_list|
      data(label, {
             search: search,
             messages: [
               [ "Date: Thu, 07 Nov 2013 12:34:56 +0000\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Date: Fri, 08 Nov 2013 12:34:56 +0000\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Date: Sat, 09 Nov 2013 12:34:56 +0000\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ 'foo',
                 {}
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'us-ascii', %w[ SUBJECT foo ],                [ true,  false, false, false, false, false, false ] ],
      [ 'charset',  %W[ SUBJECT \u306F\u306B\u307B ], [ false, false, false, true,  false, true,  false ], 'utf-8' ]
    ].each do |label, search, cond_list, charset|
      data("SUBJECT:#{label}", {
             search: search,
             charset: charset,
             messages: [
               [ "Subject: foo\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Subject: bar\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ 'foo',
                 {}
               ],
               [ "Subject: =?UTF-8?B?44GE44KN44Gv44Gr44G744G444Go?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "Subject: =?UTF-8?B?44Gh44KK44Gs44KL44KS?=\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Subject: =?ISO-2022-JP?B?GyRCJCQkbSRPJEskWyRYJEgbKEI=?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "Subject: =?ISO-2022-JP?B?GyRCJEEkaiRMJGskchsoQg==?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'header_field_name',  %w[ TEXT jec ], [ true  ] ],
      [ 'header_field_value', %w[ TEXT foo ], [ true  ] ],
      [ 'body',               %w[ TEXT bar ], [ true  ] ],
      [ 'no_match',           %w[ TEXT baz ], [ false ] ]
    ].each do |label, search, cond_list|
      data("TEXT:#{label}", {
             search: search,
             messages: [
               [ "Content-Type: text/plain\r\n" +
                 "Subject: foo\r\n" +
                 "\r\n" +
                 "bar",
                 {}
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'header',          [ 'TEXT', 'Subject: multipart test' ],  [ true  ] ],
      [ 'inner_header',    [ 'TEXT', 'Subject: inner multipart' ], [ true  ] ],
      [ 'part_body',       [ 'TEXT', 'Hello world.' ],             [ true  ] ],
      [ 'inner_part_body', [ 'TEXT', 'HALO' ],                     [ true  ] ],
      [ 'no_match',        [ 'TEXT', 'detarame' ],                 [ false ] ]
    ].each do |label, search, cond_list|
      data("TEXT:multipart:#{label}", {
             search: search,
             messages: [
               [ MPART_MAIL_TEXT, {} ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'us-ascii', %w[ TO foo ],                [ true,  false, false, false, false, false, false ] ],
      [ 'charset',  %W[ TO \u306F\u306B\u307B ], [ false, false, false, true,  false, true,  false ], 'utf-8' ]
    ].each do |label, search, cond_list, charset|
      data("TO:#{label}", {
             search: search,
             charset: charset,
             messages: [
               [ "To: foo\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "To: bar\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ 'foo',
                 {}
               ],
               [ "To: =?UTF-8?B?44GE44KN44Gv44Gr44G744G444Go?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "To: =?UTF-8?B?44Gh44KK44Gs44KL44KS?=\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "To: =?ISO-2022-JP?B?GyRCJCQkbSRPJEskWyRYJEgbKEI=?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ],
               [ "To: =?ISO-2022-JP?B?GyRCJEEkaiRMJGskchsoQg==?=\r\n" +
                 "\r\n" +
                 "foo",
                 {},
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'us-ascii',          %w[ BODY foo ],                [ true,  true,  true,  false, false ] ],
      [ 'us-ascii:no_match', %w[ BODY bar ],                [ false, false, false, false, false ] ],
      [ 'utf-8',             %W[ BODY \u306F\u306B\u307B ], [ false, false, false, true,  true  ] ]
    ].each do |label, search, cond_list|
      data("BODY:charset:#{label}", {
             search: search,
             charset: 'utf-8',
             messages: [
               [ "Content-Type: text/plain\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Content-Type: text/plain; charset=utf-8\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Content-Type: text/plain; charset=utf-8\r\n" +
                 "\r\n" +
                 "\u3053\u3093\u306B\u3061\u306F\r\n" +
                 "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
                 "\u3042\u3044\u3046\u3048\u304A\r\n",
                 {}
               ],
               [ "Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                 "\r\n" +
                 "\e$B$3$s$K$A$O\e(B\r\n\e$B$$$m$O$K$[$X$H\e(B\r\n\e$B$\"$$$&$($*\e(B\r\n",
                 {}
               ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    [ [ 'us-ascii:header_and_body', %w[ TEXT foo ],                [ true,  true,  true,  false, false ] ],
      [ 'us-ascii:body',            %w[ TEXT bar ],                [ false, true,  true,  false, false ] ],
      [ 'us-ascii:no_match',        %w[ TEXT baz ],                [ false, false, false, false, false ] ],
      [ 'utf-8:body',               %W[ TEXT \u306F\u306B\u307B ], [ false, false, false, true,  true  ] ]
    ].each do |label, search, cond_list|
      data("TEXT:charset:#{label}", {
             search: search,
             charset: 'utf-8',
             messages: [
               [ "Content-Type: text/plain\r\n" +
                 "\r\n" +
                 "foo",
                 {}
               ],
               [ "Content-Type: text/plain; charset=utf-8\r\n" +
                 "X-foo: dummy\r\n" +
                 "\r\n" +
                 "bar",
                 {}
               ],
               [ "Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                 "X-dummy: foo\r\n" +
                 "\r\n" +
                 "bar",
                 {}
               ],
               [ "Content-Type: text/plain; charset=utf-8\r\n" +
                 "\r\n" +
                 "\u3053\u3093\u306B\u3061\u306F\r\n" +
                 "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
                 "\u3042\u3044\u3046\u3048\u304A\r\n",
                 {}
               ],
               [ "Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                 "\r\n" +
                 "\e$B$3$s$K$A$O\e(B\r\n\e$B$$$m$O$K$[$X$H\e(B\r\n\e$B$\"$$$&$($*\e(B\r\n",
                 {}
               ]
             ].zip(cond_list).map{|msg, cond| [ cond] + msg }
           })
    end
    data('msg_set', {
           search: %w[ 1,2,* ],
           messages: [
             [ true,  'foo', {} ],
             [ true,  'foo', {} ],
             [ false, 'foo', {} ],
             [ false, 'foo', {} ],
             [ true,  'foo', {} ]
           ]
         })
    [ [ 'list',  %w[ ANSWERED FLAGGED ],                [ true, false, false, false ] ],
      [ 'group', [ [ :group, 'ANSWERED', 'FLAGGED' ] ], [ true, false, false, false ] ]
    ].each do |label, search, cond_list|
      data("group:#{label}", {
             search: search,
             messages: [
               [ 'foo', { answered: true,  flagged: true  } ],
               [ 'foo', { answered: true,  flagged: false } ],
               [ 'foo', { answered: false, flagged: true  } ],
               [ 'foo', { answered: false, flagged: false } ]
             ].zip(cond_list).map{|msg, cond| [ cond ] + msg }
           })
    end
    def test_parse_and_search(data)
      search   = data[:search]
      charset  = data[:charset]
      msg_list = data[:messages]

      make_search_parser(charset: charset) {
        for _, msg, flags, *optional in msg_list
          uid = add_msg(msg, *optional)
          for name, value in flags
            set_msg_flag(uid, name.to_s, value)
          end
        end
      }

      search = search.map{|key| (key.is_a? String) ? key.b : key }
      parse_search_key(search) {
        msg_list.each_with_index do |(expected_cond, *_), i|
          assert_search_cond(i, expected_cond, "message index: #{i}")
        end
      }
    end

    %w[ BCC BODY CC FROM KEYWORD SUBJECT TEXT TO UNKEYWORD ].each do |key|
      data("#{key}:no_string", [
             [ key ],
             /need for a search string/
           ])
      data("#{key}:not_string", [
             [ key, [ :group, 'foo' ] ],
             /search string expected as <String> but was/
           ])
    end
    %w[ BEFORE ON SENTBEFORE SENTON SENTSINCE SINCE ].each do |key|
      data("#{key}:no_date", [
             [ key ],
             /need for a search date/
           ])
      data("#{key}:invalid_date", [
             [ key, '99-Nov-2013' ],
             /search date is invalid/
           ])
      data("#{key}:not_date", [
             [ key, [ :group, '08-Nov-2013'] ],
             /search date string expected as <String> but was/
           ])
    end
    %w[ LARGER SMALLER ].each do |key|
      data("#{key}:no_size", [
             %w[ LARGER ],
             /need for a octet size/
           ])
      data("#{key}:invalid_size", [
             %w[ LARGER nonum ],
             /octet size is expected as numeric string but was/
           ])
      data("#{key}:not_size", [
             [ 'LARGER', [ :group, '3' ] ],
             /octet size is expected as numeric string but was/
           ])
    end
    data('HEADER:no_field_name', [
           %w[ HEADER ],
           /need for a search string/
         ])
    data('HEADER:no_string', [
           %w[ HEADER Received ],
           /need for a search string/
         ])
    data('HEADER:not_field_name', [
           [ 'HEADER', [ :group, 'Received' ], 'foo' ],
           /search string expected as <String> but was/
         ])
    data('HEADER:not_string', [
           [ 'HEADER', 'Received', [ :group, 'foo' ] ],
           /search string expected as <String> but was/
         ])
    data('NOT:no_search_key', [
           %w[ NOT ],
           'unexpected end of search key.'
         ])
    data('OR:no_left_search_key', [
           %w[ OR ],
           'unexpected end of search key.'
         ])
    data('OR:no_right_search_key', [
           %w[ OR ANSWERED ],
           'unexpected end of search key.'
         ])
    [ [ 'string', %w[ detarame ] ],
      [ 'symbol', [ :detarame ] ],
      [ 'array',  [ [ :detarame, 'ANSWERED', 'FLAGGED' ] ] ],
    ].each do |label, search_key|
      data("unknown_search_key:#{label}", [
             search_key,
             /unknown search key/
           ])
    end
    def test_search_syntax_error(data)
      search, expected_pattern = data
      make_search_parser
      assert_search_syntax_error(search, expected_pattern)
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

      error = assert_raise(RIMS::MessageSetSyntaxError) { @parser.parse([ 'UID', 'detarame' ]) }
      assert_kind_of(RIMS::SyntaxError, error)
      assert_match(/invalid message sequence format/, error.message)
      assert_match(/detarame/, error.message)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
