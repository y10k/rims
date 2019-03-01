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

      @channel.attach(pub1, sub1)
      @channel.attach(pub2, sub2)
      @channel.attach(pub3, sub3)

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
      pub, sub = @channel.make_pub_sub_pair(0)
      @channel.attach(pub, sub)
      assert_equal(false, sub.message?)
      assert_equal([], sub.enum_for(:fetch).to_a)
    end

    def test_pub_sub_detach
      pub1, sub1 = @channel.make_pub_sub_pair(0)
      pub2, sub2 = @channel.make_pub_sub_pair(0)
      pub3, sub3 = @channel.make_pub_sub_pair(0)

      @channel.attach(pub1, sub1)
      @channel.attach(pub2, sub2)
      @channel.attach(pub3, sub3)

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

      @channel.attach(mbox0_pub1, mbox0_sub1)
      @channel.attach(mbox0_pub2, mbox0_sub2)
      @channel.attach(mbox1_pub1, mbox1_sub1)
      @channel.attach(mbox1_pub2, mbox1_sub2)

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
      pub1, sub1 = @channel.make_pub_sub_pair(0)
      pub2, sub2 = @channel.make_pub_sub_pair(0)

      @channel.attach(pub1, sub1)
      @channel.attach(pub2, sub2)

      pub1.publish('msg1')
      sub2.idle_interrupt
      assert_equal([ %w[ msg1 ] ], sub2.enum_for(:idle_wait).to_a)

      pub1.publish('msg2')
      pub1.publish('msg3')
      sub2.idle_interrupt
      assert_equal([ %w[ msg2 msg3 ] ], sub2.enum_for(:idle_wait).to_a)
    end

    def test_pub_sub_idle_chunks
      pub1, sub1 = @channel.make_pub_sub_pair(0)
      pub2, sub2 = @channel.make_pub_sub_pair(0)

      @channel.attach(pub1, sub1)
      @channel.attach(pub2, sub2)

      t = Thread.new{ sub2.enum_for(:idle_wait).to_a }

      pub1.publish('msg1')
      t.wakeup
      sleep(0.1)

      pub1.publish('msg2')
      pub1.publish('msg3')
      sub2.idle_interrupt

      assert_equal([ %w[ msg1 ], %w[ msg2 msg3 ] ], t.value)
    end

    def test_pub_sub_idle_no_message
      pub, sub = @channel.make_pub_sub_pair(0)
      @channel.attach(pub, sub)

      sub.idle_interrupt
      assert_equal([], sub.enum_for(:idle_wait).to_a)
    end

    def test_attach_mismatched_pub_sub_pair_error
      pub1, _ = @channel.make_pub_sub_pair(0)
      _, sub2 = @channel.make_pub_sub_pair(0)
      error = assert_raise(ArgumentError) { @channel.attach(pub1, sub2) }
      assert_match(/mismatched/, error.message)
    end

    def test_attach_conflicted_subscriber_error
      pub, sub = @channel.make_pub_sub_pair(0)
      @channel.attach(pub, sub)
      error = assert_raise(ArgumentError) { @channel.attach(pub, sub) }
      assert_match(/conflicted/, error.message)
    end

    def test_detach_mismatch_pub_sub_pair_error
      pub1, sub1 = @channel.make_pub_sub_pair(0)
      _, sub2 = @channel.make_pub_sub_pair(0)
      @channel.attach(pub1, sub1)
      error = assert_raise(ArgumentError) { @channel.detach(pub1, sub2) }
      assert_match(/mismatched/, error.message)
    end

    def test_detach_unregistered_pub_sub_pair_error
      pub, sub = @channel.make_pub_sub_pair(0)
      assert_raise(ArgumentError) { @channel.detach(pub, sub) }
    end

    def test_detach_mismatched_subscriber_error
      pub, sub = @channel.make_pub_sub_pair(0)
      @channel.attach(pub, sub)
      dummy_sub = pub
      error = assert_raise(RuntimeError) { @channel.detach(pub, dummy_sub) }
      assert_match(/mismatched/, error.message)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
