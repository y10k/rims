# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'
require 'time'

module RIMS::Test
  class TimeTest < Test::Unit::TestCase
    def test_parse_date_time
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), Time.parse('19-Nov-1975 12:34:56 +0900'))
      assert_raise(ArgumentError) { Time.parse('detarame') }
      assert_raise(TypeError) { Time.parse([]) }
      assert_raise(TypeError) { Time.parse(nil) }
    end
  end

  class ProtocolTest < Test::Unit::TestCase
    def assert_strenc_equal(expected_enc, expected_str, expr_str)
      assert_equal(Encoding.find(expected_enc), expr_str.encoding)
      assert_equal(expected_str.dup.force_encoding(expected_enc), expr_str)
    end
    private :assert_strenc_equal

    def test_quote
      assert_strenc_equal('utf-8', '""', RIMS::Protocol.quote(''))
      assert_strenc_equal('ascii-8bit', '""', RIMS::Protocol.quote(''.encode('ascii-8bit')))

      assert_strenc_equal('utf-8', '"foo"', RIMS::Protocol.quote('foo'))
      assert_strenc_equal('ascii-8bit', '"foo"', RIMS::Protocol.quote('foo'.encode('ascii-8bit')))

      assert_strenc_equal('utf-8', "{1}\r\n\"", RIMS::Protocol.quote('"'))
      assert_strenc_equal('ascii-8bit', "{1}\r\n\"", RIMS::Protocol.quote('"'.encode('ascii-8bit')))

      assert_strenc_equal('utf-8', "{8}\r\nfoo\nbar\n", RIMS::Protocol.quote("foo\nbar\n"))
      assert_strenc_equal('ascii-8bit', "{8}\r\nfoo\nbar\n", RIMS::Protocol.quote("foo\nbar\n".encode('ascii-8bit')))
    end

    def assert_regexp_enc(expected_encoding, regexp)
      assert_equal(Encoding.find(expected_encoding), regexp.encoding)
      regexp
    end
    private :assert_regexp_enc

    def test_compile_wildcard
      assert(RIMS::Protocol.compile_wildcard('xxx') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('xxx') !~ 'yyy')
      assert(RIMS::Protocol.compile_wildcard('x*') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('x*') !~ 'yxx')
      assert(RIMS::Protocol.compile_wildcard('*x') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('*x') !~ 'xxy')
      assert(RIMS::Protocol.compile_wildcard('*x*') =~ 'xyy')
      assert(RIMS::Protocol.compile_wildcard('*x*') =~ 'yxy')
      assert(RIMS::Protocol.compile_wildcard('*x*') =~ 'yyx')
      assert(RIMS::Protocol.compile_wildcard('*x*') !~ 'yyy')

      assert(RIMS::Protocol.compile_wildcard('xxx') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('xxx') !~ 'yyy')
      assert(RIMS::Protocol.compile_wildcard('x%') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('x%') !~ 'yxx')
      assert(RIMS::Protocol.compile_wildcard('%x') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('%x') !~ 'xxy')
      assert(RIMS::Protocol.compile_wildcard('%x%') =~ 'xyy')
      assert(RIMS::Protocol.compile_wildcard('%x%') =~ 'yxy')
      assert(RIMS::Protocol.compile_wildcard('%x%') =~ 'yyx')
      assert(RIMS::Protocol.compile_wildcard('%x%') !~ 'yyy')
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
