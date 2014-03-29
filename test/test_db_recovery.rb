# -*- coding: utf-8 -*-

require 'logger'
require 'pp' if $DEBUG
require 'rims'
require 'test/unit'

module RIMS::Test
  class DBRecoveryTest < Test::Unit::TestCase
    def setup
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL

      @kvs = {}
      @kvs_open = proc{|name| RIMS::Hash_KeyValueStore.new(@kvs[name] = {}) }

      @meta_db = RIMS::DB::Meta.new(@kvs_open.call('meta'))
      @msg_db = RIMS::DB::Message.new(@kvs_open.call('msg'))
      @mbox_db = {}

      @mail_store = RIMS::MailStore.new(@meta_db, @msg_db) {|mbox_id|
        @mbox_db[mbox_id] = RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }

      @inbox_id = @mail_store.add_mbox('INBOX')
      @meta_db.recovery_start
    end

    def teardown
      @meta_db.recovery_end
      pp @kvs if $DEBUG
    end

    def deep_copy(obj)
      Marshal.load(Marshal.dump(obj))
    end
    private :deep_copy

    def test_recovery_phase1_msg_scan_empty
      prev_kvs = deep_copy(@kvs)
      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase1_msg_scan_some_msgs
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase1_msg_scan_max_msg_id
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']['msg_id'] = '2'
      assert_equal(2, @meta_db.msg_id)

      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      assert_equal(3, @meta_db.msg_id)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase1_msg_scan_repair_msg_date
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')

      @kvs['meta'].delete('msg_id2date-1')
      assert_instance_of(Time, @meta_db.msg_date(0))
      assert_raise(RuntimeError) { @meta_db.msg_date(1) }
      assert_instance_of(Time, @meta_db.msg_date(2))

      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      assert_instance_of(Time, @meta_db.msg_date(0))
      assert_instance_of(Time, @meta_db.msg_date(1))
      assert_instance_of(Time, @meta_db.msg_date(2))
    end

    def test_recovery_phase1_msg_scan_msg_collect_lost_found_msg
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')

      @meta_db.del_msg_mbox_uid(1, @inbox_id, 2)
      @meta_db.clear_msg_mbox_uid_mapping(1)

      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      assert_equal([ 1 ].to_set, @meta_db.lost_found_msg_set)
    end

    def test_recovery_phase2_msg_scan_empty
      prev_kvs = deep_copy(@kvs)
      @meta_db.recovery_phase2_msg_scan(@msg_db, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase2_msg_scan_some_msgs
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase2_msg_scan(@msg_db, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase2_msg_scan_clear_lost_msg
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')

      @msg_db.del_msg(1)
      assert_equal(false, (@msg_db.msg_exist? 1))
      assert_equal(true, @meta_db.msg_flag(1, 'recent'))
      assert_equal(false, @meta_db.msg_mbox_uid_mapping(1).empty?)

      @meta_db.recovery_phase2_msg_scan(@msg_db, logger: @logger)
      assert_equal(false, (@msg_db.msg_exist? 1))
      assert_equal(false, @meta_db.msg_flag(1, 'recent'))
      assert_equal(true, @meta_db.msg_mbox_uid_mapping(1).empty?)
    end

    def test_recovery_phase2_msg_scan_collect_lost_found_mbox
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')

      mbox_uid_map = Marshal.load(@kvs['meta']['msg_id2mbox-1'])
      uid_set = mbox_uid_map.delete(@inbox_id)
      mbox_uid_map[@inbox_id + 1] = uid_set
      @kvs['meta']['msg_id2mbox-1'] = Marshal.dump(mbox_uid_map)

      @meta_db.recovery_phase2_msg_scan(@msg_db, logger: @logger)
      assert_equal([ @inbox_id + 1 ].to_set, @meta_db.lost_found_mbox_set)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
