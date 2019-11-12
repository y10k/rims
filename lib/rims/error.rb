# -*- coding: utf-8 -*-

module RIMS
  class Error < StandardError
    def initialize(*args, **kw_args)
      super(*args)
      @optional_data = kw_args.dup.freeze
    end

    attr_reader :optional_data

    def self.trace_error_chain(exception)
      return enum_for(:trace_error_chain, exception) unless block_given?

      while (exception)
        yield(exception)
        exception = exception.cause
      end

      nil
    end

    def self.optional_data(error) # :yields: error, data
      if (error.is_a? Error) then
        unless (error.optional_data.empty?) then
          yield(error, error.optional_data)
        end
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
