# -*- coding: utf-8 -*-

require 'digest'
require 'pp' if $DEBUG
require 'rims'
require 'set'
require 'stringio'
require 'test/unit'

module RIMS::Test
  class SimpleText_DumpTest < Test::Unit::TestCase
    include RIMS::Test::DumpTestUtility
    include RIMS::Test::ProtocolFetchMailSample

    def get_dump_name
      require 'rims/simple_dump' # load plug-in explicitly
      'simple'
    end

    data('invalid_header_size_format' => [ "x,0\n", /invalid header size format/ ],
         'invalid header size format' => [ "0,x\n", /invalid header checksum format/ ],
         'not_found_a_header'         => [ "1,0\n", /not found a header/ ])
    def test_read_error_header_line(data)
      line, expected_error_message_pattern = data
      @input.string = line
      error = assert_raise(RuntimeError) {
        @dump_reader.each do
          flunk
        end
      }
      assert_match(expected_error_message_pattern, error.message)
    end

    def test_read_error_broken_header
      @dump_writer.add('test', MAIL_SIMPLE_TEXT)
      broken_header_dump = @output.string
      broken_header_dump[-(MAIL_SIMPLE_TEXT.bytesize + 1)] = "\0"

      @input.string = broken_header_dump
      error = assert_raise(RuntimeError) {
        @dump_reader.each do
          flunk
        end
      }
      assert_match(/broken header/, error.message)
    end

    data('no content-length' => [
           <<-"EOF",
Content-Transfer-Encoding: 7bit
Content-MD5: #{[ Digest::MD5.digest('') ].pack('m').strip}
Content-Disposition: attachment; filename="test"

           EOF
           /not found a content-length header/
         ],
         'invalid content-length' => [
           <<-"EOF",
Content-Length: x
Content-Transfer-Encoding: 7bit
Content-MD5: #{[ Digest::MD5.digest('') ].pack('m').strip}
Content-Disposition: attachment; filename="test"

           EOF
           /invalid content-length header format/
         ],
         'no content-transfer-encoding' => [
           <<-"EOF",
Content-Length: 0
Content-MD5: #{[ Digest::MD5.digest('') ].pack('m').strip}
Content-Disposition: attachment; filename="test"

           EOF
           /not found a content-transfer-encoding header/
         ],
         'unknown content-transfer-encoding' => [
           <<-"EOF",
Content-Length: 0
Content-Transfer-Encoding: x
Content-MD5: #{[ Digest::MD5.digest('') ].pack('m').strip}
Content-Disposition: attachment; filename="test"

           EOF
           /unknown content-transfer-encoding header format/
         ],
         'no content-md5' => [
           <<-"EOF",
Content-Length: 0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="test"

           EOF
           /not found a content-md5 header/
         ],
         'no content-disposition' => [
           <<-"EOF",
Content-Length: 0
Content-Transfer-Encoding: 7bit
Content-MD5: #{[ Digest::MD5.digest('') ].pack('m').strip}

           EOF
           /not found a content-disposition header/
         ],
         'content-disposition no filename' => [
           <<-"EOF",
Content-Length: 0
Content-Transfer-Encoding: 7bit
Content-MD5: #{[ Digest::MD5.digest('') ].pack('m').strip}
Content-Disposition: attachment"

           EOF
           /not found a filename parameter/
         ])
    def test_read_error_header(data)
      header, expected_error_message_pattern = data
      @input.string = "#{header.bytesize},#{header.sum}\n#{header}"
      error = assert_raise(RuntimeError) {
        @dump_reader.each do
          flunk
        end
      }
      assert_match(expected_error_message_pattern, error.message)
    end

    def test_read_invalid_content
      @dump_writer.add('test', MAIL_SIMPLE_TEXT)
      broken_content_dump = @output.string
      broken_content_dump[-1] = "\0"

      @input.string = broken_content_dump
      read_contents = @dump_reader.each.to_a
      (_, _, valid), *_ = read_contents
      refute(valid)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
