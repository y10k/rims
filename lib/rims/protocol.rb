# -*- coding: utf-8 -*-

module RIMS
  class ProtocolError < Error
  end

  class SyntaxError < ProtocolError
  end

  class MessageSetSyntaxError < SyntaxError
  end

  module Protocol
    def quote(s)
      qs = ''.encode(s.encoding)
      case (s)
      when /"/, /\n/
        qs << '{' << s.bytesize.to_s << "}\r\n" << s
      else
        qs << '"' << s << '"'
      end
    end
    module_function :quote

    def compile_wildcard(pattern)
      src = '\A'
      src << pattern.gsub(/.*?[*%]/) {|s| Regexp.quote(s[0..-2]) + '.*' }
      src << Regexp.quote($') if $'
      src << '\z'
      Regexp.compile(src)
    end
    module_function :compile_wildcard

    IO_DATA_DUMP = false        # true for debug

    def io_data_log(str)
      s = '<'
      s << str.encoding.to_s
      if (str.ascii_only?) then
        s << ':ascii_only'
      end
      if (IO_DATA_DUMP) then
        s << '> ' << str.inspect
      else
        s << '> ' << str.bytesize.to_s << ' octets'
      end
    end
    module_function :io_data_log

    def encode_base64(plain_txt)
      [ plain_txt ].pack('m').each_line.map{|line| line.strip }.join('')
    end
    module_function :encode_base64

    def decode_base64(base64_txt)
      base64_txt.unpack('m')[0]
    end
    module_function :decode_base64

    autoload :FetchBody,            'rims/protocol/parser'
    autoload :RequestReader,        'rims/protocol/parser'
    autoload :AuthenticationReader, 'rims/protocol/parser'
    autoload :SearchParser,         'rims/protocol/parser'
    autoload :FetchParser,          'rims/protocol/parser'
    autoload :ConnectionLimits,     'rims/protocol/connection'
    autoload :ConnectionTimer,      'rims/protocol/connection'
    autoload :Decoder,              'rims/protocol/decoder'

    def body(symbol: nil, option: nil, section: nil, section_list: nil, partial_origin: nil, partial_size: nil)
      FetchBody.new(symbol, option, section, section_list, partial_origin, partial_size)
    end
    module_function :body
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
