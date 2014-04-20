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

    def parse_content_type(content_type_txt)
      src_txt = content_type_txt.dup
      if (src_txt.sub!(%r"\A \s* (?<main_type>\S+?) \s* / \s* (?<sub_type>\S+?) \s* (?:;|\Z)"x, '')) then
        main_type = $~[:main_type]
        sub_type = $~[:sub_type]

        params = {}
        src_txt.scan(%r'(?<name>\S+?) \s* = \s* (?: (?<quoted_string>".*?") | (?<token>\S+?) ) \s* (?:;|\Z)'x) do
          name = $~[:name]
          if ($~[:quoted_string]) then
            quoted_value = $~[:quoted_string]
            value = unquote_phrase(quoted_value)
          else
            value = $~[:token]
          end
          params[name.downcase] = [ name, value ]
        end

        [ main_type, sub_type, params ]
      else
        [ 'application', 'octet-stream', {} ]
      end
    end
    module_function :parse_content_type

    def parse_multipart_body(boundary, body_txt)
      delim = '--' + boundary
      term = delim + '--'
      body_txt2, body_epilogue_txt = body_txt.split(term, 2)
      if (body_txt2) then
        body_preamble_txt, body_parts_txt = body_txt2.split(delim, 2)
        if (body_parts_txt) then
          part_list = body_parts_txt.split(delim, -1)
          for part_txt in part_list
            part_txt.lstrip!
            part_txt.chomp!("\n")
            part_txt.chomp!("\r")
          end
          return part_list
        end
      end

      []
    end
    module_function :parse_multipart_body

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

    def parse_mail_address_list(address_list_txt)
      addr_list = []
      src_txt = address_list_txt.dup

      while (true)
        if (src_txt.sub!(%r{
              \A
              \s*
              (?<display_name>\S.*?) \s* : (?<group_list>.*?) ;
              \s*
              ,?
            }x, ''))
        then
          display_name = $~[:display_name]
          group_list = $~[:group_list]
          addr_list << [ nil, nil, unquote_phrase(display_name), nil ]
          addr_list.concat(parse_mail_address_list(group_list))
          addr_list << [ nil, nil, nil, nil ]
        elsif (src_txt.sub!(%r{
                 \A
                 \s*
                 (?<local_part>[^<>@,\s]+) \s* @ \s* (?<domain>[^<>@,\s]+)
                 \s*
                 ,?
               }x, ''))
        then
          addr_list << [ nil, nil, $~[:local_part], $~[:domain] ]
        elsif (src_txt.sub!(%r{
                 \A
                 \s*
                 (?<display_name>\S.*?)
                 \s*
                 <
                   \s*
                   (?:
                     (?<route>@[^<>@,]* (?:, \s* @[^<>@,]*)*)
                     \s*
                     :
                   )?
                   \s*
                   (?<local_part>[^<>@,\s]+) \s* @ \s* (?<domain>[^<>@,\s]+)
                   \s*
                 >
                 \s*
                 ,?
               }x, ''))
        then
          display_name = $~[:display_name]
          route = $~[:route]
          local_part = $~[:local_part]
          domain = $~[:domain]
          addr_list << [ unquote_phrase(display_name), route, local_part, domain ]
        else
          break
        end
      end

      addr_list
    end
    module_function :parse_mail_address_list
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
