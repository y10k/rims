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

    def test_parse_header
      assert_equal([], RIMS::RFC822.parse_header(''.b))

      field_pair_list = RIMS::RFC822.parse_header("Content-Type: text/plain; charset=utf-8\r\n".b +
                                                   "Subject: This is a test\r\n".b +
                                                   "\r\n".b)
      assert_equal(2, field_pair_list.length)
      assert_strenc_equal('ascii-8bit', 'Content-Type', field_pair_list[0][0])
      assert_strenc_equal('ascii-8bit', 'text/plain; charset=utf-8', field_pair_list[0][1])
      assert_strenc_equal('ascii-8bit', 'Subject', field_pair_list[1][0])
      assert_strenc_equal('ascii-8bit', 'This is a test', field_pair_list[1][1])

      field_pair_list = RIMS::RFC822.parse_header("Content-Type: text/plain; charset=utf-8\r\n".b +
                                                   "Subject: This is a test\r\n".b)
      assert_equal(2, field_pair_list.length)
      assert_strenc_equal('ascii-8bit', 'Content-Type', field_pair_list[0][0])
      assert_strenc_equal('ascii-8bit', 'text/plain; charset=utf-8', field_pair_list[0][1])
      assert_strenc_equal('ascii-8bit', 'Subject', field_pair_list[1][0])
      assert_strenc_equal('ascii-8bit', 'This is a test', field_pair_list[1][1])

      field_pair_list = RIMS::RFC822.parse_header("Content-Type: text/plain; charset=utf-8\r\n".b +
                                                   "Subject: This is a test".b)
      assert_equal(2, field_pair_list.length)
      assert_strenc_equal('ascii-8bit', 'Content-Type', field_pair_list[0][0])
      assert_strenc_equal('ascii-8bit', 'text/plain; charset=utf-8', field_pair_list[0][1])
      assert_strenc_equal('ascii-8bit', 'Subject', field_pair_list[1][0])
      assert_strenc_equal('ascii-8bit', 'This is a test', field_pair_list[1][1])

      field_pair_list = RIMS::RFC822.parse_header("Content-Type:\r\n".b +
                                                   " text/plain;\r\n".b +
                                                   " charset=utf-8\r\n".b +
                                                   "Subject: This\n".b +
                                                   " is a test\r\n".b +
                                                   "\r\n".b)
      assert_equal(2, field_pair_list.length)
      assert_strenc_equal('ascii-8bit', 'Content-Type', field_pair_list[0][0])
      assert_strenc_equal('ascii-8bit', "text/plain;\r\n charset=utf-8", field_pair_list[0][1])
      assert_strenc_equal('ascii-8bit', 'Subject', field_pair_list[1][0])
      assert_strenc_equal('ascii-8bit', "This\n is a test", field_pair_list[1][1])

      field_pair_list = RIMS::RFC822.parse_header('foo'.b)
      assert_equal(0, field_pair_list.length)
    end

    def test_parse_content_type
      content_type = RIMS::RFC822.parse_content_type('text/plain'.b)
      assert_equal([ 'text', 'plain', {} ], content_type)
      assert(content_type[0..1].all?{|s| s.encoding == Encoding::ASCII_8BIT })

      content_type = RIMS::RFC822.parse_content_type('text/plain; charset=utf-8'.b)
      assert_equal([ 'text', 'plain', { 'charset' => %w[ charset utf-8 ] } ], content_type)
      assert(content_type[0..1].all?{|s| s.encoding == Encoding::ASCII_8BIT })
      assert(content_type[2].each_pair.to_a.flatten.all?{|s| s.encoding == Encoding::ASCII_8BIT })

      content_type = RIMS::RFC822.parse_content_type('text/plain; CHARSET=UTF-8; Foo=apple; Bar="banana"'.b)
      assert_equal([ 'text', 'plain',
                     { 'charset' => %w[ CHARSET UTF-8 ],
                       'foo' => %w[ Foo apple ],
                       'bar' => %w[ Bar banana ]
                     }
                   ], content_type)
      assert(content_type[0..1].all?{|s| s.encoding == Encoding::ASCII_8BIT })
      assert(content_type[2].each_pair.to_a.flatten.all?{|s| s.encoding == Encoding::ASCII_8BIT })

      content_type = RIMS::RFC822.parse_content_type('text/plain;CHARSET=UTF-8;Foo=apple;Bar="banana"'.b)
      assert_equal([ 'text', 'plain',
                     { 'charset' => %w[ CHARSET UTF-8 ],
                       'foo' => %w[ Foo apple ],
                       'bar' => %w[ Bar banana ]
                     }
                   ], content_type)
      assert(content_type[0..1].all?{|s| s.encoding == Encoding::ASCII_8BIT })
      assert(content_type[2].each_pair.to_a.flatten.all?{|s| s.encoding == Encoding::ASCII_8BIT })

      content_type = RIMS::RFC822.parse_content_type('multipart/mixed; boundary=----=_Part_1459890_1462677911.1383882437398'.b)
      assert_equal([ 'multipart', 'mixed',
                     { 'boundary' => %w[ boundary ----=_Part_1459890_1462677911.1383882437398 ] }
                   ], content_type)
      assert(content_type[0..1].all?{|s| s.encoding == Encoding::ASCII_8BIT })
      assert(content_type[2].each_pair.to_a.flatten.all?{|s| s.encoding == Encoding::ASCII_8BIT })

      content_type = RIMS::RFC822.parse_content_type("multipart/alternative; \r\n	boundary=\"----=_Part_1459891_982342968.1383882437398\"".b)
      assert_equal([ 'multipart', 'alternative',
                     { 'boundary' => %w[ boundary ----=_Part_1459891_982342968.1383882437398 ] }
                   ], content_type)
      assert(content_type[0..1].all?{|s| s.encoding == Encoding::ASCII_8BIT })
      assert(content_type[2].each_pair.to_a.flatten.all?{|s| s.encoding == Encoding::ASCII_8BIT })

      assert_equal([ 'application', 'octet-stream', {} ], RIMS::RFC822.parse_content_type(''))
    end

    def test_parse_multipart_body
      body_txt = <<-'MULTIPART'.b
------=_Part_1459890_1462677911.1383882437398
Content-Type: multipart/alternative; 
	boundary="----=_Part_1459891_982342968.1383882437398"

------=_Part_1459891_982342968.1383882437398
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: base64

Cgo9PT09PT09PT09CkFNQVpPTi5DTy5KUAo9PT09PT09PT09CkFtYXpvbi5jby5qcOOBp+WVhuWT
rpvjgavpgIHkv6HjgZXjgozjgb7jgZfjgZ86IHRva2lAZnJlZWRvbS5uZS5qcAoKCg==
------=_Part_1459891_982342968.1383882437398
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: quoted-printable

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.=

------=_Part_1459891_982342968.1383882437398--

------=_Part_1459890_1462677911.1383882437398--
      MULTIPART

      part_list = RIMS::RFC822.parse_multipart_body('----=_Part_1459890_1462677911.1383882437398'.b, body_txt)
      assert_equal(1, part_list.length)
      assert_strenc_equal('ascii-8bit', <<-'PART', part_list[0])
Content-Type: multipart/alternative; 
	boundary="----=_Part_1459891_982342968.1383882437398"

------=_Part_1459891_982342968.1383882437398
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: base64

Cgo9PT09PT09PT09CkFNQVpPTi5DTy5KUAo9PT09PT09PT09CkFtYXpvbi5jby5qcOOBp+WVhuWT
rpvjgavpgIHkv6HjgZXjgozjgb7jgZfjgZ86IHRva2lAZnJlZWRvbS5uZS5qcAoKCg==
------=_Part_1459891_982342968.1383882437398
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: quoted-printable

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.=

------=_Part_1459891_982342968.1383882437398--
      PART

      header_txt, body_txt = RIMS::RFC822.split_message(part_list[0])
      content_type_txt = RIMS::RFC822.parse_header(header_txt).find{|n, v| n == 'Content-Type' }[1]
      boundary = RIMS::RFC822.parse_content_type(content_type_txt)[2]['boundary'][1]

      part_list = RIMS::RFC822.parse_multipart_body(boundary, body_txt)
      assert_equal(2, part_list.length)
      assert_strenc_equal('ascii-8bit', <<-'PART1'.chomp, part_list[0])
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: base64

Cgo9PT09PT09PT09CkFNQVpPTi5DTy5KUAo9PT09PT09PT09CkFtYXpvbi5jby5qcOOBp+WVhuWT
rpvjgavpgIHkv6HjgZXjgozjgb7jgZfjgZ86IHRva2lAZnJlZWRvbS5uZS5qcAoKCg==
      PART1
      assert_strenc_equal('ascii-8bit', <<-'PART2', part_list[1])
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: quoted-printable

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.=
      PART2
    end

    def test_parse_multipart_body_bad_format
      assert_equal(%w[ foo bar baz ], RIMS::RFC822.parse_multipart_body('sep', <<-EOF))
--sep
foo
--sep
bar
--sep
baz
      EOF

      assert_equal([], RIMS::RFC822.parse_multipart_body('sep', <<-EOF))
--sep--
      EOF

      assert_equal([], RIMS::RFC822.parse_multipart_body('sep', 'detarame'))
      assert_equal([], RIMS::RFC822.parse_multipart_body('sep', ''))
    end

    def test_unquote_phrase_raw
      assert_strenc_equal('ascii-8bit', '', RIMS::RFC822.unquote_phrase(''.b))
      assert_strenc_equal('ascii-8bit', 'Hello world.', RIMS::RFC822.unquote_phrase('Hello world.'.b))
      assert_strenc_equal('ascii-8bit', "\" ( ) \\", RIMS::RFC822.unquote_phrase("\\\" \\( \\) \\\\".b))
    end

    def test_unquote_phrase_quote
      assert_strenc_equal('ascii-8bit', '', RIMS::RFC822.unquote_phrase('""'.b))
      assert_strenc_equal('ascii-8bit', 'Hello world.', RIMS::RFC822.unquote_phrase('"Hello world."'.b))
      assert_strenc_equal('ascii-8bit', 'foo "bar" baz', RIMS::RFC822.unquote_phrase("\"foo \\\"bar\\\" baz\"".b))
      assert_strenc_equal('ascii-8bit', 'foo (bar) baz', RIMS::RFC822.unquote_phrase('"foo (bar) baz"'.b))
    end

    def test_unquote_phrase_comment
      assert_strenc_equal('ascii-8bit', '', RIMS::RFC822.unquote_phrase('()'.b))
      assert_strenc_equal('ascii-8bit', '', RIMS::RFC822.unquote_phrase('(Hello world.)'.b))
      assert_strenc_equal('ascii-8bit', '', RIMS::RFC822.unquote_phrase("( \" \\( \\) \\\\ )".b))
    end

    def test_unquote_phrase_abnormal_patterns
      assert_strenc_equal('ascii-8bit', '', RIMS::RFC822.unquote_phrase("\\".b))
      assert_strenc_equal('ascii-8bit', 'foo', RIMS::RFC822.unquote_phrase('"foo'.b))
      assert_strenc_equal('ascii-8bit', 'foo', RIMS::RFC822.unquote_phrase(%Q'"foo\\'.b))
      assert_strenc_equal('ascii-8bit', '', RIMS::RFC822.unquote_phrase('(foo'.b))
      assert_strenc_equal('ascii-8bit', '', RIMS::RFC822.unquote_phrase("(foo\\".b))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
