# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolFetchParserTest < Test::Unit::TestCase
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

      @mail_store.add_msg(@inbox_id, <<-'EOF', Time.parse('2013-11-08 06:47:50 +0900'))
To: foo@nonet.org
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain;us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
      EOF

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
Content-Type: application/octet-steram

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
Content-Type: text/plain: charset=us-ascii

alternative message.
--1383.905529.351301
Content-Type: text/html: charset=us-ascii

<html>
<body><p>HTML message</p></body>
</html>
--1383.905529.351301--
--1383.905529.351300--
--1383.905529.351299--
--1383.905529.351297--
      EOF

      @folder = @mail_store.select_mbox(@inbox_id)
      @parser = RIMS::Protocol::FetchParser.new(@mail_store, @folder)
    end

    def test_parse_internaldate
      fetch = @parser.parse('INTERNALDATE')
      assert_equal('INTERNALDATE "08-11-2013 06:47:50 +0900"', fetch.call(@folder.msg_list[0]))
      assert_equal('INTERNALDATE "08-11-2013 19:31:03 +0900"', fetch.call(@folder.msg_list[1]))
    end

    def test_parse_uid
      fetch = @parser.parse('UID')
      assert_equal('UID 1', fetch.call(@folder.msg_list[0]))
      assert_equal('UID 2', fetch.call(@folder.msg_list[1]))
    end

    def test_parse_group_empty
      fetch = @parser.parse([ :group ])
      assert_equal('()', fetch.call(@folder.msg_list[0]))
      assert_equal('()', fetch.call(@folder.msg_list[1]))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
