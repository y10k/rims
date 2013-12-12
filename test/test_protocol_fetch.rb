# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolFetchParserTest < Test::Unit::TestCase
    include RIMS::Protocol::FetchParser::Utils

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

    def make_fetch_parser
      yield if block_given?
      @folder = @mail_store.select_mbox(@inbox_id)
      @parser = RIMS::Protocol::FetchParser.new(@mail_store, @folder)
    end
    private :make_fetch_parser

    def add_mail_simple
      @mail_store.add_msg(@inbox_id, <<-'EOF', Time.parse('2013-11-08 06:47:50 +0900'))
To: foo@nonet.org
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
      EOF
    end
    private :add_mail_simple

    def add_mail_multipart
      @mail_store.add_msg(@inbox_id, <<-'EOF', Time.parse('2013-11-08 19:31:03 +0900'))
To: bar@nonet.com
From: foo@nonet.com
Subject: multipart test
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351297"

--1383.905529.351297
Content-Type: text/plain; charset=us-ascii

Multipart test.
--1383.905529.351297
Content-Type: application/octet-stream

0123456789
--1383.905529.351297
Content-Type: message/rfc822

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
--1383.905529.351297
Content-Type: multipart/mixed; boundary="1383.905529.351299"

--1383.905529.351299
Content-Type: image/gif

--1383.905529.351299
Content-Type: message/rfc822

To: bar@nonet.com
From: foo@nonet.com
Subject: inner multipart
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351300"

--1383.905529.351300
Content-Type: text/plain; charset=us-ascii

HALO
--1383.905529.351300
Content-Type: multipart/alternative; boundary="1383.905529.351301"

--1383.905529.351301
Content-Type: text/plain; charset=us-ascii

alternative message.
--1383.905529.351301
Content-Type: text/html; charset=us-ascii

<html>
<body><p>HTML message</p></body>
</html>
--1383.905529.351301--
--1383.905529.351300--
--1383.905529.351299--
--1383.905529.351297--
      EOF
    end
    private :add_mail_multipart

    def add_mail_mime_subject
      @mail_store.add_msg(@inbox_id, <<-'EOF', Time.parse('2013-11-08 19:31:03 +0900'))
Date: Fri, 8 Nov 2013 19:31:03 +0900
Subject: =?ISO-2022-JP?B?GyRCJEYkOSRIGyhC?=
From: foo@nonet.com, bar <bar@nonet.com>
Sender: foo@nonet.com
Reply-To: foo@nonet.com
To: alice@test.com, bob <bob@test.com>
Cc: Kate <kate@test.com>
Bcc: foo@nonet.com
In-Reply-To: <20131106081723.5KJU1774292@smtp.testt.com>
Message-Id: <20131107214750.445A1255B9F@smtp.nonet.com>

Hello world.
      EOF
    end
    private :add_mail_mime_subject

    def test_parse_bodystructure
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      fetch_body = @parser.parse('BODY')
      fetch_bodystructure = @parser.parse('BODYSTRUCTURE')
      assert_equal('BODY ' +
                   encode_list([ 'TEXT',
                                 'plain',
                                 %w[ charset us-ascii ],
                                 nil,
                                 nil,
                                 '7bit',
                                 212,
                                 9
                               ]),
                   fetch_body.call(@folder.msg_list[0]))
      assert_equal('BODYSTRUCTURE ' +
                   encode_list([ 'TEXT',
                                 'plain',
                                 %w[ charset us-ascii ],
                                 nil,
                                 nil,
                                 '7bit',
                                 212,
                                 9
                               ]),
                   fetch_bodystructure.call(@folder.msg_list[0]))
      assert_equal('BODY ' +
                   encode_list([ [ 'TEXT', 'plain', %w[ charset us-ascii], nil, nil, nil, 63, 4 ],
                                 [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                 [
                                   'MESSAGE', 'RFC822', [], nil, nil, nil, 401,
                                   [
                                     'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                     %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                   ],
                                   [
                                     [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 60, 4 ],
                                     [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                     'mixed'
                                   ],
                                   19
                                 ],
                                 [
                                   [ 'image', 'gif', [], nil, nil, nil, 27 ],
                                   [
                                     'MESSAGE', 'RFC822', [], nil, nil, nil, 641,
                                     [
                                       'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                       %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                     ],
                                     [
                                       [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 52, 4 ],
                                       [
                                         [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 68, 4 ],
                                         [ 'TEXT', 'html', %w[ charset us-ascii ], nil, nil, nil, 96, 6 ],
                                         'alternative'
                                       ],
                                       'mixed'
                                     ],
                                     29
                                   ],
                                   'mixed',
                                 ],
                                 'mixed'
                               ]),
                   fetch_body.call(@folder.msg_list[1]))
      assert_equal('BODYSTRUCTURE ' +
                   encode_list([ [ 'TEXT', 'plain', %w[ charset us-ascii], nil, nil, nil, 63, 4 ],
                                 [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                 [
                                   'MESSAGE', 'RFC822', [], nil, nil, nil, 401,
                                   [
                                     'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                     %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                   ],
                                   [
                                     [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 60, 4 ],
                                     [ 'application', 'octet-stream', [], nil, nil, nil, 54 ],
                                     'mixed'
                                   ],
                                   19
                                 ],
                                 [
                                   [ 'image', 'gif', [], nil, nil, nil, 27 ],
                                   [
                                     'MESSAGE', 'RFC822', [], nil, nil, nil, 641,
                                     [
                                       'Fri, 08 Nov 2013 19:31:03 +0900', 'inner multipart',
                                       %w[ foo@nonet.com ], nil, nil, %w[ bar@nonet.com ], nil, nil, nil, nil
                                     ],
                                     [
                                       [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 52, 4 ],
                                       [
                                         [ 'TEXT', 'plain', %w[ charset us-ascii ], nil, nil, nil, 68, 4 ],
                                         [ 'TEXT', 'html', %w[ charset us-ascii ], nil, nil, nil, 96, 6 ],
                                         'alternative'
                                       ],
                                       'mixed'
                                     ],
                                     29
                                   ],
                                   'mixed',
                                 ],
                                 'mixed'
                               ]),
                   fetch_bodystructure.call(@folder.msg_list[1]))
    end

    def test_parse_envelope
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
        add_mail_mime_subject
      }
      fetch = @parser.parse('ENVELOPE')
      assert_equal('ENVELOPE (' + [
                     '"Fri, 08 Nov 2013 06:47:50 +0900"',       # Date
                     '"test"',                                  # Subject
                     '("bar@nonet.org")',                       # From
                     'NIL',                                     # Sender
                     'NIL',                                     # Reply-To
                     '("foo@nonet.org")',                       # To
                     'NIL',                                     # Cc
                     'NIL',                                     # Bcc
                     'NIL',                                     # In-Reply-To
                     'NIL'                                      # Message-Id
                   ].join(' ') +')',
                   fetch.call(@folder.msg_list[0]))
      assert_equal('ENVELOPE (' + [
                     '"Fri, 08 Nov 2013 19:31:03 +0900"',       # Date
                     '"multipart test"',                        # Subject
                     '("foo@nonet.com")',                       # From
                     'NIL',                                     # Sender
                     'NIL',                                     # Reply-To
                     '("bar@nonet.com")',                       # To
                     'NIL',                                     # Cc
                     'NIL',                                     # Bcc
                     'NIL',                                     # In-Reply-To
                     'NIL'                                      # Message-Id
                   ].join(' ') +')',
                   fetch.call(@folder.msg_list[1]))
      assert_equal('ENVELOPE (' + [
                     '"Fri, 08 Nov 2013 19:31:03 +0900"',       # Date
                     '"=?ISO-2022-JP?B?GyRCJEYkOSRIGyhC?="',    # Subject
                     '("foo@nonet.com" "bar@nonet.com")',       # From
                     '("foo@nonet.com")',                       # Sender
                     '("foo@nonet.com")',                       # Reply-To
                     '("alice@test.com" "bob@test.com")',       # To
                     '("kate@test.com")',                       # Cc
                     '("foo@nonet.com")',                       # Bcc
                     '"20131106081723.5KJU1774292@smtp.testt.com"',# In-Reply-To
                     '"20131107214750.445A1255B9F@smtp.nonet.com"' # Message-Id
                   ].join(' ') +')',
                   fetch.call(@folder.msg_list[2]))
    end

    def test_parse_flags
      make_fetch_parser{
        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'answered', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'flagged', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'deleted', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'seen', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', false)
        @mail_store.set_msg_flag(@inbox_id, id, 'draft', true)

        id = add_mail_simple
        @mail_store.set_msg_flag(@inbox_id, id, 'recent', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'answered', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'flagged', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'deleted', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'seen', true)
        @mail_store.set_msg_flag(@inbox_id, id, 'draft', true)
      }
      fetch = @parser.parse('FLAGS')
      assert_equal('FLAGS ()', fetch.call(@folder.msg_list[0]))
      assert_equal('FLAGS (\Recent)', fetch.call(@folder.msg_list[1]))
      assert_equal('FLAGS (\Answered)', fetch.call(@folder.msg_list[2]))
      assert_equal('FLAGS (\Flagged)', fetch.call(@folder.msg_list[3]))
      assert_equal('FLAGS (\Deleted)', fetch.call(@folder.msg_list[4]))
      assert_equal('FLAGS (\Seen)', fetch.call(@folder.msg_list[5]))
      assert_equal('FLAGS (\Draft)', fetch.call(@folder.msg_list[6]))
      assert_equal('FLAGS (' +
                   RIMS::MailStore::MSG_FLAG_NAMES.map{|n| "\\#{n.capitalize}" }.join(' ') +
                   ')', fetch.call(@folder.msg_list[7]))
    end

    def test_parse_internaldate
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      }
      fetch = @parser.parse('INTERNALDATE')
      assert_equal('INTERNALDATE "08-11-2013 06:47:50 +0900"', fetch.call(@folder.msg_list[0]))
      assert_equal('INTERNALDATE "08-11-2013 19:31:03 +0900"', fetch.call(@folder.msg_list[1]))
    end

    def test_parse_uid
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      } 
      fetch = @parser.parse('UID')
      assert_equal('UID 1', fetch.call(@folder.msg_list[0]))
      assert_equal('UID 2', fetch.call(@folder.msg_list[1]))
    end

    def test_parse_group_empty
      make_fetch_parser{
        add_mail_simple
        add_mail_multipart
      } 
      fetch = @parser.parse([ :group ])
      assert_equal('()', fetch.call(@folder.msg_list[0]))
      assert_equal('()', fetch.call(@folder.msg_list[1]))
    end
  end

  class ProtocolFetchParserUtilsTest < Test::Unit::TestCase
    def setup
      @mail_simple = Mail.new(<<-'EOF')
To: foo@nonet.org
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
      EOF

      @mail_multipart = Mail.new(<<-'EOF')
To: bar@nonet.com
From: foo@nonet.com
Subject: multipart test
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351297"

--1383.905529.351297
Content-Type: text/plain; charset=us-ascii

Multipart test.
--1383.905529.351297
Content-Type: application/octet-stream

0123456789
--1383.905529.351297
Content-Type: message/rfc822

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
--1383.905529.351297
Content-Type: multipart/mixed; boundary="1383.905529.351299"

--1383.905529.351299
Content-Type: image/gif

--1383.905529.351299
Content-Type: message/rfc822

To: bar@nonet.com
From: foo@nonet.com
Subject: inner multipart
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351300"

--1383.905529.351300
Content-Type: text/plain; charset=us-ascii

HALO
--1383.905529.351300
Content-Type: multipart/alternative; boundary="1383.905529.351301"

--1383.905529.351301
Content-Type: text/plain; charset=us-ascii

alternative message.
--1383.905529.351301
Content-Type: text/html; charset=us-ascii

<html>
<body><p>HTML message</p></body>
</html>
--1383.905529.351301--
--1383.905529.351300--
--1383.905529.351299--
--1383.905529.351297--
      EOF
    end

    def test_get_body_section
      assert_equal(@mail_simple, RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_simple, []))
      assert_equal(@mail_simple, RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_simple, [ 1 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_simple, [ 1, 1 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_simple, [ 2 ]))

      assert_equal(@mail_multipart.raw_source, RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, []).raw_source)
      assert_equal(@mail_multipart.parts[0].raw_source, RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 1 ]).raw_source)
      assert_equal(@mail_multipart.parts[1].raw_source, RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 2 ]).raw_source)
      assert_equal(@mail_multipart.parts[2].raw_source, RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 3 ]).raw_source)
      assert_equal(Mail.new(@mail_multipart.parts[2].body.raw_source).parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 3, 1 ]).raw_source)
      assert_equal(Mail.new(@mail_multipart.parts[2].body.raw_source).parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 3, 2 ]).raw_source)
      assert_equal(@mail_multipart.parts[3].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4 ]).raw_source)
      assert_equal(@mail_multipart.parts[3].parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 1 ]).raw_source)
      assert_equal(@mail_multipart.parts[3].parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 2 ]).raw_source)
      assert_equal(Mail.new(@mail_multipart.parts[3].parts[1].body.raw_source).parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 2, 1 ]).raw_source)
      assert_equal(Mail.new(@mail_multipart.parts[3].parts[1].body.raw_source).parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 2, 2 ]).raw_source)
      assert_equal(Mail.new(@mail_multipart.parts[3].parts[1].body.raw_source).parts[1].parts[0].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 2, 2, 1 ]).raw_source)
      assert_equal(Mail.new(@mail_multipart.parts[3].parts[1].body.raw_source).parts[1].parts[1].raw_source,
                   RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 2, 2, 2 ]).raw_source)
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 5 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 3, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 2, 3 ]))
      assert_nil(RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 2, 2, 3 ]))

      assert_raise(RIMS::SyntaxError) {
        RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_simple, [ 0 ])
      }
      assert_raise(RIMS::SyntaxError) {
        RIMS::Protocol::FetchParser::Utils.get_body_section(@mail_multipart, [ 4, 2, 2, 0 ])
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
