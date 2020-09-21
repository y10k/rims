# -*- coding: utf-8 -*-

module RIMS
  module Dump
    PLUG_IN = {}                # :nodoc:

    class << self
      def add_plug_in(name, reader_class, writer_class)
        PLUG_IN[name] = {
          ReaderClass: reader_class,
          WriterClass: writer_class
        }
        self
      end

      def get_reader_plug_in(name)
        PLUG_IN.dig(name, :ReaderClass) or raise KeyError, "not found a dump plug-in: #{name}"
      end

      def get_writer_plug_in(name)
        PLUG_IN.dig(name, :WriterClass) or raise KeyError, "not found a dump plug-in: #{name}"
      end

      def plug_in_names
        PLUG_IN.keys
      end
    end
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
