# -*- coding: utf-8 -*-

module RIMS
  module RFC822
    def split_message(msg_txt)
      header_txt, body_txt = msg_txt.lstrip.split(/\r?\n\r?\n/, 2)
      header_txt << $& if $&
      [ header_txt, body_txt ]
    end
    module_function :split_message

    def parse_header(header_txt)
      field_pair_list = header_txt.scan(%r{
        ^((?#name) \S+ ) \s* : \s* ((?#value)
                                    .*? (?: \n|\z)
                                    (?: ^\s .*? (?: \n|\z) )*
                                   )
      }x)

      for name, value in field_pair_list
        value.strip!
      end

      field_pair_list
    end
    module_function :parse_header

    def unquote_phrase(phrase_txt)
      state = :raw
      src_txt = phrase_txt.dup
      dst_txt = ''.encode(phrase_txt.encoding)

      while (src_txt.sub!(/\A(:? " | \( | \) | \\ | [^"\(\)\\]+ )/x, ''))
        match_txt = $&
        case (state)
        when :raw
          case (match_txt)
          when '"'
            state = :quote
          when '('
            state = :comment
          when "\\"
            src_txt.sub!(/\A./, '') and dst_txt << $&
          else
            dst_txt << match_txt
          end
        when :quote
          case (match_txt)
          when '"'
            state = :raw
          when "\\"
            src_txt.sub!(/\A./, '') && dst_txt << $&
          else
            dst_txt << match_txt
          end
        when :comment
          case (match_txt)
          when ')'
            state = :raw
          when "\\"
            src_txt.sub!(/\A./, '')
          else
            # ignore comment text.
          end
        else
          raise "internal error: unknown state #{state}"
        end
      end

      dst_txt
    end
    module_function :unquote_phrase
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
