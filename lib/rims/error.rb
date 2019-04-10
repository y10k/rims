# -*- coding: utf-8 -*-

module RIMS
  class Error < StandardError
    def self.trace_error_chain(exception)
      return enum_for(:trace_error_chain, exception) unless block_given?

      while (exception)
        yield(exception)
        exception = exception.cause
      end

      nil
    end

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
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
