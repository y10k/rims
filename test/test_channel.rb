# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class ServerResponseChannelTest < Test::Unit::TestCase
    def setup
      @channel = RIMS::ServerResponseChannel.new
    end

    def test_pub_sub_fetch_message
      pub1, sub1 = @channel.make_pub_sub_pair(0)
      pub2, sub2 = @channel.make_pub_sub_pair(0)
      pub3, sub3 = @channel.make_pub_sub_pair(0)

      pub1.publish('msg1')
      assert_equal(false, sub1.message?)
      assert_equal(true, sub2.message?)
      assert_equal(true, sub3.message?)

      pub2.publish('msg2')
      assert_equal(true, sub1.message?)
      assert_equal(true, sub2.message?)
      assert_equal(true, sub3.message?)

      pub3.publish('msg3')
      assert_equal(true, sub1.message?)
      assert_equal(true, sub2.message?)
      assert_equal(true, sub3.message?)

      assert_equal(%w[ msg2 msg3 ], sub1.enum_for(:fetch).to_a)
      assert_equal(%w[ msg1 msg3 ], sub2.enum_for(:fetch).to_a)
      assert_equal(%w[ msg1 msg2 ], sub3.enum_for(:fetch).to_a)

      assert_equal(false, sub1.message?)
      assert_equal(false, sub2.message?)
      assert_equal(false, sub3.message?)
    end

    def test_pub_sub_fetch_no_message
      _, sub = @channel.make_pub_sub_pair(0)
      assert_equal(false, sub.message?)
      assert_equal([], sub.enum_for(:fetch).to_a)
    end

    def test_pub_sub_detach
      pub1, sub1 = @channel.make_pub_sub_pair(0)
      pub2, sub2 = @channel.make_pub_sub_pair(0)
      pub3, sub3 = @channel.make_pub_sub_pair(0)

      pub3.detach
      sub3.detach

      pub1.publish('msg1')
      pub2.publish('msg2')

      error = assert_raise(RuntimeError) { pub3.publish('msg3') }
      assert_match(/detached/, error.message)

      assert_equal(%w[ msg2 ], sub1.enum_for(:fetch).to_a)
      assert_equal(%w[ msg1 ], sub2.enum_for(:fetch).to_a)
      assert_equal([], sub3.enum_for(:fetch).to_a)
    end

    def test_pub_sub_different_mailboxes
      mbox0_pub1, mbox0_sub1 = @channel.make_pub_sub_pair(0)
      mbox0_pub2, mbox0_sub2 = @channel.make_pub_sub_pair(0)
      mbox1_pub1, mbox1_sub1 = @channel.make_pub_sub_pair(1)
      mbox1_pub2, mbox1_sub2 = @channel.make_pub_sub_pair(1)

      mbox0_pub1.publish('mbox0:msg1')
      mbox0_pub2.publish('mbox0:msg2')

      assert_equal(%w[ mbox0:msg2 ], mbox0_sub1.enum_for(:fetch).to_a)
      assert_equal(%w[ mbox0:msg1 ], mbox0_sub2.enum_for(:fetch).to_a)
      assert_equal([], mbox1_sub1.enum_for(:fetch).to_a)
      assert_equal([], mbox1_sub2.enum_for(:fetch).to_a)

      mbox1_pub1.publish('mbox1:msg1')
      mbox1_pub2.publish('mbox1:msg2')

      assert_equal([], mbox0_sub1.enum_for(:fetch).to_a)
      assert_equal([], mbox0_sub2.enum_for(:fetch).to_a)
      assert_equal(%w[ mbox1:msg2 ], mbox1_sub1.enum_for(:fetch).to_a)
      assert_equal(%w[ mbox1:msg1 ], mbox1_sub2.enum_for(:fetch).to_a)
    end

    def test_pub_sub_idle
      pub, _ = @channel.make_pub_sub_pair(0)
      _, sub = @channel.make_pub_sub_pair(0)

      pub.publish('msg1')
      sub.idle_interrupt
      assert_equal([ %w[ msg1 ] ], sub.enum_for(:idle_wait).to_a)

      pub.publish('msg2')
      pub.publish('msg3')
      sub.idle_interrupt
      assert_equal([ %w[ msg2 msg3 ] ], sub.enum_for(:idle_wait).to_a)
    end

    def test_pub_sub_idle_chunks
      pub, _ = @channel.make_pub_sub_pair(0)
      _, sub = @channel.make_pub_sub_pair(0)

      t = Thread.new{ sub.enum_for(:idle_wait).to_a }

      pub.publish('msg1')
      t.wakeup
      sleep(0.1)

      pub.publish('msg2')
      pub.publish('msg3')
      sub.idle_interrupt

      assert_equal([ %w[ msg1 ], %w[ msg2 msg3 ] ], t.value)
    end

    def test_pub_sub_idle_no_message
      _, sub = @channel.make_pub_sub_pair(0)
      sub.idle_interrupt
      assert_equal([], sub.enum_for(:idle_wait).to_a)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
