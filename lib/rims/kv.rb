# -*- coding: utf-8 -*-

module RIMS
  class KeyValueStore
    def [](key)
      fetch(key)
    end

    def []=(key, value)
      store(key, value)
    end

    def fetch(key)
      raise NotImplementedError, 'abstract'
    end

    def store(key, value)
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
        yield(fetch(key))
      end
    end

    def each_pair
      return enum_for(:each_pair) unless block_given?
      each_key do |key|
        yield(key, fetch(key))
      end
    end

    def sync
      raise NotImplementedError, 'abstract'
    end

    def close
      raise NotImplementedError, 'abstract'
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
