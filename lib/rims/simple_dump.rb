# -*- coding: utf-8 -*-

require 'digest'

module RIMS
  class SimpleText_DumpReader < DumpReader
    def each                    # :yields: filename, contnet, valid
      return enum_for(:each) unless block_given?

      while (line = @input.gets)
        line.chomp!
        header_size, checksum = line.split(',', 2)

        header_size =~ /\A \d+ \z/x or raise "invalid header size format: #{header_size}"
        header_size = header_size.to_i

        checksum =~ /\A \d+ \z/x or raise "invalid header checksum format: #{checksum}"
        checksum = checksum.to_i

        header_text = @input.read(header_size) or raise 'not found a header.'
        header_text.sum == checksum or raise "broken header: #{header_text}"
        header = RFC822::Header.new(header_text)

        (header.key? 'Content-Length') or raise 'not found a content-length header.'
        header['Content-Length'] =~ /\A \d+ \z/x or raise "invalid content-length header format: #{header['Content-Length']}"
        content_length = header['Content-Length'].to_i

        (header.key? 'Content-Transfer-Encoding') or raise 'not found a content-transfer-encoding header.'
        content_encoding = header['Content-Transfer-Encoding']

        (header.key? 'Content-MD5') or raise 'not found a content-md5 header.'
        content_md5 = header['Content-MD5'].unpack('m')[0]

        (header.key? 'Content-Disposition') or raise 'not found a content-disposition header.'
        disposition = RFC822.parse_content_disposition(header['Content-Disposition'])
        filename = disposition.dig(1, 'filename', 1) or raise 'not found a filename parameter.'

        body = @input.read(content_length) or raise 'not found a body.'
        case (content_encoding)
        when '7bit'
          content = body
        when 'base64'
          content = body.unpack('m')[0]
        else
          raise "unknown content-transfer-encoding header format: #{content_encoding}"
        end
        valid = Digest::MD5.digest(content) == content_md5

        yield(filename, content, valid)
      end

      self
    end
  end

  class SimpleText_DumpWriter < DumpWriter
    def add(filename, content)
      if (filename.include? '/message/') then
        if (content.ascii_only?) then
          media_type = 'message/rfc822'
        else
          media_type = 'application/octet-stream'
        end
      else
        if (content.ascii_only?) then
          media_type = 'text/plain'
        else
          media_type = 'application/octet-stream'
        end
      end

      if (content.ascii_only?) then
        content_encoding = '7bit'
        body = content
      else
        content_encoding = 'base64'
        body = [ content ].pack('m')
      end

      content_md5 = [ Digest::MD5.digest(content) ].pack('m').strip

      header = <<-EOF
Content-Type: #{media_type}
Content-Length: #{body.bytesize}
Content-Transfer-Encoding: #{content_encoding}
Content-MD5: #{content_md5}
Content-Disposition: attachment; filename="#{filename}"

      EOF
      checksum = header.sum

      @output.puts("#{header.bytesize},#{checksum}")
      @output.write(header)
      @output.write(body)

      self
    end
  end

  Dump.add_plug_in('simple', SimpleText_DumpReader, SimpleText_DumpWriter)
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
