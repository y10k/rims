# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolSearchParserTest < Test::Unit::TestCase
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

    def make_search_parser
      yield
      @folder = @mail_store.select_mbox(@inbox_id)
      @parser = RIMS::Protocol::SearchParser.new(@mail_store, @folder)
    end
    private :make_search_parser

    def test_parse_all
      make_search_parser{
	@mail_store.add_msg(@inbox_id, 'foo')
	assert_equal([ 1 ], @mail_store.each_msg_id(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'ALL' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
    end

    def test_parse_answered
      make_search_parser{
	@mail_store.add_msg(@inbox_id, 'foo')
	@mail_store.add_msg(@inbox_id, 'foo')
	assert_equal([ 1, 2 ], @mail_store.each_msg_id(@inbox_id).to_a)
	@mail_store.set_msg_flag(@inbox_id, 1, 'answered', true)
	assert_equal(true, @mail_store.msg_flag(@inbox_id, 1, 'answered'))
	assert_equal(false, @mail_store.msg_flag(@inbox_id, 2, 'answered'))
      }
      cond = @parser.parse([ 'ANSWERED' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
    end

    def test_parse_bcc
      make_search_parser{
	@mail_store.add_msg(@inbox_id, "Bcc: foo\r\n\r\nfoo")
	@mail_store.add_msg(@inbox_id, "Bcc: bar\r\n\r\foo")
        @mail_store.add_msg(@inbox_id, 'foo')
	assert_equal([ 1, 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'BCC', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'BCC' ])
      }
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'BCC', [ :group, 'foo' ] ])
      }
    end

    def test_parse_before
      make_search_parser{
	@mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-07 12:34:56'))
	@mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-08 12:34:56'))
	@mail_store.add_msg(@inbox_id, 'foo', Time.parse('2013-11-09 12:34:56'))
	assert_equal([ 1, 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
	assert_equal(Time.parse('2013-11-07 12:34:56'), @mail_store.msg_date(@inbox_id, 1))
	assert_equal(Time.parse('2013-11-08 12:34:56'), @mail_store.msg_date(@inbox_id, 2))
	assert_equal(Time.parse('2013-11-09 12:34:56'), @mail_store.msg_date(@inbox_id, 3))
      }
      cond = @parser.parse([ 'BEFORE', '08-Nov-2013' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'BEFORE' ])
      }
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'BEFORE', '99-Nov-2013' ])
      }
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'BEFORE', [ :group, '08-Nov-2013'] ])
      }
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
        assert_equal([ 1, 2, 3, 4 ], @mail_store.each_msg_id(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'BODY', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(true, cond.call(@folder.msg_list[2]))
      assert_equal(false, cond.call(@folder.msg_list[3])) # ignored text part of multipart message.
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'BODY' ])
      }
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'BODY', [ :group, 'foo' ] ])
      }
    end

    def test_parse_cc
      make_search_parser{
	@mail_store.add_msg(@inbox_id, "Cc: foo\r\n\r\nfoo")
	@mail_store.add_msg(@inbox_id, "Cc: bar\r\n\r\foo")
        @mail_store.add_msg(@inbox_id, 'foo')
	assert_equal([ 1, 2, 3 ], @mail_store.each_msg_id(@inbox_id).to_a)
      }
      cond = @parser.parse([ 'CC', 'foo' ])
      assert_equal(true, cond.call(@folder.msg_list[0]))
      assert_equal(false, cond.call(@folder.msg_list[1]))
      assert_equal(false, cond.call(@folder.msg_list[2]))
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'CC' ])
      }
      assert_raise(RIMS::ProtocolDecoder::SyntaxError) {
	@parser.parse([ 'CC', [ :group, 'foo' ] ])
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
