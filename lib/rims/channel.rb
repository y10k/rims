# -*- coding: utf-8 -*-

require 'forwardable'

module RIMS
  class ServerResponseChannelError < Error
  end

  class ServerResponseChannelAttachError < ServerResponseChannelError
  end

  class ServerResponseChannelDetachError < ServerResponseChannelError
  end

  class ServerResponseChannelPublishError < ServerResponseChannelError
  end

  class ServerResponseChannel
    def initialize
      @mutex = Thread::Mutex.new
      @channel = {}
    end

    def make_pub_sub_pair(mbox_id)
      pub = ServerResponsePublisher.new(self, mbox_id)
      sub = ServerResponseSubscriber.new(self, pub)
      return pub, attach(sub)
    end

    def attach(sub)
      @mutex.synchronize{
        @channel[sub.mbox_id] ||= {}
        if (@channel[sub.mbox_id].key? sub.pub_sub_pair_key) then
          raise ServerResponseChannelAttachError.new('conflicted subscriber.', channel: self, subscriber: sub)
        end
        @channel[sub.mbox_id][sub.pub_sub_pair_key] = sub
      }

      sub
    end
    private :attach

    # do not call this method directly, call the following method
    # instead.
    #   - ServerResponsePublisher#detach
    #   - ServerResponseSubscriber#detach
    def detach(sub)
      @mutex.synchronize{
        unless ((@channel.key? sub.mbox_id) && (@channel[sub.mbox_id].key? sub.pub_sub_pair_key)) then
          raise ServerResponseChannelDetachError.new('unregistered pub-sub pair.', channel: self, subscriber: sub)
        end

        unless (@channel[sub.mbox_id][sub.pub_sub_pair_key] == sub) then
          raise ServerResponseChannelDetachError.new('internal error: mismatched subscriber.', channel: self, subscribe: sub)
        end

        @channel[sub.mbox_id].delete(sub.pub_sub_pair_key)
        if (@channel[sub.mbox_id].empty?) then
          @channel.delete(sub.mbox_id)
        end
      }

      nil
    end

    # do not call this method directly, call the following method
    # instead.
    #   - ServerResponsePublisher#publish
    def publish(mbox_id, pub_sub_pair_key, response_message)
      @mutex.synchronize{
        @channel[mbox_id].each_value do |sub|
          if (sub.pub_sub_pair_key != pub_sub_pair_key) then
            sub.publish(response_message)
          end
        end
      }

      nil
    end
  end

  class ServerResponsePublisher
    # do not call this method directly, call the following method
    # instead.
    #   - ServerResponseChannel#make_pub_sub_pair
    def initialize(channel, mbox_id)
      @channel = channel
      @mbox_id = mbox_id
    end

    attr_reader :mbox_id

    def pub_sub_pair_key
      object_id
    end

    def publish(response_message)
      unless (@channel) then
        raise ServerResponseChannelPublishError.new('detached publisher.',
                                                    publisher: self,
                                                    pub_sub_pair_key: pub_sub_pair_key,
                                                    message: response_message)
      end
      @channel.publish(@mbox_id, pub_sub_pair_key, response_message)
      nil
    end

    def detach
      @channel = nil
      nil
    end
  end

  class ServerResponseSubscriber
    # do not call this method directly, call the following method
    # instead.
    #   - ServerResponseChannel#make_pub_sub_pair
    def initialize(channel, pub)
      @channel = channel
      @pub = pub
      @queue = Thread::Queue.new
    end

    extend Forwardable
    def_delegators :@pub, :mbox_id, :pub_sub_pair_key

    # do not call this method directly, call the following method
    # instead.
    #   - ServerResponsePublisher#publish
    def publish(response_message)
      @queue.push(response_message)
      nil
    end

    def detach
      @channel.detach(self)
      nil
    end

    def message?
      ! @queue.empty?
    end

    def fetch
      while (message?)
        response_message = @queue.pop(true)
        yield(response_message)
      end

      nil
    end

    def idle_wait
      catch(:idle_interrupt) {
        while (response_message = @queue.pop(false))
          message_list = [ response_message ]
          fetch{|next_response_message|
            if (next_response_message) then
              message_list << next_response_message
            else
              yield(message_list)
              throw(:idle_interrupt)
            end
          }
          yield(message_list)
        end
      }

      nil
    end

    def idle_interrupt
      @queue.push(nil)
      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
