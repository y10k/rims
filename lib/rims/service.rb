# -*- coding: utf-8 -*-

require 'riser'

module RIMS
  class Service
    class Configuration
      class << self
        def stringify_symbol(collection)
          case (collection)
          when Hash
            Hash[collection.map{|key, value| [ stringify_symbol(key), stringify_symbol(value) ] }]
          when Array
            collection.map{|i| stringify_symbol(i) }
          else
            case (value = collection)
            when Symbol
              value.to_s
            else
              value
            end
          end
        end
      end

      def accept_polling_timeout_seconds
        0.1
      end

      def process_num
        0                       # not yet supported multi-process server configuration.
      end

      def process_queue_size
        20
      end

      def process_queue_polling_timeout_seconds
        0.1
      end

      def process_send_io_polling_timeout_seconds
        0.1
      end

      def thread_num
        20
      end

      def thread_queue_size
        20
      end

      def thread_queue_polling_timeout_seconds
        0.1
      end
    end

    def initialize(config)
      @config = config
    end

    def setup(server)
      server.accept_polling_timeout_seconds          = @config.accept_polling_timeout_seconds
      server.process_num                             = @config.process_num
      server.process_queue_size                      = @config.process_queue_size
      server.process_queue_polling_timeout_seconds   = @config.process_queue_polling_timeout_seconds
      server.process_send_io_polling_timeout_seconds = @config.process_send_io_polling_timeout_seconds
      server.thread_num                              = @config.thread_num
      server.thread_queue_size                       = @config.thread_queue_size
      server.thread_queue_polling_timeout_seconds    = @config.thread_queue_polling_timeout_seconds
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
