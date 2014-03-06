# -*- coding: utf-8 -*-

require 'set'

module RIMS
  class CoreDB
    def initialize(kv_store)
      @db = kv_store
    end

    def sync
      @db.sync
      self
    end

    def close
      @db.close
      self
    end
  end

  class GlobalDB < CoreDB
    def setup
      [ %w[ cnum 0 ],
        %w[ uidvalidity 1 ]
      ].each do |k, v|
        @db[k] = v unless (@db.key? k)
      end

      self
    end

    def cnum
      @db['cnum'].to_i
    end

    def cnum_succ!
      @db['cnum'] = @db['cnum'].succ!
    end

    def uidvalidity
      @db['uidvalidity'].to_i
    end

    def add_mbox(name)
      id = @db['uidvalidity']
      @db['uidvalidity'] = id.succ

      @db["mbox_id-#{id}"] = name
      @db["mbox_name-#{name}"] = id

      id.to_i
    end

    def del_mbox(id)
      name = @db.delete("mbox_id-#{id}")
      unless (name) then
        return
      end

      id2 = @db.delete("mbox_name-#{name}")
      unless (id2) then
        raise "internal error: not found a mailbox name entry at `{id}'"
      end
      if (id2.to_i != id) then
        raise "internal error: expected id <#{id}> but was <#{id2}>."
      end

      name
    end

    def rename_mbox(id, new_name)
      old_name = @db["mbox_id-#{id}"] or raise "not found a mailbox: #{id}"
      if (@db.key? "mbox_name-#{new_name}") then
        raise "duplicated mailbox name: #{new_name}"
      end
      @db["mbox_id-#{id}"] = new_name
      @db["mbox_name-#{new_name}"] = id.to_s
      @db.delete("mbox_name-#{old_name}") or raise 'internal error.'
      old_name
    end

    def mbox_name(id)
      @db["mbox_id-#{id}"]
    end

    def mbox_id(name)
      v = @db["mbox_name-#{name}"] and v.to_i
    end

    def each_mbox_id
      return enum_for(:each_mbox_id) unless block_given?
      @db.each_key do |key|
        if (key =~ /\Ambox_id-\d+\z/) then
          yield($&[8..-1].to_i)
        end
      end
      self
    end
  end

  class MessageDB
    def initialize(text_st, attr_st)
      @text_st = text_st
      @attr_st = attr_st
    end

    def sync
      @text_st.sync
      @attr_st.sync
      self
    end

    def close
      errors = []
      for db in [ @text_st, @attr_st ]
        begin
          db.close
        rescue
          errors << $!
        end
      end

      unless (errors.empty?) then
        if (errors.length == 1) then
          raise errors[0]
        else
          raise 'failed to close message db: ' + errors.map{|ex| "[#{ex.class}] #{ex.message}" }.join(', ')
        end
      end

      self
    end

    def setup
      @attr_st['uid'] = '1' unless (@attr_st.key? 'uid')
      self
    end

    def uid
      @attr_st['uid'].to_i
    end

    def add_msg(text, date=Time.now)
      id = @attr_st['uid']
      @attr_st['uid'] = id.succ

      @text_st[id] = text
      @attr_st["date-#{id}"] = Marshal.dump(date)

      id = id.to_i
      save_flags(id, [].to_set)
      save_mboxes(id, [].to_set)

      id
    end

    def clean_msg(id)
      if (@text_st.delete(id.to_s)) then
        @attr_st.delete("date-#{id}") or raise "internal error: #{id}"
        self
      else
        raise "not found a message at #{id}"
      end
    end
    private :clean_msg

    def load_flags(id)
      if (flag_list_bin = @attr_st["flags-#{id}"]) then
        flag_list_bin.split(/,/).to_set
      end
    end
    private :load_flags

    def save_flags(id, flag_set)
      @attr_st["flags-#{id}"] = flag_set.to_a.join(',')
      nil
    end
    private :save_flags

    def clean_flags(id)
      if (@attr_st.delete("flags-#{id}")) then
        self
      else
        raise "not found a message flags at #{id}"
      end
    end
    private :clean_flags

    def load_mboxes(id)
      if (mbox_list_bin = @attr_st["mbox-#{id}"]) then
        mbox_list_bin.split(/,/).map{|id_bin| id_bin.to_i }.to_set
      end
    end
    private :load_mboxes

    def save_mboxes(id, mbox_set)
      @attr_st["mbox-#{id}"] = mbox_set.to_a.map{|mbox_id| mbox_id.to_s }.join(',')
      nil
    end
    private :save_mboxes

    def clean_mboxes(id)
      if (@attr_st.delete("mbox-#{id}")) then
        self
      else
        raise "not found a message mboxes at #{id}"
      end
    end
    private :clean_mboxes

    def msg_text(id)
      @text_st[id.to_s]
    end

    def msg_date(id)
      if (date_bin = @attr_st["date-#{id}"]) then
        Marshal.load(date_bin)
      end
    end

    def each_msg_id
      return enum_for(:each_msg_id) unless block_given?
      @text_st.each_key do |key|
        yield(key.to_i)
      end
      self
    end

    def get_mbox_flags(mbox_id, name)
      if (count = @attr_st["mbox-#{mbox_id}-flag_count-#{name}"]) then
        count.to_i
      end
    end
    private :get_mbox_flags

    def set_mbox_flags(mbox_id, name, count)
      @attr_st["mbox-#{mbox_id}-flag_count-#{name}"] = count.to_s
      nil
    end
    private :set_mbox_flags

    def mbox_flags(mbox_id, name)
      get_mbox_flags(mbox_id, name) || 0
    end

    def mbox_flags_increment(mbox_id, name)
      set_mbox_flags(mbox_id, name, (mbox_flags(mbox_id, name) + 1).to_s)
      nil
    end
    private :mbox_flags_increment

    def mbox_flags_decrement(mbox_id, name)
      count = get_mbox_flags(mbox_id, name) or raise "not found a mailbox flag counter: #{mbox_id}, #{name}"
      unless (count > 0) then
        raise "mailbox flag counter is underflow: #{mbox_id}, #{name}"
      end
      set_mbox_flags(mbox_id, name, (count - 1).to_s)
      nil
    end
    private :mbox_flags_decrement

    def msg_flag(id, name)
      flag_set = load_flags(id) or raise "not found a message at `#{id}'."
      flag_set.include? name
    end

    def set_msg_flag(id, name, value)
      flag_set = load_flags(id) or raise "not found amessage at `#{id}'."
      if (value) then
        is_modified = flag_set.add?(name)
        if (is_modified) then
          for mbox_id in msg_mboxes(id)
            mbox_flags_increment(mbox_id, name)
          end
        end
      else
        is_modified = flag_set.delete?(name)
        if (is_modified) then
          for mbox_id in msg_mboxes(id)
            mbox_flags_decrement(mbox_id, name)
          end
        end
      end
      if (is_modified) then
        save_flags(id, flag_set)
        self
      end
    end

    def msg_mboxes(id)
      load_mboxes(id) or raise "not found a message at `#{id}'."
    end

    def add_msg_mbox(id, mbox_id)
      mbox_set = load_mboxes(id) or raise "not found a message at `#{id}'."
      is_modified = mbox_set.add?(mbox_id)
      if (is_modified) then
        for name in load_flags(id)
          mbox_flags_increment(mbox_id, name)
        end
        save_mboxes(id, mbox_set)
        self
      end
    end

    def del_msg_mbox(id, mbox_id)
      mbox_set = load_mboxes(id) or raise "not found a message at `#{id}'."
      is_modified = mbox_set.delete?(mbox_id)
      if (is_modified) then
        for name in load_flags(id)
          mbox_flags_decrement(mbox_id, name)
        end
        if (mbox_set.empty?) then
          clean_msg(id)
          clean_flags(id)
          clean_mboxes(id)
        else
          save_mboxes(id, mbox_set)
        end
        self
      end
    end
  end

  class MailboxDB < CoreDB
    def mbox_id
      if (id = @db['mbox_id']) then
        id.to_i
      end
    end

    def mbox_id=(id)
      @db['mbox_id'] = id.to_s
      id
    end

    def mbox_name
      @db['mbox_name']
    end

    def mbox_name=(name)
      @db['mbox_name'] = name
      name
    end

    def setup
      [ %w[ msg_count 0 ],
        %w[ flags_deleted 0 ]
      ].each do |k, v|
        @db[k] = v unless (@db.key? k)
      end

      self
    end

    def get_msgs
      if (count = @db['msg_count']) then
        count.to_i
      end
    end
    private :get_msgs

    def set_msgs(count)
      @db['msg_count'] = count.to_s
      nil
    end

    def msgs
      get_msgs || 0
    end

    def msgs_increment
      count = msgs
      set_msgs(count + 1)
      nil
    end
    private :msgs_increment

    def msgs_decrement
      count = get_msgs or raise 'not found a message counter.'
      unless (count > 0) then
        raise 'message counter is underflowr.'
      end
      set_msgs(count - 1)
      nil
    end
    private :msgs_decrement

    def get_del_flags
      if (count = @db['flags_deleted']) then
        count.to_i
      end
    end
    private :get_del_flags

    def set_del_flags(count)
      @db['flags_deleted'] = count.to_s
      nil
    end
    private :set_del_flags

    def del_flags
      get_del_flags || 0
    end

    def del_flags_increment
      count = del_flags
      set_del_flags(count + 1)
      nil
    end
    private :del_flags_increment

    def del_flags_decrement
      count = get_del_flags or raise 'not found a deleted flag counter.'
      unless (count > 0) then
        raise 'deleted flag counter is underflow.'
      end
      set_del_flags(count - 1)
      nil
    end
    private :del_flags_decrement

    def add_msg(id)
      unless (exist_msg? id) then
        @db["msg-#{id}"] = ''
        msgs_increment
        self
      end
    end

    def exist_msg?(id)
      @db.key? "msg-#{id}"
    end

    def msg_flag_del(id)
      (exist_msg? id) or raise "not exist message: #{id}."
      @db["msg-#{id}"] == 'deleted'
    end

    def set_msg_flag_del(id, value)
      (exist_msg? id) or raise "not exist message: #{id}."
      old_flag_value = @db["msg-#{id}"]
      new_flag_value = value ? 'deleted' : ''
      @db["msg-#{id}"] = new_flag_value
      if (old_flag_value != new_flag_value) then
        if (value) then
          del_flags_increment
        else
          del_flags_decrement
        end
        self
      end
    end

    def expunge_msg(id)
      (exist_msg? id) or raise "not exist message: #{id}."
      msg_flag_del(id) or raise "no deleted flag: #{id}."
      @db.delete("msg-#{id}")
      msgs_decrement
      del_flags_decrement
      self
    end

    def each_msg_id
      return enum_for(:each_msg_id) unless block_given?
      @db.each_key do |key|
        if (key =~ /\Amsg-\d+\z/) then
          yield($&[4..-1].to_i)
        end
      end
      self
    end
  end

  module DB
    class Core
      def initialize(kvs)
        @kvs = kvs
      end

      def sync
        @kvs.sync
        self
      end

      def close
        @kvs.close
        self
      end

      def get_str(key, default_value: nil)
        @kvs[key] || default_value
      end
      private :get_str

      def put_str(key, str)
        @kvs[key] = str
        self
      end
      private :put_str

      def get_num(key, default_value: 0)
        if (s = @kvs[key]) then
          s.to_i
        else
          default_value
        end
      end
      private :get_num

      def put_num(key, num)
        @kvs[key] = num.to_s
        self
      end
      private :put_num

      def num_succ!(key, default_value: 0)
        n = get_num(key, default_value: default_value)
        put_num(key, n + 1)
        n
      end
      private :num_succ!

      def get_num_set(key)
        if (s = @kvs[key]) then
          s.split(',', -1).map{|n| n.to_i }.to_set
        else
          [].to_set
        end
      end
      private :get_num_set

      def put_num_set(key, num_set)
        @kvs[key] = num_set.to_a.join(',')
        self
      end
      private :put_num_set
    end

    class Meta < Core
    end

    class Message < Core
    end

    class Mailbox < Core
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
