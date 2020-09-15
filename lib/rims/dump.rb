# -*- coding: utf-8 -*-

module RIMS
  module Dump
    PLUG_IN = {}                # :nodoc:
  end

  class DumpReader
    def initialize(input)
      @input = input
    end

    def each                    # :yields: filename, content, valid
      raise NotImplementedError, 'abstract'
    end
  end

  class DumpWriter
    def initialize(output)
      @output = output
    end

    def add(filename, content)
      raise NotImplementedError, 'abstract'
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
