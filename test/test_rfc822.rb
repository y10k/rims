# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class RFC822ParserTest < Test::Unit::TestCase
    def assert_strenc_equal(expected_enc, expected_str, expr_str)
      assert_equal(Encoding.find(expected_enc), expr_str.encoding)
      assert_equal(expected_str.dup.force_encoding(expected_enc), expr_str)
    end
    private :assert_strenc_equal

    def test_split_message
      msg =
	"Content-Type: text/plain\r\n" +
	"Subject: test\r\n" +
	"\r\n" +
	"HALO\r\n"
      header_body_pair = RIMS::RFC822.split_message(msg.b)
      assert_strenc_equal('ascii-8bit',
                          "Content-Type: text/plain\r\n" +
                          "Subject: test\r\n" +
                          "\r\n",
                          header_body_pair[0])
      assert_strenc_equal('ascii-8bit',
                          "HALO\r\n",
                          header_body_pair[1])

      msg =
	"Content-Type: text/plain\n" +
	"Subject: test\n" +
	"\n" +
	"HALO\n"
      header_body_pair = RIMS::RFC822.split_message(msg.b)
      assert_strenc_equal('ascii-8bit',
                          "Content-Type: text/plain\n" +
                          "Subject: test\n" +
                          "\n",
                          header_body_pair[0])
      assert_strenc_equal('ascii-8bit',
                          "HALO\n",
                          header_body_pair[1])

      msg =
        "\n" +
        "\r\n" +
        " \t\n" +
	"Content-Type: text/plain\r\n" +
	"Subject: test\r\n" +
	"\r\n" +
	"HALO\r\n"
      header_body_pair = RIMS::RFC822.split_message(msg.b)
      assert_strenc_equal('ascii-8bit',
                          "Content-Type: text/plain\r\n" +
                          "Subject: test\r\n" +
                          "\r\n",
                          header_body_pair[0])
      assert_strenc_equal('ascii-8bit',
                          "HALO\r\n",
                          header_body_pair[1])

      msg =
	"Content-Type: text/plain\r\n" +
	"Subject: test\r\n" +
	"\r\n"
      header_body_pair = RIMS::RFC822.split_message(msg.b)
      assert_strenc_equal('ascii-8bit',
                          "Content-Type: text/plain\r\n" +
                          "Subject: test\r\n" +
                          "\r\n",
                          header_body_pair[0])
      assert_strenc_equal('ascii-8bit', '', header_body_pair[1])

      msg =
	"Content-Type: text/plain\r\n" +
	"Subject: test\r\n"
      header_body_pair = RIMS::RFC822.split_message(msg.b)
      assert_strenc_equal('ascii-8bit',
                          "Content-Type: text/plain\r\n" +
                          "Subject: test\r\n",
                          header_body_pair[0])
      assert_nil(header_body_pair[1])
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
