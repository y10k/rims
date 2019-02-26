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
      def return_pool(&block) # yields:
        @object_pool.put(self, &block)
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
      @mutex = Mutex.new
      @object_factory = object_factory
      @pool = {}
    end

    def empty?
      @mutex.synchronize{ @pool.empty? }
    end

    # optional block is called when a new object is added to an object pool.
    def get(object_key)         # yields:
      @mutex.synchronize{
        if (@pool.key? object_key) then
          ref_count = @pool[object_key]
        else
          yield if block_given?
          object_holder = @object_factory.call(self, object_key)
          ref_count = ReferenceCount.new(0, object_holder)
          @pool[object_key] = ref_count
        end
        ref_count.count >= 0 or raise 'internal error'
        ref_count.count += 1
        ref_count.object_holder
      }
    end

    # optional block is called when an object is deleted from an object pool.
    def put(object_holder) # yields:
      @mutex.synchronize{
        ref_count = @pool[object_holder.object_key] or raise 'internal error'
        ref_count.object_holder.equal? object_holder or raise 'internal error'
        ref_count.count > 0 or raise 'internal error'
        ref_count.count -= 1
        if (ref_count.count == 0) then
          @pool.delete(object_holder.object_key)
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
