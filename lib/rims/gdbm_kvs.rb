# -*- coding: utf-8 -*-

require 'gdbm'

module RIMS
  class GDBM_KeyValueStore < KeyValueStore
    def initialize(gdbm, path)
      @db = gdbm
      @path = path
    end

    def self.open(path, *optional)
      gdbm_path = path + '.gdbm'
      new(GDBM.new(gdbm_path, *optional), gdbm_path)
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

    def destroy
      unless (@db.closed?) then
        raise "failed to destroy gdbm that isn't closed: #{@path}"
      end
      File.delete(@path)
      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
