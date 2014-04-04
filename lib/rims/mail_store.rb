# -*- coding: utf-8 -*-

require 'logger'
require 'set'
require 'thread'

module RIMS
  class MailStore
    MSG_FLAG_NAMES = %w[ answered flagged deleted seen draft recent ].each{|n| n.freeze }.freeze

    def initialize(meta_db, msg_db, &mbox_db_factory) # :yields: mbox_id
      @meta_db = meta_db
      @msg_db = msg_db
      @mbox_db_factory = mbox_db_factory

      @mbox_db = {}
      @meta_db.each_mbox_id do |mbox_id|
        @mbox_db[mbox_id] = @mbox_db_factory.call(mbox_id)
      end

      if (@meta_db.dirty?) then
        @abort_transaction = true
      else
        @abort_transaction = false
        @meta_db.dirty = true
      end
    end

    def abort_transaction?
      @abort_transaction
    end

    def transaction
      if (@abort_transaction) then
        raise 'abort transaction.'
      end

      begin
        yield
      ensure
        @abort_transaction = true if $!
      end
    end

    def recovery_data(logger: Logger.new(STDOUT))
      begin
        logger.info('test read all: meta DB')
        @meta_db.test_read_all do |error|
          logger.error("read fail: #{error}")
        end
        logger.info('test read all: msg DB')
        @msg_db.test_read_all do |error|
          logger.error("read fail: #{error}")
        end
        @mbox_db.each_key do |mbox_id|
          logger.info("test_read_all: mailbox DB #{mbox_id}")
          @mbox_db[mbox_id].test_read_all do |error|
            logger.error("read fail: #{error}")
          end
        end

        @meta_db.recovery_start
        @meta_db.recovery_phase1_msg_scan(@msg_db, logger: logger)
        @meta_db.recovery_phase2_msg_scan(@msg_db, logger: logger)
        @meta_db.recovery_phase3_mbox_scan(logger: logger)
        @meta_db.recovery_phase4_mbox_scan(logger: logger)
        @meta_db.recovery_phase5_mbox_repair(logger: logger) {|mbox_id|
          @mbox_db[mbox_id] = @mbox_db_factory.call(mbox_id)
        }
        @meta_db.recovery_phase6_msg_scan(@mbox_db, logger: logger)
        @meta_db.recovery_phase7_mbox_msg_scan(@mbox_db, MSG_FLAG_NAMES, logger: logger)
        @meta_db.recovery_phase8_lost_found(@mbox_db, logger: logger)
        @meta_db.recovery_end
      ensure
        @abort_transaction = ! $!.nil?
      end

      self
    end

    def close
      @mbox_db.each_value do |db|
        db.close
      end
      @msg_db.close
      @meta_db.dirty = false unless @abort_transaction
      @meta_db.close
      self
    end

    def sync
      transaction{
        @msg_db.sync
        @mbox_db.each_value do |db|
          db.sync
        end
        @meta_db.sync
        self
      }
    end

    def cnum
      @meta_db.cnum
    end

    def uid(mbox_id)
      @meta_db.mbox_uid(mbox_id)
    end

    def uidvalidity
      @meta_db.uidvalidity
    end

    def add_mbox(name)
      transaction{
        name = 'INBOX' if (name =~ /\AINBOX\z/i)
        name = name.b

        mbox_id = @meta_db.add_mbox(name)
        @mbox_db[mbox_id] = @mbox_db_factory.call(mbox_id)

        @meta_db.cnum_succ!

        mbox_id
      }
    end

    def del_mbox(mbox_id)
      transaction{
        mbox_name = @meta_db.mbox_name(mbox_id) or raise "not found a mailbox: #{mbox_id}."

        mbox_db = @mbox_db.delete(mbox_id)
        mbox_db.each_msg_uid do |uid|
          msg_id = mbox_db.msg_id(uid)
          del_msg(msg_id, mbox_id, uid)
        end
        mbox_db.close
        mbox_db.destroy

        for name in MSG_FLAG_NAMES
          @meta_db.clear_mbox_flag_num(mbox_id, name)
        end
        @meta_db.del_mbox(mbox_id) or raise 'internal error.'

        @meta_db.cnum_succ!

        mbox_name
      }
    end

    def rename_mbox(mbox_id, new_name)
      transaction{
        old_name = @meta_db.mbox_name(mbox_id) or raise "not found a mailbox: #{mbox_id}."
        old_name = old_name.dup.force_encoding('utf-8')

        new_name = 'INBOX' if (new_name =~ /\AINBOX\z/i)
        @meta_db.rename_mbox(mbox_id, new_name.b)

        @meta_db.cnum_succ!

        old_name
      }
    end

    def mbox_name(mbox_id)
      if (name = @meta_db.mbox_name(mbox_id)) then
        name.dup.force_encoding('utf-8')
      end
    end

    def mbox_id(mbox_name)
      mbox_name = 'INBOX' if (mbox_name =~ /\AINBOX\z/i)
      @meta_db.mbox_id(mbox_name.b)
    end

    def each_mbox_id
      return enum_for(:each_mbox_id) unless block_given?
      @meta_db.each_mbox_id do |mbox_id|
        yield(mbox_id)
      end
      self
    end

    def mbox_msg_num(mbox_id)
      @meta_db.mbox_msg_num(mbox_id)
    end

    def mbox_flag_num(mbox_id, flag_name)
      if (MSG_FLAG_NAMES.include? flag_name) then
        @meta_db.mbox_flag_num(mbox_id, flag_name)
      else
        raise "unknown flag name: #{name}"
      end
    end

    def add_msg(mbox_id, msg_text, msg_date=Time.now)
      transaction{
        mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."

        msg_id = @meta_db.msg_id_succ!
        @msg_db.add_msg(msg_id, msg_text)
        @meta_db.set_msg_date(msg_id, msg_date)
        @meta_db.set_msg_flag(msg_id, 'recent', true)

        uid = @meta_db.add_msg_mbox_uid(msg_id, mbox_id)
        mbox_db.add_msg(uid, msg_id)

        @meta_db.cnum_succ!

        uid
      }
    end

    def del_msg(msg_id, mbox_id, uid)
      mbox_uid_map = @meta_db.del_msg_mbox_uid(msg_id, mbox_id, uid)
      if (mbox_uid_map.empty?) then
        @meta_db.clear_msg_date(msg_id)
        @meta_db.clear_msg_flag(msg_id)
        @meta_db.clear_msg_mbox_uid_mapping(msg_id)
        @msg_db.del_msg(msg_id)
      end
      @meta_db.mbox_flag_num_decrement(mbox_id, 'deleted')
      nil
    end
    private :del_msg

    def copy_msg(src_uid, src_mbox_id, dst_mbox_id)
      transaction{
        src_mbox_db = @mbox_db[src_mbox_id] or raise "not found a source mailbox: #{src_mbox_id}"
        dst_mbox_db = @mbox_db[dst_mbox_id] or raise "not found a destination mailbox: #{dst_mbox_id}"

        msg_id = src_mbox_db.msg_id(src_uid) or raise "not found a message: #{src_mbox_id},#{src_uid}"
        dst_uid = @meta_db.add_msg_mbox_uid(msg_id, dst_mbox_id)
        dst_mbox_db.add_msg(dst_uid, msg_id)

        @meta_db.cnum_succ!

        self
      }
    end

    def msg_exist?(mbox_id, uid)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      mbox_db.msg_exist? uid
    end

    def msg_text(mbox_id, uid)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      msg_id = mbox_db.msg_id(uid) or raise "not found a message: #{mbox_id},#{uid}"
      @msg_db.msg_text(msg_id)
    end

    def msg_date(mbox_id, uid)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      msg_id = mbox_db.msg_id(uid) or raise "not found a message: #{mbox_id},#{uid}"
      @meta_db.msg_date(msg_id)
    end

    def msg_flag(mbox_id, uid, flag_name)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."

      if ((MSG_FLAG_NAMES - %w[ deleted ]).include? flag_name) then
        msg_id = mbox_db.msg_id(uid) or raise "not found a message: #{mbox_id},#{uid}"
        @meta_db.msg_flag(msg_id, flag_name)
      elsif (flag_name == 'deleted') then
        mbox_db.msg_flag_deleted(uid)
      else
        raise "unnown flag name: #{flag_name}"
      end
    end

    def set_msg_flag(mbox_id, uid, flag_name, flag_value)
      transaction{
        mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."

        if ((MSG_FLAG_NAMES - %w[ deleted ]).include? flag_name) then
          msg_id = mbox_db.msg_id(uid) or raise "not found a message: #{mbox_id},#{uid}"
          @meta_db.set_msg_flag(msg_id, flag_name, flag_value)
        elsif (flag_name == 'deleted') then
          prev_deleted = mbox_db.msg_flag_deleted(uid)
          mbox_db.set_msg_flag_deleted(uid, flag_value)
          if (! prev_deleted && flag_value) then
            @meta_db.mbox_flag_num_increment(mbox_id, 'deleted')
          elsif (prev_deleted && ! flag_value) then
            @meta_db.mbox_flag_num_decrement(mbox_id, 'deleted')
          end
        else
          raise "unnown flag name: #{flag_name}"
        end

        @meta_db.cnum_succ!

        self
      }
    end

    def each_msg_uid(mbox_id)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      return enum_for(:each_msg_uid, mbox_id) unless block_given?
      mbox_db.each_msg_uid do |uid|
        yield(uid)
      end
      self
    end

    def expunge_mbox(mbox_id)
      transaction{
        mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."

        uid_list = mbox_db.each_msg_uid.find_all{|uid| mbox_db.msg_flag_deleted(uid) }
        msg_id_list = uid_list.map{|uid| mbox_db.msg_id(uid) }

        uid_list.zip(msg_id_list) do |uid, msg_id|
          mbox_db.expunge_msg(uid)
          del_msg(msg_id, mbox_id, uid)
          yield(uid) if block_given?
        end

        @meta_db.cnum_succ!

        self
      }
    end

    def select_mbox(mbox_id)
      MailFolder.new(mbox_id, self)
    end

    def examine_mbox(mbox_id)
      @meta_db.mbox_name(mbox_id) or raise "not found a mailbox: #{mbox_id}."
      MailFolder.new(mbox_id, self, read_only: true)
    end
  end

  class MailFolder
    MessageStruct = Struct.new(:uid, :num)

    def initialize(mbox_id, mail_store, read_only: false)
      @mbox_id = mbox_id
      @mail_store = mail_store
      @read_only = read_only
      reload
    end

    def reload
      @cnum = @mail_store.cnum
      msg_id_list = @mail_store.each_msg_uid(@mbox_id).to_a
      msg_id_list.sort!
      @msg_list = msg_id_list.zip(1..(msg_id_list.length)).map{|id, num| MessageStruct.new(id, num) }
      self
    end

    def updated?
      @mail_store.cnum > @cnum
    end

    attr_reader :mbox_id
    attr_reader :msg_list
    attr_reader :read_only
    alias read_only? read_only

    def expunge_mbox
      if (@mail_store.mbox_flag_num(@mbox_id, 'deleted') > 0) then
        if (block_given?) then
          uid2num = {}
          for msg in @msg_list
            uid2num[msg.uid] = msg.num
          end

          @mail_store.expunge_mbox(@mbox_id) do |uid|
            num = uid2num[uid] or raise "internal error: not found a message: #{@mbox_id},#{uid}"
            yield(num)
          end
        else
          @mail_store.expunge_mbox(@mbox_id)
        end
      end

      self
    end

    def close
      unless (@read_only) then
        expunge_mbox
        @mail_store.each_msg_uid(@mbox_id) do |msg_id|
          if (@mail_store.msg_flag(@mbox_id, msg_id, 'recent')) then
            @mail_store.set_msg_flag(@mbox_id, msg_id, 'recent', false)
          end
        end
      end

      self
    end

    def parse_msg_set(msg_set_desc, uid: false)
      if (@msg_list.empty?) then
        [].to_set
      else
        if (uid) then
          last_number = @msg_list[-1].uid
        else
          last_number = @msg_list[-1].num
        end
        self.class.parse_msg_set(msg_set_desc, last_number)
      end
    end

    def self.parse_msg_seq(msg_seq_desc, last_number)
      case (msg_seq_desc)
      when /\A(\d+|\*)\z/
        msg_seq_pair = [ $&, $& ]
      when /\A(\d+|\*):(\d+|\*)\z/
        msg_seq_pair = [ $1, $2 ]
      else
        raise MessageSetSyntaxError, "invalid message sequence format: #{msg_seq_desc}"
      end

      msg_seq_pair.map!{|num|
        case (num)
        when '*'
          last_number
        else
          n = num.to_i
          if (n < 1) then
            raise MessageSetSyntaxError, "out of range of message sequence number: #{msg_seq_desc}"
          end
          n
        end
      }

      Range.new(msg_seq_pair[0], msg_seq_pair[1])
    end

    def self.parse_msg_set(msg_set_desc, last_number)
      msg_set = [].to_set
      msg_set_desc.split(/,/).each do |msg_seq_desc|
        msg_range = parse_msg_seq(msg_seq_desc, last_number)
        msg_range.step do |n|
          msg_set << n
        end
      end

      msg_set
    end
  end

  class MailStorePool
    Holder = Struct.new(:mail_store, :user_name, :user_lock)
    RefCountEntry = Struct.new(:count, :mail_store_holder)

    def initialize(kvs_open_attr, kvs_open_text, make_user_prefix)
      @kvs_open_attr = kvs_open_attr
      @kvs_open_text = kvs_open_text
      @make_user_prefix = make_user_prefix
      @pool_map = {}
      @pool_lock = Mutex.new
      @user_lock_map = Hash.new{|hash, key| hash[key] = Mutex.new }
    end

    def empty?
      @pool_map.empty?
    end

    def new_mail_store(user_name)
      user_prefix = @make_user_prefix.call(user_name)
      mail_store = MailStore.new(DB::Meta.new(@kvs_open_attr.call(user_prefix, 'meta')),
                                 DB::Message.new(@kvs_open_text.call(user_prefix, 'msg'))) {|mbox_id|
        DB::Mailbox.new(@kvs_open_attr.call(user_prefix, "mbox_#{mbox_id}"))
      }
      unless (mail_store.mbox_id('INBOX')) then
        mail_store.add_mbox('INBOX')
      end
      mail_store
    end
    private :new_mail_store

    def get(user_name)
      user_lock = @pool_lock.synchronize{ @user_lock_map[user_name] }
      user_lock.synchronize{
        if (@pool_map.key? user_name) then
          ref_count_entry = @pool_map[user_name]
        else
          mail_store = new_mail_store(user_name)
          holder = Holder.new(mail_store, user_name, user_lock)
          ref_count_entry = RefCountEntry.new(0, holder)
          @pool_map[user_name] = ref_count_entry
        end
        if (ref_count_entry.count < 0) then
          raise 'internal error.'
        end
        ref_count_entry.count += 1
        ref_count_entry.mail_store_holder
      }
    end

    def put(mail_store_holder)
      user_lock = @pool_lock.synchronize{ @user_lock_map[mail_store_holder.user_name] }
      user_lock.synchronize{
        ref_count_entry = @pool_map[mail_store_holder.user_name] or raise 'internal error.'
        if (ref_count_entry.count < 1) then
          raise 'internal error.'
        end
        ref_count_entry.count -= 1
        if (ref_count_entry.count == 0) then
          @pool_map.delete(mail_store_holder.user_name)
          ref_count_entry.mail_store_holder.mail_store.close
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
