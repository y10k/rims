# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
