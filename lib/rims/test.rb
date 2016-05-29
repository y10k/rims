# -*- coding: utf-8 -*-

require 'set'

module RIMS
  module Test
    module AssertUtility
      def literal(text_string)
        "{#{text_string.bytesize}}\r\n#{text_string}"
      end
      module_function :literal

      def make_header_text(name_value_pair_list, select_list: [], reject_list: [])
        name_value_pair_list = name_value_pair_list.to_a.dup
        select_set = select_list.map{|name| name.downcase }.to_set
        reject_set = reject_list.map{|name| name.downcase }.to_set

        name_value_pair_list.select!{|name, value| select_set.include? name.downcase } unless select_set.empty?
        name_value_pair_list.reject!{|name, value| reject_set.include? name.downcase } unless reject_set.empty?
        name_value_pair_list.map{|name, value| "#{name}: #{value}\r\n" }.join('') + "\r\n"
      end
      module_function :make_header_text

      def message_data_list(msg_data_array)
        msg_data_array.map{|msg_data|
          case (msg_data)
          when String
            msg_data
          when Array
            '(' << message_data_list(msg_data) << ')'
          else
            raise "unknown message data: #{msg_data}"
          end
        }.join(' ')
      end
      module_function :message_data_list

      def make_body(description)
        reader = RIMS::Protocol::RequestReader.new(StringIO.new('', 'r'), StringIO.new('', 'w'), Logger.new(STDOUT))
        reader.parse(reader.scan_line(description))[0]
      end
      private :make_body

      def assert_strenc_equal(expected_enc, expected_str, expr_str)
        assert_equal(Encoding.find(expected_enc), expr_str.encoding)
        assert_equal(expected_str.dup.force_encoding(expected_enc), expr_str)
      end
      module_function :assert_strenc_equal
    end

    module PseudoAuthenticationUtility
      def make_pseudo_time_source(src_time)
        t = src_time
        proc{
          t = t + 1
          t.dup
        }
      end
      module_function :make_pseudo_time_source

      def make_pseudo_random_string_source(random_seed)
        r = Random.new(random_seed)
        proc{ r.bytes(16).each_byte.map{|c| format('%02x', c ) }.join('') }
      end
      module_function :make_pseudo_random_string_source
    end

    module ProtocolFetchMailSample
      def make_mail_simple
        @simple_mail = RIMS::RFC822::Message.new(<<-'EOF')
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
      private :make_mail_simple

      def make_mail_multipart
        @mpart_mail = RIMS::RFC822::Message.new(<<-'EOF')
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
      private :make_mail_multipart

      def make_mail_mime_subject
        @mime_subject_mail = RIMS::RFC822::Message.new(<<-'EOF')
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
      private :make_mail_mime_subject

      def make_mail_empty
        @empty_mail = RIMS::RFC822::Message.new('')
      end
      private :make_mail_empty

      def make_mail_no_body
        @no_body_mail = RIMS::RFC822::Message.new('foo')
      end
      private :make_mail_no_body

      def make_mail_address_header_pattern
        @address_header_pattern_mail = RIMS::RFC822::Message.new(<<-'EOF')
To: "foo@nonet.org" <foo@nonet.org>
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
EOF
      end
      private :make_mail_address_header_pattern
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
