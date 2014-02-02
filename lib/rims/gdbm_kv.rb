# -*- coding: utf-8 -*-

require 'gdbm'
require 'rims/kv'

module RIMS
  class GDBM_KeyValueStore < KeyValueStore
    def initialize(gdbm)
      @db = gdbm
    end

    def self.open(path)
      new(GDBM.new(path + '.gdbm'))
    end

    def [](key)
      @db[key]
    end

    def []=(key, value)
      @db[key] = value
    end

    def delete(key)
      @db.delete(key)
    end

    def key?(key)
      @db.key? key
    end

    def each_key
      return enum_for(:each_key) unless block_given?
      @db.each_key do |key|
        yield(key)
      end
      self
    end

    def sync
      @db.sync
      self
    end

    def close
      @db.close
      self
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
