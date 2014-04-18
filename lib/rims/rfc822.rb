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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
