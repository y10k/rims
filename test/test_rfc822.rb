# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class RFC822ParserTest < Test::Unit::TestCase
    include AssertUtility

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

      field_pair_list = RIMS::RFC822.parse_header('foo:bar:baz'.b)
      assert_equal(1, field_pair_list.length)
      assert_strenc_equal('ascii-8bit', 'foo', field_pair_list[0][0])
      assert_strenc_equal('ascii-8bit', 'bar:baz', field_pair_list[0][1])
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

    def test_parse_mail_address_list_addr_spec
      assert_equal([], RIMS::RFC822.parse_mail_address_list(''.b))
      assert_equal([ [ nil, nil, 'toki', 'freedom.ne.jp' ] ],
                   RIMS::RFC822.parse_mail_address_list('toki@freedom.ne.jp'.b))
      assert_equal([ [ nil, nil, 'toki', 'freedom.ne.jp' ] ],
                   RIMS::RFC822.parse_mail_address_list(' toki@freedom.ne.jp '.b))
    end

    def test_parse_mail_address_list_name_addr
      assert_equal([ [ 'TOKI Yoshinori', nil, 'toki', 'freedom.ne.jp' ] ],
                   RIMS::RFC822.parse_mail_address_list('TOKI Yoshinori <toki@freedom.ne.jp>'.b))
      assert_equal([ [ 'TOKI Yoshinori', nil, 'toki', 'freedom.ne.jp' ] ],
                   RIMS::RFC822.parse_mail_address_list('"TOKI Yoshinori" <toki@freedom.ne.jp>'.b))
      assert_equal([ [ 'TOKI Yoshinori', nil, 'toki', 'freedom.ne.jp' ] ],
                   RIMS::RFC822.parse_mail_address_list('TOKI(土岐) Yoshinori <toki@freedom.ne.jp>'.b))
      assert_equal([ [ 'TOKI,Yoshinori', nil, 'toki', 'freedom.ne.jp' ] ],
                   RIMS::RFC822.parse_mail_address_list('TOKI\,Yoshinori <toki@freedom.ne.jp>'.b))
      assert_equal([ [ 'toki@freedom.ne.jp', nil, 'toki', 'freedom.ne.jp' ] ],
                   RIMS::RFC822.parse_mail_address_list('"toki@freedom.ne.jp" <toki@freedom.ne.jp>'.b))
    end

    def test_parse_mail_address_list_route_addr
      assert_equal([ [ 'TOKI Yoshinori', '@mail.freedom.ne.jp,@smtp.gmail.com', 'toki', 'freedom.ne.jp' ] ],
                   RIMS::RFC822.parse_mail_address_list('TOKI Yoshinori <@mail.freedom.ne.jp,@smtp.gmail.com:toki@freedom.ne.jp>'.b))
    end

    def test_parse_mail_address_list_group
      assert_equal([ [ nil, nil, 'toki', nil ],
                     [ nil, nil, 'toki', 'freedom.ne.jp' ],
                     [ 'TOKI Yoshinori', nil, 'toki', 'freedom.ne.jp' ],
                     [ 'TOKI Yoshinori', '@mail.freedom.ne.jp,@smtp.gmail.com', 'toki', 'freedom.ne.jp' ],
                     [ nil, nil, nil, nil ]
                   ],
                   RIMS::RFC822.parse_mail_address_list('toki: ' +
                                                        'toki@freedom.ne.jp, ' +
                                                        'TOKI Yoshinori <toki@freedom.ne.jp>, ' +
                                                        'TOKI Yoshinori <@mail.freedom.ne.jp,@smtp.gmail.com:toki@freedom.ne.jp>' +
                                                        ';'.b))
    end

    def test_parse_mail_address_list_multiline
      assert_equal([ [ nil, nil, 'toki', 'freedom.ne.jp' ],
                     [ 'TOKI Yoshinori', nil, 'toki', 'freedom.ne.jp' ],
                     [ 'Yoshinori Toki', nil, 'toki', 'freedom.ne.jp' ]
                   ],
                   RIMS::RFC822.parse_mail_address_list("toki@freedom.ne.jp,\n" +
                                                        "  TOKI Yoshinori <toki@freedom.ne.jp>\n" +
                                                        "  , Yoshinori Toki <toki@freedom.ne.jp>  "))
    end
  end

  class RFC822HeaderText < Test::Unit::TestCase
    def setup
      @header = RIMS::RFC822::Header.new("foo: apple\r\n" +
                                         "bar: Bob\r\n" +
                                         "Foo: banana\r\n" +
                                         "FOO: orange\r\n" +
                                         "\r\n")
      pp @header if $DEBUG
    end

    def teardown
      pp @header if $DEBUG
    end

    def test_each
      assert_equal([ %w[ foo apple ], %w[ bar Bob ], %w[ Foo banana ], %w[ FOO orange ] ],
                   @header.each.to_a)
    end

    def test_key?
      assert_equal(true, (@header.key? 'foo'))
      assert_equal(true, (@header.key? 'Foo'))
      assert_equal(true, (@header.key? 'FOO'))

      assert_equal(true, (@header.key? 'bar'))
      assert_equal(true, (@header.key? 'Bar'))
      assert_equal(true, (@header.key? 'BAR'))

      assert_equal(false, (@header.key? 'baz'))
      assert_equal(false, (@header.key? 'Baz'))
      assert_equal(false, (@header.key? 'BAZ'))
    end

    def test_fetch
      assert_equal('apple', @header['foo'])
      assert_equal('apple', @header['Foo'])
      assert_equal('apple', @header['FOO'])

      assert_equal('Bob', @header['bar'])
      assert_equal('Bob', @header['Bar'])
      assert_equal('Bob', @header['BAR'])

      assert_nil(@header['baz'])
      assert_nil(@header['Baz'])
      assert_nil(@header['BAZ'])
    end

    def test_fetch_upcase
      assert_equal('APPLE', @header.fetch_upcase('foo'))
      assert_equal('APPLE', @header.fetch_upcase('Foo'))
      assert_equal('APPLE', @header.fetch_upcase('FOO'))

      assert_equal('BOB', @header.fetch_upcase('bar'))
      assert_equal('BOB', @header.fetch_upcase('Bar'))
      assert_equal('BOB', @header.fetch_upcase('BAR'))

      assert_nil(@header.fetch_upcase('baz'))
      assert_nil(@header.fetch_upcase('Baz'))
      assert_nil(@header.fetch_upcase('BAZ'))
    end

    def test_field_value_list
      assert_equal(%w[ apple banana orange ], @header.field_value_list('foo'))
      assert_equal(%w[ apple banana orange ], @header.field_value_list('Foo'))
      assert_equal(%w[ apple banana orange ], @header.field_value_list('FOO'))

      assert_equal(%w[ Bob ], @header.field_value_list('bar'))
      assert_equal(%w[ Bob ], @header.field_value_list('Bar'))
      assert_equal(%w[ Bob ], @header.field_value_list('BAR'))

      assert_nil(@header.field_value_list('baz'))
      assert_nil(@header.field_value_list('Baz'))
      assert_nil(@header.field_value_list('BAZ'))
    end
  end

  class RFC822MessageTest < Test::Unit::TestCase
    def setup_message(headers={},
                      content_type: 'text/plain; charset=utf-8',
                      body: "Hello world.\r\n")
      @msg = RIMS::RFC822::Message.new(headers.map{|n, v| "#{n}: #{v}\r\n" }.join('') +
                                       "Content-Type: #{content_type}\r\n" +
                                       "Subject: test\r\n" +
                                       "\r\n" +
                                       body)
      pp @msg if $DEBUG
    end

    def teardown
      pp @msg if $DEBUG
    end

    def test_header
      setup_message
      assert_equal("Content-Type: text/plain; charset=utf-8\r\n" +
                   "Subject: test\r\n" +
                   "\r\n",
                   @msg.header.raw_source)
    end

    def test_body
      setup_message
      assert_equal("Hello world.\r\n", @msg.body.raw_source)
    end

    def test_media_main_type
      setup_message
      assert_equal('text', @msg.media_main_type)
      assert_equal('TEXT', @msg.media_main_type_upcase)
    end

    def test_media_sub_type
      setup_message
      assert_equal('plain', @msg.media_sub_type)
      assert_equal('PLAIN', @msg.media_sub_type_upcase)
    end

    def test_content_type
      setup_message
      assert_equal('text/plain', @msg.content_type)
      assert_equal('TEXT/PLAIN', @msg.content_type_upcase)
    end

    def test_content_type_parameters
      setup_message(content_type: 'text/plain; charset=utf-8; foo=apple; Bar=Banana')
      assert_equal([ %w[ charset utf-8 ], %w[ foo apple ], %w[ Bar Banana ] ], @msg.content_type_parameters)
    end

    def test_charset
      setup_message
      assert_equal('utf-8', @msg.charset)
    end

    def test_charset_no_value
      setup_message(content_type: 'text/plain')
      assert_nil(@msg.charset)
    end

    def test_boundary
      setup_message(content_type: "multipart/alternative; \r\n	boundary=\"----=_Part_1459891_982342968.1383882437398\"")
      assert_equal('----=_Part_1459891_982342968.1383882437398', @msg.boundary)
    end

    def test_boundary_no_value
      setup_message
      assert_nil(@msg.boundary)
    end

    def test_text?
      setup_message
      assert_equal(true, @msg.text?)
    end

    def test_not_text?
      setup_message(content_type: 'application/octet-stream')
      assert_equal(false, @msg.text?)
    end

    def test_multipart?
      setup_message(content_type: 'multipart/mixed')
      assert_equal(true, @msg.multipart?)
    end

    def test_not_multipart?
      setup_message
      assert_equal(false, @msg.multipart?)
    end

    def test_parts
      setup_message(content_type: 'multipart/mixed; boundary="----=_Part_1459890_1462677911.1383882437398"', body: <<-'EOF')
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
      EOF

      assert_equal(1, @msg.parts.length)
      assert_equal(<<-'EOF', @msg.parts[0].raw_source)
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
      EOF

      assert_equal(2, @msg.parts[0].parts.length)
      assert_equal(<<-'EOF'.chomp, @msg.parts[0].parts[0].raw_source)
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: base64

Cgo9PT09PT09PT09CkFNQVpPTi5DTy5KUAo9PT09PT09PT09CkFtYXpvbi5jby5qcOOBp+WVhuWT
rpvjgavpgIHkv6HjgZXjgozjgb7jgZfjgZ86IHRva2lAZnJlZWRvbS5uZS5qcAoKCg==
      EOF
      assert_equal(<<-'EOF', @msg.parts[0].parts[1].raw_source)
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: quoted-printable

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.=
      EOF
    end

    def test_parts_not_multipart
      setup_message
      assert_nil(@msg.parts)
    end

    def test_parts_no_boundary
      setup_message(content_type: 'multipart/mixed')
      assert_equal([], @msg.parts)
    end

    def test_message?
      setup_message(content_type: 'message/rfc822')
      assert_equal(true, @msg.message?)
    end

    def test_not_message?
      setup_message
      assert_equal(false, @msg.message?)
    end

    def test_message
      setup_message(content_type: 'message/rfc822', body: <<-'EOF')
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
      EOF

      assert_equal(<<-'EOF', @msg.message.raw_source)
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
      EOF
      assert_equal(true, @msg.message.multipart?)
      assert_equal(2, @msg.message.parts.length)
      assert_equal('text/plain', @msg.message.parts[0].content_type)
      assert_equal('us-ascii', @msg.message.parts[0].charset)
      assert_equal('Hello world.', @msg.message.parts[0].body.raw_source)
      assert_equal('application/octet-stream', @msg.message.parts[1].content_type)
      assert_equal('9876543210', @msg.message.parts[1].body.raw_source)
    end

    def test_message_no_msg
      setup_message
      assert_nil(@msg.message)
    end

    def test_date
      setup_message('Date' => 'Fri, 8 Nov 2013 03:47:17 +0000')
      assert_equal(Time.utc(2013, 11, 8, 3, 47, 17), @msg.date)
    end

    def test_date_no_value
      setup_message
      assert_nil(@msg.date)
    end

    def test_date_bad_format
      setup_message('Date' => 'no_date')
      assert_equal(Time.at(0), @msg.date)
    end

    def test_mail_address_header_field
      setup_message('From' => 'Foo <foo@mail.example.com>',
                    'Sender' => 'Bar <bar@mail.example.com>',
                    'Reply-To' => 'Baz <baz@mail.example.com>',
                    'To' => 'Alice <alice@mail.example.com>',
                    'Cc' => 'Bob <bob@mail.example.com>',
                    'Bcc' => 'Kate <kate@mail.example.com>')

      assert_equal([ [ 'Foo', nil, 'foo', 'mail.example.com' ] ], @msg.from)
      assert_equal([ [ 'Bar', nil, 'bar', 'mail.example.com' ] ], @msg.sender)
      assert_equal([ [ 'Baz', nil, 'baz', 'mail.example.com' ] ], @msg.reply_to)
      assert_equal([ [ 'Alice', nil, 'alice', 'mail.example.com' ] ], @msg.to)
      assert_equal([ [ 'Bob', nil, 'bob', 'mail.example.com' ] ], @msg.cc)
      assert_equal([ [ 'Kate', nil, 'kate', 'mail.example.com' ] ], @msg.bcc)
    end

    def test_mail_address_header_field_multi_header_field
      setup_message([ [ 'From', 'Foo <foo@mail.example.com>, Bar <bar@mail.example.com>' ],
                      [ 'from', 'Baz <baz@mail.example.com>' ]
                    ])
      assert_equal([ [ 'Foo', nil, 'foo', 'mail.example.com' ],
                     [ 'Bar', nil, 'bar', 'mail.example.com' ],
                     [ 'Baz', nil, 'baz', 'mail.example.com' ]
                   ],
                   @msg.from)
    end

    def test_mail_address_header_field_no_value
      setup_message
      assert_nil(@msg.from)
    end

    def test_mail_address_header_field_bad_format
      setup_message('From' => 'no_mail_address')
      assert_equal([], @msg.from)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
