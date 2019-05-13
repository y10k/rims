# -*- coding: utf-8 -*-

require 'digest'

module RIMS
  class Checksum_KeyValueStore < KeyValueStore
    def initialize(kvs)
      @kvs = kvs
    end

    def md5_cksum_parse(key, s)
      if (s) then
        s =~ /\A md5 \s (\S+?) \n/x or raise "checksum format error at key: #{key}"
        md5_cksum = $1
        value = $'
        if (Digest::MD5.hexdigest(value) != md5_cksum) then
          raise "checksum error at key: #{key}"
        end

        value
      end
    end
    private :md5_cksum_parse

    def [](key)
      md5_cksum_parse(key, @kvs[key])
    end

    def []=(key, value)
      @kvs[key] = "md5 #{Digest::MD5.hexdigest(value)}\n#{value}"
      value
    end

    def delete(key)
      md5_cksum_parse(key, @kvs.delete(key))
    end

    def key?(key)
      @kvs.key? key
    end

    def each_key(&block)
      return enum_for(:each_key) unless block_given?
      @kvs.each_key(&block)
      self
    end

    def sync
      @kvs.sync
      self
    end

    def close
      @kvs.close
      self
    end

    def destroy
      @kvs.destroy
      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
