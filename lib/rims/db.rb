# -*- coding: utf-8 -*-

require 'set'

module RIMS
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

      def destroy
        @kvs.destroy
        nil
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

      def get_str_set(key)
        if (s = @kvs[key]) then
          s.split(',', -1).to_set
        else
          [].to_set
        end
      end
      private :get_str_set

      def put_str_set(key, str_set)
        @kvs[key] = str_set.to_a.join(',')
        self
      end
      private :put_str_set

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

      def num_increment(key)
        n = get_num(key)
        put_num(key, n + 1)
        self
      end
      private :num_increment

      def num_decrement(key)
        n = get_num(key)
        put_num(key, n - 1)
        self
      end
      private :num_decrement

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

      def get_obj(key, default_value: nil)
        if (s = @kvs[key]) then
          Marshal.load(s)
        else
          default_value
        end
      end
      private :get_obj

      def put_obj(key, value)
        @kvs[key] = Marshal.dump(value)
        self
      end
      private :put_obj
    end

    class Meta < Core
      def cnum
        get_num('cnum')
      end

      def cnum_succ!
        num_succ!('cnum')
      end

      def msg_id
        get_num('msg_id')
      end

      def msg_id_succ!
        num_succ!('msg_id')
      end

      def uidvalidity
        get_num('uidvalidity', default_value: 1)
      end

      def uidvalidity_succ!
        num_succ!('uidvalidity', default_value: 1)
      end

      def add_mbox(name)
        if (@kvs.key? "mbox_name2id-#{name}") then
          raise "duplicated mailbox name: #{name}."
        end

        mbox_id = uidvalidity_succ!
        mbox_set = get_num_set('mbox_set')
        if (mbox_set.include? mbox_id) then
          raise "internal error: duplicated mailbox id: #{mbox_id}"
        end
        mbox_set << mbox_id
        put_num_set('mbox_set', mbox_set)

        put_str("mbox_id2name-#{mbox_id}", name)
        put_num("mbox_name2id-#{name}", mbox_id)

        mbox_id
      end

      def del_mbox(mbox_id)
        mbox_set = get_num_set('mbox_set')
        if (mbox_set.include? mbox_id) then
          mbox_set.delete(mbox_id)
          put_num_set('mbox_set', mbox_set)
          name = mbox_name(mbox_id)
          @kvs.delete("mbox_id2name-#{mbox_id}") or raise "not found a mailbox name for id: #{mbox_id}"
          @kvs.delete("mbox_name2id-#{name}") or raise "not found a mailbox id for name: #{name}"
          @kvs.delete("mbox_id2uid-#{mbox_id}")
          @kvs.delete("mbox_id2msgnum-#{mbox_id}")
          self
        end
      end

      def rename_mbox(mbox_id, new_name)
        old_name = get_str("mbox_id2name-#{mbox_id}") or raise "not found a mailbox name for id: #{mbox_id}"
        if (new_name == old_name) then
          return
        end
        if (@kvs.key? "mbox_name2id-#{new_name}") then
          raise "duplicated mailbox name: #{new_name}"
        end
        @kvs.delete("mbox_name2id-#{old_name}") or raise "not found a mailbox old name for id: #{mbox_id}"
        put_str("mbox_id2name-#{mbox_id}", new_name)
        put_num("mbox_name2id-#{new_name}", mbox_id)
        self
      end

      def each_mbox_id
        return enum_for(:each_mbox_id) unless block_given?
        mbox_set = get_num_set('mbox_set')
        for mbox_id in mbox_set
          yield(mbox_id)
        end
        self
      end

      def mbox_name(mbox_id)
        get_str("mbox_id2name-#{mbox_id}", default_value: nil)
      end

      def mbox_id(name)
        get_num("mbox_name2id-#{name}", default_value: nil)
      end

      def mbox_uid(mbox_id)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        get_num("mbox_id2uid-#{mbox_id}", default_value: 1)
      end

      def mbox_uid_succ!(mbox_id)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        num_succ!("mbox_id2uid-#{mbox_id}", default_value: 1)
      end

      def mbox_msg_num(mbox_id)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        get_num("mbox_id2msgnum-#{mbox_id}")
      end

      def mbox_msg_num_increment(mbox_id)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        num_increment("mbox_id2msgnum-#{mbox_id}")
        self
      end

      def mbox_msg_num_decrement(mbox_id)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        num_decrement("mbox_id2msgnum-#{mbox_id}")
        self
      end

      def mbox_flag_num(mbox_id, name)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        get_num("mbox_id2flagnum-#{mbox_id}-#{name}")
      end

      def mbox_flag_num_increment(mbox_id, name)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        num_increment("mbox_id2flagnum-#{mbox_id}-#{name}")
        self
      end

      def mbox_flag_num_decrement(mbox_id, name)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        num_decrement("mbox_id2flagnum-#{mbox_id}-#{name}")
        self
      end

      def clear_mbox_flag_num(mbox_id, name)
        mbox_name(mbox_id) or raise "not found a mailbox for id: #{mbox_id}"
        if (@kvs.delete("mbox_id2flagnum-#{mbox_id}-#{name}")) then
          self
        end
      end

      def msg_date(msg_id)
        get_obj("msg_id2date-#{msg_id}") or raise "not found a message date for internal id: #{msg_id}"
      end

      def set_msg_date(msg_id, date)
        put_obj("msg_id2date-#{msg_id}", date)
        self
      end

      def clear_msg_date(msg_id)
        @kvs.delete("msg_id2date-#{msg_id}") or raise "not found a message date for internal id: #{msg_id}"
        self
      end

      def msg_flag(msg_id, name)
        flag_set = get_str_set("msg_id2flag-#{msg_id}")
        flag_set.include? name
      end

      def set_msg_flag(msg_id, name, value)
        flag_set = get_str_set("msg_id2flag-#{msg_id}")
        if (value) then
          unless (flag_set.include? name) then
            mbox_uid_map = msg_mbox_uid_mapping(msg_id)
            for mbox_id, uid_set in mbox_uid_map
              uid_set.length.times do
                mbox_flag_num_increment(mbox_id, name)
              end
            end
          end
          flag_set.add(name)
        else
          if (flag_set.include? name) then
            mbox_uid_map = msg_mbox_uid_mapping(msg_id)
            for mbox_id, uid_set in mbox_uid_map
              uid_set.length.times do
                mbox_flag_num_decrement(mbox_id, name)
              end
            end
          end
          flag_set.delete(name)
        end
        put_str_set("msg_id2flag-#{msg_id}", flag_set)
        self
      end

      def clear_msg_flag(msg_id)
        if (@kvs.delete("msg_id2flag-#{msg_id}")) then
          self
        end
      end

      def msg_mbox_uid_mapping(msg_id)
        get_obj("msg_id2mbox-#{msg_id}", default_value: {})
      end

      def add_msg_mbox_uid(msg_id, mbox_id)
        uid = mbox_uid_succ!(mbox_id)
        mbox_uid_map = msg_mbox_uid_mapping(msg_id)
        if (mbox_uid_map.key? mbox_id) then
          msg_uid_set = mbox_uid_map[mbox_id]
        else
          msg_uid_set = mbox_uid_map[mbox_id] = [].to_set
        end
        if (msg_uid_set.include? uid) then
          raise "duplicated uid(#{uid}) in mailbox id(#{mbox_id} on message id(#{msg_id}))"
        end
        mbox_uid_map[mbox_id] << uid
        put_obj("msg_id2mbox-#{msg_id}", mbox_uid_map)

        mbox_msg_num_increment(mbox_id)
        flag_set = get_str_set("msg_id2flag-#{msg_id}")
        for name in flag_set
          mbox_flag_num_increment(mbox_id, name)
        end

        uid
      end

      def del_msg_mbox_uid(msg_id, mbox_id, uid)
        mbox_uid_map = msg_mbox_uid_mapping(msg_id)
        if (uid_set = mbox_uid_map[mbox_id]) then
          if (uid_set.include? uid) then
            uid_set.delete(uid)
            if (uid_set.empty?) then
              mbox_uid_map.delete(mbox_id)
            end
            put_obj("msg_id2mbox-#{msg_id}", mbox_uid_map)

            mbox_msg_num_decrement(mbox_id)
            flag_set = get_str_set("msg_id2flag-#{msg_id}")
            for name in flag_set
              mbox_flag_num_decrement(mbox_id, name)
            end

            mbox_uid_map
          end
        end
      end

      def clear_msg_mbox_uid_mapping(msg_id)
        if (@kvs.delete("msg_id2mbox-#{msg_id}")) then
          self
        end
      end
    end

    class Message < Core
      def add_msg(msg_id, text)
        put_str(msg_id.to_s, text)
        self
      end

      def del_msg(msg_id)
        @kvs.delete(msg_id.to_s) or raise "not found a message text for id: #{msg_id}"
        self
      end

      def each_msg_id
        return enum_for(:each_msg_id) unless block_given?
        @kvs.each_key do |msg_id|
          yield(msg_id.to_i)
        end
        self
      end

      def msg_text(msg_id)
        get_str(msg_id.to_s)
      end

      def msg_exist?(msg_id)
	@kvs.key? msg_id.to_s
      end
    end

    class Mailbox < Core
      def put_msg_id(uid, msg_id, deleted: false)
        s = msg_id.to_s
        s << ',deleted' if deleted
        @kvs[uid.to_s] = s
        self
      end
      private :put_msg_id

      def add_msg(uid, msg_id)
        put_msg_id(uid, msg_id)
        self
      end

      def each_msg_uid
        return enum_for(:each_msg_uid) unless block_given?
        @kvs.each_key do |uid|
          yield(uid.to_i)
        end
        self
      end

      def msg_exist?(uid)
        @kvs.key? uid.to_s
      end

      def msg_id(uid)
        if (s = @kvs[uid.to_s]) then
          s.split(',', 2)[0].to_i
        end
      end

      def msg_flag_deleted(uid)
        if (s = @kvs[uid.to_s]) then
          s.split(',', 2)[1] == 'deleted'
        end
      end

      def set_msg_flag_deleted(uid, value)
        msg_id = msg_id(uid) or raise "not found a message uid: #{uid}"
        put_msg_id(uid, msg_id, deleted: value)
        self
      end

      def expunge_msg(uid)
        case (msg_flag_deleted(uid))
        when true
          # OK
        when false
          raise "not deleted flag at message uid: #{uid}"
        when nil
          raise "not found a message uid: #{uid}"
        else
          raise 'internal error.'
        end
        @kvs.delete(uid.to_s) or raise 'internal error.'
        self
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
