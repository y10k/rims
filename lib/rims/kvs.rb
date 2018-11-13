# -*- coding: utf-8 -*-

module RIMS
  class KeyValueStore
    def [](key)
      raise NotImplementedError, 'abstract'
    end

    def []=(key, value)
      raise NotImplementedError, 'abstract'
    end

    def delete(key)
      raise NotImplementedError, 'abstract'
    end

    def key?(key)
      raise NotImplementedError, 'abstract'
    end

    def each_key
      raise NotImplementedError, 'abstract'
    end

    def each_value
      return enum_for(:each_value) unless block_given?
      each_key do |key|
        yield(self[key])
      end
    end

    def each_pair
      return enum_for(:each_pair) unless block_given?
      each_key do |key|
        yield(key, self[key])
      end
    end

    def sync
      raise NotImplementedError, 'abstract'
    end

    def close
      raise NotImplementedError, 'abstract'
    end

    def destroy
      raise NotImplementedError, 'abstract'
    end

    def self.exist?(path)
      raise NotImplementedError, 'not implemented.'
    end

    def self.open_with_conf(config)
      raise NotImplementedError, 'not implemented.'
    end

    class FactoryBuilder
      PLUG_IN = {}                # :nodoc:

      class << self
        def add_plug_in(name, klass)
          PLUG_IN[name] = klass
          self
        end

        def get_plug_in(name)
          PLUG_IN[name] or raise KeyError, "not found a plug-in: #{name}"
        end
      end

      def initialize
        @open = nil
        @factory = proc{|name|
          @open.call(name)
        }
      end

      attr_reader :factory

      def open(&block)      # :yields: name
        @open = block
        self
      end

      def use(middleware, *args, &block)
        prev_factory = @factory
        @factory = proc{|name|
          middleware.new(prev_factory.call(name), *args, &block)
        }
        self
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
