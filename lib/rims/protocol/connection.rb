# -*- coding: utf-8 -*-

require 'riser'

module RIMS
  module Protocol
    class ConnectionLimits
      def initialize(read_polling_interval_seconds, command_wait_timeout_seconds)
        @mutex = Thread::Mutex.new
        @read_polling_interval_seconds = read_polling_interval_seconds
        self.command_wait_timeout_seconds = command_wait_timeout_seconds
      end

      attr_reader :read_polling_interval_seconds

      def command_wait_timeout_seconds
        @mutex.synchronize{ @command_wait_timeout_seconds }
      end

      def command_wait_timeout_seconds=(value)
        @mutex.synchronize{ @command_wait_timeout_seconds = value }
      end
    end

    class ConnectionTimer
      def initialize(limits, read_io)
        @limits = limits
        @read_poll = Riser::ReadPoll.new(read_io)
        @command_wait_timeout = false
      end

      def command_wait
        if (@limits.command_wait_timeout_seconds == 0) then
          if (@read_poll.call(0) != nil) then
            return self
          else
            @command_wait_timeout = true
            return
          end
        end

        @read_poll.reset_timer
        until (@read_poll.call(@limits.read_polling_interval_seconds) != nil)
          if (@read_poll.interval_seconds >= @limits.command_wait_timeout_seconds) then
            @command_wait_timeout = true
            return
          end
        end

        self
      end

      def command_wait_timeout?
        @command_wait_timeout
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
