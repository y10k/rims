# -*- coding: utf-8 -*-

module RIMS
  class ObjectPool
    class ObjectHolder
      def initialize(object_pool, object_key)
        @object_pool = object_pool
        @object_key = object_key
      end

      attr_reader :object_key

      def object_destroy
      end

      # optional block is called when a mail store is closed.
      def return_pool(**name_args, &block) # yields:
        @object_pool.put(self, **name_args, &block)
        nil
      end
    end

    class ReferenceCount
      def initialize(count, object_holder)
        @count = count
        @object_holder = object_holder
      end

      attr_accessor :count
      attr_reader :object_holder

      def object_destroy
        @object_holder.object_destroy
      end
    end

    def initialize(&object_factory)      # yields: object_pool, object_key, object_lock
      @object_factory = object_factory
      @pool_map = {}
      @pool_lock = Mutex.new
      @object_lock_map = Hash.new{|hash, key| hash[key] = ReadWriteLock.new }
    end

    def empty?
      @pool_map.empty?
    end

    # optional block is called when a new object is added to an object pool.
    def get(object_key, timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS) # yields:
      object_lock = @pool_lock.synchronize{ @object_lock_map[object_key] }
      object_lock.write_synchronize(timeout_seconds) {
        if (@pool_lock.synchronize{ @pool_map.key? object_key }) then
          ref_count = @pool_lock.synchronize{ @pool_map[object_key] }
        else
          yield if block_given?
          object_holder = @object_factory.call(self, object_key, object_lock)
          ref_count = ReferenceCount.new(0, object_holder)
          @pool_lock.synchronize{ @pool_map[object_key] = ref_count }
        end
        ref_count.count >= 0 or raise 'internal error'
        ref_count.count += 1
        ref_count.object_holder
      }
    end

    # optional block is called when an object is deleted from an object pool.
    def put(object_holder, timeout_seconds: ReadWriteLock::DEFAULT_TIMEOUT_SECONDS) # yields:
      object_lock = @pool_lock.synchronize{ @object_lock_map[object_holder.object_key] }
      object_lock.write_synchronize(timeout_seconds) {
        ref_count = @pool_lock.synchronize{ @pool_map[object_holder.object_key] } or raise 'internal error'
        ref_count.object_holder.equal? object_holder or raise 'internal error'
        ref_count.count > 0 or raise 'internal error'
        ref_count.count -= 1
        if (ref_count.count == 0) then
          @pool_lock.synchronize{ @pool_map.delete(object_holder.object_key) }
          ref_count.object_destroy
          yield if block_given?
        end
      }
      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
