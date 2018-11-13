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

    def test_recovery_phase3_msg_scan_empty
      prev_kvs = deep_copy(@kvs)
      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase3_msg_scan_some_mboxes
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase3_msg_scan_repair_uidvalidity
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']['uidvalidity'] = '3'
      assert_equal(3, @meta_db.uidvalidity)

      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      assert_equal(4, @meta_db.uidvalidity)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase3_msg_scan_repair_lost_mbox_name2id
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta'].delete('mbox_name2id-foo')
      assert_equal(1, @meta_db.mbox_id('INBOX'))
      assert_nil(@meta_db.mbox_id('foo'))
      assert_equal(3, @meta_db.mbox_id('bar'))

      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      assert_equal(1, @meta_db.mbox_id('INBOX'))
      assert_equal(2, @meta_db.mbox_id('foo'))
      assert_equal(3, @meta_db.mbox_id('bar'))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase3_msg_scan_reapir_dup_mbox_name2id
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']['mbox_name2id-foo'] = '1'
      assert_equal(1, @meta_db.mbox_id('INBOX'))
      assert_equal(1, @meta_db.mbox_id('foo'))
      assert_equal(3, @meta_db.mbox_id('bar'))

      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      assert_equal(1, @meta_db.mbox_id('INBOX'))
      assert_equal(2, @meta_db.mbox_id('foo'))
      assert_equal(3, @meta_db.mbox_id('bar'))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase3_msg_scan_repair_lost_mbox_id_name_pair
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')

      @kvs['meta'].delete('mbox_id2name-2')
      assert_nil(@meta_db.mbox_name(2))
      assert_equal(2, @meta_db.mbox_id('foo'))

      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      assert_equal('MAILBOX#2', @meta_db.mbox_name(2))
      assert_equal(2, @meta_db.mbox_id('MAILBOX#2'))
      assert_equal(2, @meta_db.mbox_id('foo')) # recovered at phase 4.
    end

    def test_recovery_phase3_msg_scan_repair_lost_mbox_id_name_pair2
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('MAILBOX#2')
      @mail_store.add_mbox('MAILBOX#2 (1)')
      @mail_store.add_mbox('MAILBOX#2 (2)')

      @kvs['meta'].delete('mbox_id2name-2')
      assert_nil(@meta_db.mbox_name(2))
      assert_equal(2, @meta_db.mbox_id('foo'))

      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      assert_equal('MAILBOX#2 (3)', @meta_db.mbox_name(2))
      assert_equal(2, @meta_db.mbox_id('MAILBOX#2 (3)'))
      assert_equal(2, @meta_db.mbox_id('foo')) # recovered at phase 4.
    end

    def test_recovery_phase4_mbox_scan_empty
      prev_kvs = deep_copy(@kvs)
      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase4_mbox_scan_some_mboxes
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase4_mbox_scan_excess_key_mbox_id
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']['mbox_id2name-4'] = 'foo'
      assert_equal('INBOX', @meta_db.mbox_name(1))
      assert_equal('foo', @meta_db.mbox_name(2))
      assert_equal('bar', @meta_db.mbox_name(3))
      assert_equal('foo', @meta_db.mbox_name(4))

      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      assert_equal('INBOX', @meta_db.mbox_name(1))
      assert_equal('foo', @meta_db.mbox_name(2))
      assert_equal('bar', @meta_db.mbox_name(3))
      assert_nil(@meta_db.mbox_name(4))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase4_mbox_scan_reapir_dup_mbox_name
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']['mbox_name2id-x'] = '2'
      assert_equal(1, @meta_db.mbox_id('INBOX'))
      assert_equal(2, @meta_db.mbox_id('foo'))
      assert_equal(3, @meta_db.mbox_id('bar'))
      assert_equal(2, @meta_db.mbox_id('x'))

      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      assert_equal(1, @meta_db.mbox_id('INBOX'))
      assert_equal(2, @meta_db.mbox_id('foo'))
      assert_equal(3, @meta_db.mbox_id('bar'))
      assert_nil(@meta_db.mbox_id('x'))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase4_mbox_scan_repair_orphaned_mbox_id_mbox_name
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']['mbox_name2id-x'] = '4'
      @kvs['meta']['mbox_id2name-4'] = 'x'
      assert_equal(4, @meta_db.mbox_id('x'))
      assert_equal('x', @meta_db.mbox_name(4))

      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      assert_nil(@meta_db.mbox_id('x'))
      assert_nil(@meta_db.mbox_name(4))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase5_mbox_repair_make_lost_found_mbox
      @meta_db.recovery_phase5_mbox_repair(logger: @logger) {|mbox_id|
        @mbox_db[mbox_id] = RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
      assert_equal(3, @meta_db.uidvalidity)
      assert_equal([ 1, 2 ], @meta_db.each_mbox_id.to_a)
      assert_equal('INBOX', @meta_db.mbox_name(1))
      assert_equal(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME, @meta_db.mbox_name(2))
      assert_instance_of(RIMS::DB::Mailbox, @mbox_db[2])
    end

    def test_recovery_phase5_mbox_repair_lost_found_mbox_exists
      @meta_db.add_mbox(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME)
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase5_mbox_repair(logger: @logger) {|mbox_id|
        @mbox_db[mbox_id] = RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase5_mbox_repair_make_losted_mbox
      @meta_db.lost_found_mbox_set << 2
      @meta_db.lost_found_mbox_set << 5

      @meta_db.recovery_phase5_mbox_repair(logger: @logger) {|mbox_id|
        @mbox_db[mbox_id] = RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
      assert_equal(7, @meta_db.uidvalidity)
      assert_equal([ 1, 2, 5, 6 ], @meta_db.each_mbox_id.to_a)
      assert_equal('INBOX', @meta_db.mbox_name(1))
      assert_equal('MAILBOX#2', @meta_db.mbox_name(2))
      assert_equal('MAILBOX#5', @meta_db.mbox_name(5))
      assert_equal(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME, @meta_db.mbox_name(6))
      assert_instance_of(RIMS::DB::Mailbox, @mbox_db[2])
      assert_instance_of(RIMS::DB::Mailbox, @mbox_db[5])
      assert_instance_of(RIMS::DB::Mailbox, @mbox_db[6])
    end

    def test_recovery_phase6_msg_scan_empty
      prev_kvs = deep_copy(@kvs)
      @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase6_msg_scan_some_msgs
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase6_msg_scan_repair_lost_found_msg
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @kvs['mbox_1'].delete('2')
      assert_equal({ @inbox_id => [ 1 ].to_set }, @meta_db.msg_mbox_uid_mapping(0))
      assert_equal({ @inbox_id => [ 2 ].to_set }, @meta_db.msg_mbox_uid_mapping(1))
      assert_equal({ @inbox_id => [ 3 ].to_set }, @meta_db.msg_mbox_uid_mapping(2))
      assert_equal(0, @mbox_db[@inbox_id].msg_id(1))
      assert_nil(@mbox_db[@inbox_id].msg_id(2))
      assert_equal(2, @mbox_db[@inbox_id].msg_id(3))

      @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: @logger)
      assert_equal({ @inbox_id => [ 1 ].to_set }, @meta_db.msg_mbox_uid_mapping(0))
      assert_equal({ @inbox_id => [ 2 ].to_set }, @meta_db.msg_mbox_uid_mapping(1))
      assert_equal({ @inbox_id => [ 3 ].to_set }, @meta_db.msg_mbox_uid_mapping(2))
      assert_equal(0, @mbox_db[@inbox_id].msg_id(1))
      assert_equal(1, @mbox_db[@inbox_id].msg_id(2))
      assert_equal(2, @mbox_db[@inbox_id].msg_id(3))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase6_msg_scan_collect_lost_found_msg
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')

      @kvs['meta']['msg_id2mbox-2'] = Marshal.dump({ @inbox_id => [ 1 ].to_set })
      @kvs['mbox_1'].delete('3')
      assert_equal({ @inbox_id => [ 1 ].to_set }, @meta_db.msg_mbox_uid_mapping(0))
      assert_equal({ @inbox_id => [ 2 ].to_set }, @meta_db.msg_mbox_uid_mapping(1))
      assert_equal({ @inbox_id => [ 1 ].to_set }, @meta_db.msg_mbox_uid_mapping(2))
      assert_equal(0, @mbox_db[@inbox_id].msg_id(1))
      assert_equal(1, @mbox_db[@inbox_id].msg_id(2))
      assert_nil(@mbox_db[@inbox_id].msg_id(3))

      @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: @logger)
      assert_equal({ @inbox_id => [ 1 ].to_set }, @meta_db.msg_mbox_uid_mapping(0))
      assert_equal({ @inbox_id => [ 2 ].to_set }, @meta_db.msg_mbox_uid_mapping(1))
      assert_equal({}, @meta_db.msg_mbox_uid_mapping(2))
      assert_equal(0, @mbox_db[@inbox_id].msg_id(1))
      assert_equal(1, @mbox_db[@inbox_id].msg_id(2))
      assert_nil(@mbox_db[@inbox_id].msg_id(3))
      assert_equal([ 2 ].to_set, @meta_db.lost_found_msg_set)
    end

    def test_recovery_phase7_mbox_msg_scan_empty
      prev_kvs = deep_copy(@kvs)
      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase7_mbox_msg_scan_some_msgs
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase7_mbox_msg_scan_repiar_mbox_uid
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']["mbox_id2uid-#{@inbox_id}"] = '3'
      assert_equal(3, @meta_db.mbox_uid(@inbox_id))

      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      assert_equal(4, @meta_db.mbox_uid(@inbox_id))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase7_mbox_msg_scan_repair_mbox_msg
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @mbox_db[@inbox_id].add_msg(4, 0)
      assert_equal(0, @mbox_db[@inbox_id].msg_id(1))
      assert_equal(1, @mbox_db[@inbox_id].msg_id(2))
      assert_equal(2, @mbox_db[@inbox_id].msg_id(3))
      assert_equal(0, @mbox_db[@inbox_id].msg_id(4))

      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      assert_equal(0, @mbox_db[@inbox_id].msg_id(1))
      assert_equal(1, @mbox_db[@inbox_id].msg_id(2))
      assert_equal(2, @mbox_db[@inbox_id].msg_id(3))
      assert_nil(@mbox_db[@inbox_id].msg_id(4))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase7_mbox_msg_scan_repair_msg_num
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']["mbox_id2msgnum-#{@inbox_id}"] = '0'
      assert_equal(0, @meta_db.mbox_msg_num(@inbox_id))

      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      assert_equal(3, @meta_db.mbox_msg_num(@inbox_id))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase7_mbox_msg_scan_repair_flag_num
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      @mail_store.set_msg_flag(@inbox_id, 1, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 2, 'seen', true)
      @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      prev_kvs = deep_copy(@kvs)

      @kvs['meta']["mbox_id2flagnum-#{@inbox_id}-recent"] = '0'
      @kvs['meta']["mbox_id2flagnum-#{@inbox_id}-seen"] = '0'
      @kvs['meta']["mbox_id2flagnum-#{@inbox_id}-deleted"] = '0'
      assert_equal(0, @meta_db.mbox_flag_num(@inbox_id, 'recent'))
      assert_equal(0, @meta_db.mbox_flag_num(@inbox_id, 'seen'))
      assert_equal(0, @meta_db.mbox_flag_num(@inbox_id, 'deleted'))

      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      assert_equal(3, @meta_db.mbox_flag_num(@inbox_id, 'recent'))
      assert_equal(2, @meta_db.mbox_flag_num(@inbox_id, 'seen'))
      assert_equal(1, @meta_db.mbox_flag_num(@inbox_id, 'deleted'))
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase8_lost_found_empty
      _lost_found_id = @mail_store.add_mbox(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME)
      @mail_store.expunge_mbox(_lost_found_id) # explicit open a mailbox database
      prev_kvs = deep_copy(@kvs)
      @meta_db.recovery_phase8_lost_found(@mbox_db, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_phase8_lost_found_some_msgs
      _lost_found_id = @mail_store.add_mbox(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME)
      @mail_store.expunge_mbox(_lost_found_id) # explicit open a mailbox database
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase8_lost_found(@mbox_db, logger: @logger)
      assert_equal(prev_kvs, @kvs)
    end


    def test_recovery_phase8_lost_found_repair_msgs
      lost_found_id = @mail_store.add_mbox(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME)
      @mail_store.expunge_mbox(lost_found_id) # explicit open a mailbox database
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')

      @meta_db.lost_found_msg_set << 0 << 1
      assert_nil(@meta_db.msg_mbox_uid_mapping(0)[lost_found_id])
      assert_nil(@meta_db.msg_mbox_uid_mapping(1)[lost_found_id])
      assert_nil(@meta_db.msg_mbox_uid_mapping(2)[lost_found_id])
      assert_equal([], @mbox_db[lost_found_id].each_msg_uid.to_a)

      @meta_db.recovery_phase8_lost_found(@mbox_db, logger: @logger)
      assert_equal([ 1 ].to_set, @meta_db.msg_mbox_uid_mapping(0)[lost_found_id])
      assert_equal([ 2 ].to_set, @meta_db.msg_mbox_uid_mapping(1)[lost_found_id])
      assert_nil(@meta_db.msg_mbox_uid_mapping(2)[lost_found_id])
      assert_equal([ 1, 2 ], @mbox_db[lost_found_id].each_msg_uid.to_a)
      assert_equal(0, @mbox_db[lost_found_id].msg_id(1))
      assert_equal(1, @mbox_db[lost_found_id].msg_id(2))
    end

    def test_recovery_scenario_empty
      @mail_store.add_mbox(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME)
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      @meta_db.recovery_phase2_msg_scan(@msg_db, logger: @logger)
      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      @meta_db.recovery_phase5_mbox_repair(logger: @logger) {|mbox_id|
        @mbox_db[mbox_id] = RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
      @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: @logger)
      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      @meta_db.recovery_phase8_lost_found(@mbox_db, logger: @logger)

      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_scenario_some_msgs_mboxes
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      @mail_store.add_mbox(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME)
      prev_kvs = deep_copy(@kvs)

      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      @meta_db.recovery_phase2_msg_scan(@msg_db, logger: @logger)
      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      @meta_db.recovery_phase5_mbox_repair(logger: @logger) {|mbox_id|
        @mbox_db[mbox_id] = RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
      @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: @logger)
      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      @meta_db.recovery_phase8_lost_found(@mbox_db, logger: @logger)

      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_scenario_repair_data
      @mail_store.add_msg(@inbox_id, 'foo'); @mail_store.set_msg_flag(@inbox_id, 1, 'deleted', true)
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')
      @mail_store.add_mbox(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME)
      prev_kvs = deep_copy(@kvs)

      # recovery phase 1
      @kvs['meta']['msg_id'] = '0'
      assert_equal(0, @meta_db.msg_id)

      # recovery phase 2
      @kvs['meta']['msg_id2mbox-3'] = Marshal.dump({ 10 => [ 100 ].to_set })
      @kvs['meta']['msg_id2date-3'] = Marshal.dump(Time.now)
      assert_equal({ 10 => [ 100 ].to_set }, @meta_db.msg_mbox_uid_mapping(3))
      assert_instance_of(Time, @meta_db.msg_date(3))

      # recovery phase 3
      @kvs['meta']['uidvalidity'] = '1'
      @kvs['meta']['mbox_name2id-foo'] = @inbox_id.to_s
      assert_equal(1, @meta_db.uidvalidity)
      assert_equal(@inbox_id, @meta_db.mbox_id('foo'))

      # recovery phase 4
      @kvs['meta']['mbox_name2id-NoBox'] = '1'
      assert_equal(1, @meta_db.mbox_id('INBOX'))
      assert_equal(1, @meta_db.mbox_id('NoBox'))

      # recovery phase 6
      @kvs['mbox_1'].delete('2')
      @kvs['mbox_1'].delete('3')
      assert_equal([ 1 ], @mbox_db[@inbox_id].each_msg_uid.to_a)
      assert_equal(0, @mbox_db[@inbox_id].msg_id(1))

      # recovery phase 7
      @kvs['meta']['mbox_id2msgnum-1'] = '0'
      @kvs['meta']['mbox_id2flagnum-1-recent'] = '0'
      @kvs['meta']['mbox_id2flagnum-1-deleted'] = '0'
      assert_equal(0, @meta_db.mbox_msg_num(@inbox_id))
      assert_equal(0, @meta_db.mbox_flag_num(@inbox_id, 'recent'))
      assert_equal(0, @meta_db.mbox_flag_num(@inbox_id, 'deleted'))

      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      @meta_db.recovery_phase2_msg_scan(@msg_db, logger: @logger)
      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      @meta_db.recovery_phase5_mbox_repair(logger: @logger) {|mbox_id|
        @mbox_db[mbox_id] = RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
      @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: @logger)
      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      @meta_db.recovery_phase8_lost_found(@mbox_db, logger: @logger)

      # recovery phase 1
      assert_equal(3, @meta_db.msg_id)

      # recovery phase 2
      assert_equal({}, @meta_db.msg_mbox_uid_mapping(3))
      assert_raise(RuntimeError) { @meta_db.msg_date(3) }

      # recovery phase 3
      assert_equal(5, @meta_db.uidvalidity)
      assert_equal(2, @meta_db.mbox_id('foo'))

      # recovery phase 4
      assert_equal(1, @meta_db.mbox_id('INBOX'))
      assert_nil(@meta_db.mbox_id('NoBox'))

      # recovery phase 6
      assert_equal([ 1, 2, 3 ], @mbox_db[@inbox_id].each_msg_uid.to_a)
      assert_equal(0, @mbox_db[@inbox_id].msg_id(1))
      assert_equal(1, @mbox_db[@inbox_id].msg_id(2))
      assert_equal(2, @mbox_db[@inbox_id].msg_id(3))

      # recovery phase 7
      assert_equal(3, @meta_db.mbox_msg_num(@inbox_id))
      assert_equal(3, @meta_db.mbox_flag_num(@inbox_id, 'recent'))
      assert_equal(1, @meta_db.mbox_flag_num(@inbox_id, 'deleted'))

      assert_equal(prev_kvs, @kvs)
    end

    def test_recovery_scenario_lost_found
      @mail_store.add_msg(@inbox_id, 'foo')
      @mail_store.add_msg(@inbox_id, 'bar')
      @mail_store.add_msg(@inbox_id, 'baz')
      @mail_store.add_mbox('foo')
      @mail_store.add_mbox('bar')

      # recovery phase 5
      assert_nil(@mail_store.mbox_id(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME))

      # recovery phase 1,8
      @msg_db.add_msg(3, 'apple')
      assert_equal({}, @meta_db.msg_mbox_uid_mapping(3))
      assert_raise(RuntimeError) { @meta_db.msg_date(3) }

      # recovery phase 2,5,8
      mbox_uid_map = Marshal.load(@kvs['meta']['msg_id2mbox-0'])
      mbox_uid_map[10] = [ 1 ].to_set
      @kvs['meta']['msg_id2mbox-0'] = Marshal.dump(mbox_uid_map)
      assert_equal({ @inbox_id => [ 1 ].to_set, 10 => [ 1 ].to_set }, @meta_db.msg_mbox_uid_mapping(0))
      assert_nil(@meta_db.mbox_name(10))
      assert_nil(@mbox_db[10])

      # recovery phase 6,8
      mbox_uid_map = Marshal.load(@kvs['meta']['msg_id2mbox-1'])
      mbox_uid_map[@inbox_id] << 1
      @kvs['meta']['msg_id2mbox-1'] = Marshal.dump(mbox_uid_map)
      assert_equal({ @inbox_id => [ 1, 2 ].to_set }, @meta_db.msg_mbox_uid_mapping(1))

      @meta_db.recovery_phase1_msg_scan(@msg_db, logger: @logger)
      @meta_db.recovery_phase2_msg_scan(@msg_db, logger: @logger)
      @meta_db.recovery_phase3_mbox_scan(logger: @logger)
      @meta_db.recovery_phase4_mbox_scan(logger: @logger)
      @meta_db.recovery_phase5_mbox_repair(logger: @logger) {|mbox_id|
        @mbox_db[mbox_id] = RIMS::DB::Mailbox.new(@kvs_open.call("mbox_#{mbox_id}"))
      }
      @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: @logger)
      @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, RIMS::MailStore::MSG_FLAG_NAMES, logger: @logger)
      @meta_db.recovery_phase8_lost_found(@mbox_db, logger: @logger)

      # recovery phase 5
      assert_not_nil(lost_found_id = @mail_store.mbox_id(RIMS::DB::Meta::LOST_FOUND_MBOX_NAME))
      assert_instance_of(RIMS::DB::Mailbox, @mbox_db[lost_found_id])

      # recovery phase 1,8
      assert_equal({ lost_found_id => [ 1 ].to_set }, @meta_db.msg_mbox_uid_mapping(3))
      assert_instance_of(Time, @meta_db.msg_date(3))
      assert_equal(3, @mbox_db[lost_found_id].msg_id(1))

      # recovery phase 2,5,8
      assert_equal({ @inbox_id => [ 1 ].to_set, 10 => [ 1 ].to_set }, @meta_db.msg_mbox_uid_mapping(0))
      assert_equal('MAILBOX#10', @meta_db.mbox_name(10))
      assert_equal(10, @meta_db.mbox_id('MAILBOX#10'))
      assert_instance_of(RIMS::DB::Mailbox, @mbox_db[10])
      assert_equal([ 1 ], @mbox_db[10].each_msg_uid.to_a)
      assert_equal(0, @mbox_db[10].msg_id(1))

      # recovery phase 6,8
      assert_equal({ @inbox_id => [ 2 ].to_set, lost_found_id => [ 2 ].to_set }, @meta_db.msg_mbox_uid_mapping(1))
      assert_equal(1, @mbox_db[lost_found_id].msg_id(2))

      # recovery phase 8
      assert_equal([ 1, 2 ], @mbox_db[lost_found_id].each_msg_uid.to_a)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
