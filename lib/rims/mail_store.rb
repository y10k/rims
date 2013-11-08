# -*- coding: utf-8 -*-

require 'set'
require 'thread'

module RIMS
  class MailStore
    def initialize(kvs_open_attr, kvs_open_text)
      @kvs_open_attr = kvs_open_attr
      @kvs_open_text = kvs_open_text
    end

    def open
      @global_db = GlobalDB.new(@kvs_open_attr.call('global.db')).setup
      @msg_db = MessageDB.new(@kvs_open_text.call('msg_text.db'), @kvs_open_attr.call('msg_attr.db')).setup

      @mbox_db = {}
      @global_db.each_mbox_id do |id|
        @mbox_db[id] = MailboxDB.new(@kvs_open_attr.call("mbox_#{id}.db")).setup
      end

      self
    end

    def close
      @mbox_db.each_value do |db|
        db.close
      end
      @msg_db.close
      @global_db.close
      self
    end

    def sync
      @msg_db.sync
      @mbox_db.each_value do |db|
        db.sync
      end
      @global_db.sync
      self
    end

    def cnum
      @global_db.cnum
    end

    def uid
      @msg_db.uid
    end

    def uidvalidity
      @global_db.uidvalidity
    end

    def add_mbox(name)
      name = 'INBOX' if (name =~ /^INBOX$/i)
      if (@global_db.mbox_id(name)) then
        raise "duplicated mailbox name: #{name}."
      end

      next_id = @global_db.add_mbox(name)
      @mbox_db[next_id] = MailboxDB.new(@kvs_open_attr.call("mbox_#{next_id}.db")).setup
      @mbox_db[next_id].mbox_id = next_id
      @mbox_db[next_id].mbox_name = name

      @global_db.cnum_succ!

      next_id
    end

    def del_mbox(id)
      mbox_db = @mbox_db[id] or raise "not found a mailbox: #{id}."
      mbox_db.each_msg_id do |msg_id|
        @msg_db.del_msg_mbox(msg_id, id)
      end
      mbox_db.close
      name = @global_db.del_mbox(id) or raise "internal error: not found a mailbox: #{id}"

      @global_db.cnum_succ!

      name
    end

    def mbox_name(id)
      @global_db.mbox_name(id)
    end

    def mbox_id(name)
      name = 'INBOX' if (name =~ /^INBOX$/i)
      @global_db.mbox_id(name)
    end

    def each_mbox_id
      return enum_for(:each_mbox_id) unless block_given?
      @global_db.each_mbox_id do |id|
        yield(id)
      end
      self
    end

    def mbox_msgs(id)
      mbox_db = @mbox_db[id] or raise "not found a mailbox: #{id}."
      mbox_db.msgs
    end

    def mbox_flags(id, name)
      mbox_db = @mbox_db[id] or raise "not found a mailbox: #{id}."
      case (name)
      when 'recent', 'seen', 'answered', 'flagged', 'draft'
        @msg_db.mbox_flags(id, name)
      when 'deleted'
        mbox_db.del_flags
      else
        raise "unknown flag name: #{name}"
      end
    end

    def add_msg(mbox_id, msg_text, msg_date=Time.now)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."

      msg_id = @msg_db.add_msg(msg_text, msg_date)
      @msg_db.add_msg_mbox(msg_id, mbox_id)
      @msg_db.set_msg_flag(msg_id, 'seen', false)
      @msg_db.set_msg_flag(msg_id, 'answered', false)
      @msg_db.set_msg_flag(msg_id, 'flagged', false)
      @msg_db.set_msg_flag(msg_id, 'draft', false)
      mbox_db.add_msg(msg_id)

      # @g_db.cnum_succ! is called at set_msg_flag.
      set_msg_flag(mbox_id, msg_id, 'recent', true)

      msg_id
    end

    def copy_msg(msg_id, dest_mbox_id)
      mbox_db = @mbox_db[dest_mbox_id] or raise "not found a mailbox: #{dest_mbox_id}."

      unless (mbox_db.exist_msg? msg_id) then
        @msg_db.add_msg_mbox(msg_id, dest_mbox_id)
        mbox_db.add_msg(msg_id)
      end

      @global_db.cnum_succ!

      self
    end

    def msg_text(mbox_id, msg_id)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      @msg_db.msg_text(msg_id) if (mbox_db.exist_msg? msg_id)
    end

    def msg_date(mbox_id, msg_id)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      @msg_db.msg_date(msg_id) if (mbox_db.exist_msg? msg_id)
    end

    def msg_flag(mbox_id, msg_id, name)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      unless (mbox_db.exist_msg? msg_id) then
        raise "not found a message <#{msg_id}> at mailbox <#{mbox_id}>."
      end

      case (name)
      when 'recent', 'seen', 'answered', 'flagged', 'draft'
        @msg_db.msg_flag(msg_id, name)
      when 'deleted'
        mbox_db.msg_flag_del(msg_id)
      else
        raise "unnown flag name: #{name}"
      end
    end

    def set_msg_flag(mbox_id, msg_id, name, value)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      unless (mbox_db.exist_msg? msg_id) then
        raise "not found a message <#{msg_id}> at mailbox <#{mbox_id}>."
      end

      case (name)
      when 'recent', 'seen', 'answered', 'flagged', 'draft'
        @msg_db.set_msg_flag(msg_id, name, value)
      when 'deleted'
        mbox_db.set_msg_flag_del(msg_id, value)
      else
        raise "unnown flag name: #{name}"
      end

      @global_db.cnum_succ!

      self
    end

    def each_msg_id(mbox_id)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      return enum_for(:each_msg_id, mbox_id) unless block_given?
      mbox_db.each_msg_id do |id|
        yield(id)
      end
      self
    end

    def expunge_mbox(mbox_id)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."

      msg_list = mbox_db.each_msg_id.find_all{|id| mbox_db.msg_flag_del(id) }
      for id in msg_list
        @msg_db.del_msg_mbox(id, mbox_id)
        mbox_db.expunge_msg(id)
        yield(id) if block_given?
      end

      @global_db.cnum_succ!

      self
    end

    def select_mbox(mbox_id)
      mbox_db = @mbox_db[mbox_id] or raise "not found a mailbox: #{mbox_id}."
      MailFolder.new(mbox_id, self)
    end
  end

  class MailFolder
    MessageStruct = Struct.new(:id, :num)

    def initialize(mbox_id, mail_store)
      @id = mbox_id
      @mail_store = mail_store
      reload
    end

    def reload
      @cnum = @mail_store.cnum
      msg_id_list = @mail_store.each_msg_id(@id).to_a
      msg_id_list.sort!
      @msg_list = msg_id_list.zip(1..(msg_id_list.length)).map{|id, num| MessageStruct.new(id, num) }
      self
    end

    def updated?
      @mail_store.cnum > @cnum
    end

    attr_reader :id
    attr_reader :msg_list

    def expunge_mbox
      if (@mail_store.mbox_flags(@id, 'deleted') > 0) then
        if (block_given?) then
          id2num = {}
          for msg in @msg_list
            id2num[msg.id] = msg.num
          end

          @mail_store.expunge_mbox(@id) do |id|
            num = id2num[id] or raise "internal error: not found a message id <#{id}> at mailbox <#{@id}>"
            yield(num)
          end
        else
          @mail_store.expunge_mbox(@id)
        end
      end

      self
    end

    def close
      expunge_mbox
      @mail_store.each_msg_id(@id) do |msg_id|
        if (@mail_store.msg_flag(@id, msg_id, 'recent')) then
          @mail_store.set_msg_flag(@id, msg_id, 'recent', false)
        end
      end

      self
    end

    def parse_msg_set(msg_set_desc, uid: false)
      if (uid) then
        last_number = @msg_list[-1].id
      else
        last_number = @msg_list[-1].num
      end
      self.class.parse_msg_set(msg_set_desc, last_number)
    end

    def self.parse_msg_seq(msg_seq_desc, last_number)
      case (msg_seq_desc)
      when /^(\d+|\*)$/
        msg_seq_pair = [ $&, $& ]
      when /^(\d+|\*):(\d+|\*)$/
        msg_seq_pair = [ $1, $2 ]
      else
        raise "invalid message sequence format: #{msg_seq_desc}"
      end

      msg_seq_pair.map!{|num|
        case (num)
        when '*'
          last_number
        else
          n = num.to_i
          if (n < 1) then
            raise "out of range of message sequence number: #{msg_seq_desc}"
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

  # factory for single mailbox user.
  # multi-user mailbox will be future challenge.
  class MailStorePool
    RefCountEntry = Struct.new(:count, :mail_store_holder)

    class Holder
      def initialize(mail_store, user_name, user_lock)
        @mail_store = mail_store
        @user_name = user_name
        @user_lock = user_lock
      end

      attr_reader :mail_store
      attr_reader :user_name
      attr_reader :user_lock

      alias to_mst mail_store
    end

    def new_mail_store(user_name)
      mail_store = MailStore.new(proc{|db_name| @kvs_open_attr.call(user_name, db_name) },
                                 proc{|db_name| @kvs_open_text.call(user_name, db_name) })
      mail_store.open
      unless (mail_store.mbox_id('INBOX')) then
        mail_store.add_mbox('INBOX')
      end
      mail_store
    end
    private :new_mail_store

    def initialize(kvs_open_attr, kvs_open_text)
      @kvs_open_attr = kvs_open_attr
      @kvs_open_text = kvs_open_text
      @pool_map = {}
      @pool_lock = Mutex.new
      @user_lock_map = Hash.new{|hash, key| hash[key] = Mutex.new }
    end

    def empty?
      @pool_map.empty?
    end

    def get(user_name)
      user_lock = @pool_lock.synchronize{ user_lock = @user_lock_map[user_name] }
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
      ref_count_entry = @pool_map[mail_store_holder.user_name] or raise 'internal error.'
      ref_count_entry.mail_store_holder.user_lock.synchronize{
        if (ref_count_entry.count < 1) then
          raise 'internal error.'
        end
        ref_count_entry.count -= 1
        if (ref_count_entry.count == 0) then
          @pool_map.delete(mail_store_holder.user_name)
          ref_count_entry.mail_store_holder.to_mst.close
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
