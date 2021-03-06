# -*- coding: utf-8 -*-

require 'digest'
require 'fileutils'
require 'pp' if $DEBUG
require 'set'
require 'stringio'

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
        RIMS::Protocol::RequestReader.parse(RIMS::Protocol::RequestReader.scan(description))[0]
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
      simple_mail_body = <<-'EOF'.freeze
Hello world.
      EOF

      MAIL_SIMPLE_TEXT = (<<-"EOF" + simple_mail_body).freeze
To: foo@nonet.org
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Content-MD5: #{[ Digest::MD5.digest(simple_mail_body) ].pack('m').strip}
Content-Language: en-US, en
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

      EOF

      def make_mail_simple
        @simple_mail = RIMS::RFC822::Message.new(MAIL_SIMPLE_TEXT)
        @simple_mail_body = @simple_mail.body.raw_source
      end
      private :make_mail_simple

      MPART_MAIL_TEXT = <<-'EOF'.freeze
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
Content-Disposition: attachment
  ; filename=test.dat
  ; modification-date="Wed, 12 Feb 1997 16:29:51 -0500"

0123456789
--1383.905529.351297
Content-Type: message/rfc822

To: bar@nonet.com
From: foo@nonet.com
Subject: inner multipart
MIME-Version: 1.0
Date: Fri, 8 Nov 2013 19:31:03 +0900
Content-Type: multipart/mixed; boundary="1383.905529.351298"
Content-Disposition: attachment; filename=hello.txt
Content-Language: en
Content-Location: test

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
Content-Disposition: inline

GIF image...
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
Content-Location: foo

HALO
--1383.905529.351300
Content-Type: multipart/alternative; boundary="1383.905529.351301"

--1383.905529.351301
Content-Type: text/plain; charset=us-ascii
Content-Location: bar

alternative message.
--1383.905529.351301
Content-Type: text/html; charset=us-ascii
Content-Location: baz

<html>
<body><p>HTML message</p></body>
</html>
--1383.905529.351301--
--1383.905529.351300--
--1383.905529.351299--
--1383.905529.351297--
      EOF

      def make_mail_multipart
        @mpart_mail = RIMS::RFC822::Message.new(MPART_MAIL_TEXT)
      end
      private :make_mail_multipart

      MAIL_MIME_SUBJECT_TEXT = <<-'EOF'.freeze
Date: Fri, 8 Nov 2013 19:31:03 +0900
Subject: =?ISO-2022-JP?B?GyRCJEYkOSRIGyhC?=
From: foo@nonet.com, bar <bar@nonet.com>
Sender: foo@nonet.com
Reply-To: foo@nonet.com
To: alice@test.com, bob <bob@test.com>
Cc: Kate <kate@test.com>
Bcc: foo@nonet.com
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
In-Reply-To: <20131106081723.5KJU1774292@smtp.test.com>
Message-Id: <20131107214750.445A1255B9F@smtp.nonet.com>

Hello world.
      EOF

      def make_mail_mime_subject
        @mime_subject_mail = RIMS::RFC822::Message.new(MAIL_MIME_SUBJECT_TEXT)
      end
      private :make_mail_mime_subject

      MAIL_EMPTY_TEXT = ''.freeze

      def make_mail_empty
        @empty_mail = RIMS::RFC822::Message.new(MAIL_EMPTY_TEXT)
      end
      private :make_mail_empty

      MAIL_NO_BODY_TEXT = "Subject: foo\r\n\r\n".freeze

      def make_mail_no_body
        @no_body_mail = RIMS::RFC822::Message.new(MAIL_NO_BODY_TEXT)
      end
      private :make_mail_no_body

      MAIL_ADDRESS_HEADER_PATTERN_TEXT = <<-'EOF'.freeze
To: "foo@nonet.org" <foo@nonet.org>
From: bar@nonet.org
Subject: test
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit
Date: Fri,  8 Nov 2013 06:47:50 +0900 (JST)

Hello world.
      EOF

      def make_mail_address_header_pattern
        @address_header_pattern_mail = RIMS::RFC822::Message.new(MAIL_ADDRESS_HEADER_PATTERN_TEXT)
      end
      private :make_mail_address_header_pattern
    end

    module KeyValueStoreTestUtility
      def open_database
        raise NotImplementedError, "not implemented to open `#{@name}'"
      end

      def make_key_value_store
        raise NotImplementedError, 'not implemented.'
      end

      def db_close
        @db.close
      end

      def db_closed?
        @db.closed?
      end

      def db_fetch(key)
        @db[key]
      end

      def db_key?(key)
        @db.key? key
      end

      def db_each_key
        return enum_for(:db_each_key) unless block_given?
        @db.each_key do |key|
          yield(key)
        end
      end

      def db_closed_error
        RuntimeError
      end

      def db_closed_fetch_error
        db_closed_error
      end

      def db_closed_store_error
        db_closed_error
      end

      def db_closed_delete_error
        db_closed_error
      end

      def db_closed_key_error
        db_closed_error
      end

      def db_closed_each_key_error
        db_closed_error
      end

      def db_closed_each_value_error
        db_closed_error
      end

      def db_closed_each_pair_error
        db_closed_error
      end

      def setup
        @base_dir = 'kvs_test_dir'
        FileUtils.mkdir_p(@base_dir)
        @name = File.join(@base_dir, "kvs_test.db.#{$$}")

        @db = open_database
        @kvs = make_key_value_store
      end

      def teardown
        db_close unless db_closed?
        FileUtils.rm_rf(@base_dir)
      end

      def test_store_fetch
        assert_nil(db_fetch('foo'))
        assert_nil(@kvs['foo'])

        assert_equal('apple', (@kvs['foo'] = 'apple'))
        assert_equal('apple', db_fetch('foo'))
        assert_equal('apple', @kvs['foo'])

        # update
        assert_equal('banana', (@kvs['foo'] = 'banana'))
        assert_equal('banana', db_fetch('foo'))
        assert_equal('banana', @kvs['foo'])
      end

      def test_delete
        assert_nil(@kvs.delete('foo'))

        @kvs['foo'] = 'apple'
        assert_equal('apple', @kvs.delete('foo'))

        assert_nil(db_fetch('foo'))
        assert_nil(@kvs['foo'])
      end

      def test_key?
        assert_equal(false, (db_key? 'foo'))
        assert_equal(false, (@kvs.key? 'foo'))

        @kvs['foo'] = 'apple'
        assert_equal(true, (db_key? 'foo'))
        assert_equal(true, (@kvs.key? 'foo'))

        # update
        @kvs['foo'] = 'banana'
        assert_equal(true, (db_key? 'foo'))
        assert_equal(true, (@kvs.key? 'foo'))

        @kvs.delete('foo')
        assert_equal(false, (db_key? 'foo'))
        assert_equal(false, (@kvs.key? 'foo'))
      end

      def test_each_key
        assert_equal(%w[], db_each_key.to_a)
        assert_equal(%w[], @kvs.each_key.to_a)

        @kvs['foo'] = 'apple'
        assert_equal(%w[ foo ], db_each_key.to_a)
        assert_equal(%w[ foo ], @kvs.each_key.to_a)
        assert_equal(%w[ apple ], @kvs.each_value.to_a)
        assert_equal([ %w[ foo apple ] ], @kvs.each_pair.to_a)

        @kvs['bar'] = 'banana'
        assert_equal(%w[ foo bar ].sort, db_each_key.sort)
        assert_equal(%w[ foo bar ].sort, @kvs.each_key.sort)
        assert_equal(%w[ apple banana ].sort, @kvs.each_value.sort)
        assert_equal([ %w[ foo apple ], %w[ bar banana ] ].sort, @kvs.each_pair.sort)

        @kvs['baz'] = 'orange'
        assert_equal(%w[ foo bar baz ].sort, db_each_key.sort)
        assert_equal(%w[ foo bar baz ].sort, @kvs.each_key.sort)
        assert_equal(%w[ apple banana orange ].sort, @kvs.each_value.sort)
        assert_equal([ %w[ foo apple ], %w[ bar banana ], %w[ baz orange ] ].sort, @kvs.each_pair.sort)

        @kvs.delete('bar')
        assert_equal(%w[ foo baz ].sort, db_each_key.sort)
        assert_equal(%w[ foo baz ].sort, @kvs.each_key.sort)
        assert_equal(%w[ apple orange ].sort, @kvs.each_value.sort)
        assert_equal([ %w[ foo apple ], %w[ baz orange ] ].sort, @kvs.each_pair.sort)

        # update
        @kvs['baz'] = 'melon'
        assert_equal(%w[ foo baz ].sort, db_each_key.sort)
        assert_equal(%w[ foo baz ].sort, @kvs.each_key.sort)
        assert_equal(%w[ apple melon ].sort, @kvs.each_value.sort)
        assert_equal([ %w[ foo apple ], %w[ baz melon ] ].sort, @kvs.each_pair.sort)
      end

      def test_sync
        @kvs.sync
      end

      def test_close
        @kvs.close
        assert_equal(true, db_closed?)

        # closed exception
        assert_raise(db_closed_fetch_error) { @kvs['foo'] }
        assert_raise(db_closed_store_error) { @kvs['foo'] = 'apple' }
        assert_raise(db_closed_delete_error) { @kvs.delete('foo') }
        assert_raise(db_closed_key_error) { @kvs.key? 'foo' }
        assert_raise(db_closed_each_key_error) { @kvs.each_key.to_a }
        assert_raise(db_closed_each_value_error) { @kvs.each_value.to_a }
        assert_raise(db_closed_each_pair_error) { @kvs.each_pair.to_a }
      end
    end

    module KeyValueStoreOpenCloseTestUtility
      def get_kvs_name
        raise NotImplementedError, 'not implemented.'
      end

      def get_config
        {}
      end

      def setup
        @base_dir = 'kvs_open_close_test_dir'
        @name = File.join(@base_dir, 'test_kvs')
        FileUtils.mkdir_p(@base_dir)

        @Test_KeyValueStore = RIMS::KeyValueStore::FactoryBuilder.get_plug_in(get_kvs_name)
      end

      def teardown
        FileUtils.rm_rf(@base_dir)
      end

      def test_open_close
        assert_equal(false, (@Test_KeyValueStore.exist? @name))

        kvs = @Test_KeyValueStore.open_with_conf(@name, get_config)
        begin
          assert_equal(true, (@Test_KeyValueStore.exist? @name))
        ensure
          kvs.close
        end
        assert_equal(true, (@Test_KeyValueStore.exist? @name))

        kvs.destroy
        assert_equal(false, (@Test_KeyValueStore.exist? @name))
      end
    end

    module DumpTestUtility
      def get_dump_name
        raise NotImplementedError, 'not implemented.'
      end

      def setup
        @output = StringIO.new('', 'w')
        @input = StringIO.new('', 'r')
        @dump_writer = RIMS::Dump.get_writer_plug_in(get_dump_name).new(@output)
        @dump_reader = RIMS::Dump.get_reader_plug_in(get_dump_name).new(@input)
      end

      def _test_write_read(data)
        contents = data

        for filename, content in contents
          @dump_writer.add(filename, content)
        end
        pp @output.string if $DEBUG

        @input.string = @output.string
        read_contents = @dump_reader.each.to_a
        assert_equal(contents,
                     read_contents.map{|filename, content, valid|
                       [ filename, content ]
                     })
        for filename, content, valid in read_contents
          assert(valid, filename)
        end
      end
      private :_test_write_read

      def test_write_read_empty
        _test_write_read([])
      end

      def test_write_read_rfc822
        _test_write_read([ [ 'test/message/0', ProtocolFetchMailSample::MAIL_SIMPLE_TEXT ] ])
      end

      def test_write_read_text
        _test_write_read([ [ 'test/text/0', "Hello world.\n" ] ])
      end

      def test_write_read_binary
        _test_write_read([ [ 'test/bin/0', 0xFF.chr * 32 ] ])
      end

      def test_write_read_composite
        _test_write_read([ [ 'test/message/0', ProtocolFetchMailSample::MAIL_SIMPLE_TEXT ],
                           [ 'test/text/0',    "Hello world.\n" ],
                           [ 'test/bin/0',     0xFF.chr * 32 ]
                         ])
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
