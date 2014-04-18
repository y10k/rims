# -*- coding: utf-8 -*-

module RIMS
  module RFC822
    def split_message(msg_txt)
      header_txt, body_txt = msg_txt.lstrip.split(/\r?\n\r?\n/, 2)
      header_txt << $& if $&
      [ header_txt, body_txt ]
    end
    module_function :split_message
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
