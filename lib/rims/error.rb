# -*- coding: utf-8 -*-

module RIMS
  class Error < StandardError
  end

  class ProtocolError < Error
  end

  class SyntaxError < ProtocolError
  end

  class MessageSetSyntaxError < SyntaxError
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
