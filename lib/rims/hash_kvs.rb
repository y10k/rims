# -*- coding: utf-8 -*-

module RIMS
  class Hash_KeyValueStore < KeyValueStore
    def initialize(hash)
      @db = hash
    end

    def [](key)
      unless (key.is_a? String) then
        raise "not a string key: #{key}"
      end
      @db[key.b]
    end

    def []=(key, value)
      unless (key.is_a? String) then
        raise "not a string key: #{key}"
      end
      unless (value.is_a? String) then
        raise "not a string value: #{value}"
      end
      @db[key.b] = value.b
    end

    def delete(key)
      unless (key.is_a? String) then
        raise "not a string key: #{key}"
      end
      @db.delete(key.b)
    end

    def key?(key)
      unless (key.is_a? String) then
        raise "not a string key: #{key}"
      end
      @db.key? key.b
    end

    def each_key
      return enum_for(:each_key) unless block_given?
      @db.each_key do |key|
        yield(key)
      end
      self
    end

    def sync
      self
    end

    def close
      @db = nil
      self
    end

    def destroy
      self
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
