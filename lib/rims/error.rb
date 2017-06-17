# -*- coding: utf-8 -*-

module RIMS
  class Error < StandardError
    def self.suppress_2nd_error_at_resource_closing(logger: nil)
      if ($!) then
        begin
          yield
        rescue                  # not mask the first error
          logger.error($!) if logger
          nil
        end
      else
        yield
      end
    end
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
