# -*- coding: utf-8 -*-

require 'logger'
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

      def test_read_all         # :yields: read_error
        last_error = nil
        @kvs.each_key do |key|
          begin
            @kvs[key]
          rescue
            last_error = $!
            yield($!)
          end
        end

        if (last_error) then
          raise last_error
        end

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
      def dirty?
        @kvs.key? 'dirty'
      end

      def dirty=(dirty_flag)
        if (dirty_flag) then
          put_str('dirty', '')
        else
          @kvs.delete('dirty')
        end
        @kvs.sync

        dirty_flag
      end

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

      def add_mbox(name, mbox_id: nil)
        if (@kvs.key? "mbox_name2id-#{name}") then
          raise "duplicated mailbox name: #{name}."
        end

        if (mbox_id) then
          if (@kvs.key? "mbox_id2name-#{mbox_id}") then
            raise "duplicated mailbox id: #{mbox_id}"
          end
          if (uidvalidity <= mbox_id) then
            put_num('uidvalidity', mbox_id + 1)
          end
        else
          mbox_id = uidvalidity_succ!
        end

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
        if (@kvs.delete("msg_id2date-#{msg_id}")) then
          self
        end
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
            mbox_uid_map.delete(mbox_id) if uid_set.empty?
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

      def recovery_start
        @lost_found_msg_set = [].to_set
        @lost_found_mbox_set = [].to_set
      end

      def recovery_end
        @lost_found_msg_set = nil
        @lost_found_mbox_set = nil
      end

      attr_reader :lost_found_msg_set
      attr_reader :lost_found_mbox_set

      def get_recover_entry(key, prefix)
        if (key.start_with? prefix) then
          entry_key = key[(prefix.length)..-1]
          entry_key = yield(entry_key) if block_given?
          entry_key
        end
      end
      private :get_recover_entry

      def recovery_phase1_msg_scan(msg_db, logger: Logger.new(STDOUT))
        logger.info('recovery phase 1: start.')

        max_msg_id = -1
        msg_db.each_msg_id do |msg_id|
          max_msg_id = msg_id if (max_msg_id < msg_id)
          unless (@kvs.key? "msg_id2mbox-#{msg_id}") then
            logger.warn("lost+found message: #{msg_id}")
            @lost_found_msg_set << msg_id
          end
          unless (@kvs.key? "msg_id2date-#{msg_id}") then
            logger.warn("repair internal date: #{msg_id}")
            set_msg_date(msg_id, Time.now)
          end
        end

        if (msg_id <= max_msg_id) then
          next_msg_id = max_msg_id + 1
          logger.warn("repair msg_id: #{next_msg_id}")
          put_num('msg_id', next_msg_id)
        end

        logger.info('recovery phase 1: end.')

        self
      end

      def recovery_phase2_msg_scan(msg_db, logger: Logger.new(STDOUT))
        logger.info('recovery phase 2: start.')

        lost_msg_set = [].to_set
        mbox_set = get_num_set('mbox_set')

        @kvs.each_key do |key|
          if (msg_id = get_recover_entry(key, 'msg_id2mbox-') {|s| s.to_i }) then
            if (msg_db.msg_exist? msg_id) then
              msg_mbox_uid_mapping(msg_id).each_key do |mbox_id|
                unless (mbox_set.include? mbox_id) then
                  logger.warn("lost+found mailbox: #{mbox_id}")
                  @lost_found_mbox_set << mbox_id
                end
              end
            else
              lost_msg_set << msg_id
            end
          end
        end

        for msg_id in lost_msg_set
          logger.warn("clear lost message: #{msg_id}")
          clear_msg_date(msg_id)
          clear_msg_flag(msg_id)
          clear_msg_mbox_uid_mapping(msg_id)
        end

        logger.info('recovery phase 2: end.')

        self
      end

      def make_mbox_repair_name(mbox_id)
        new_name = "MAILBOX##{mbox_id}"
        if (mbox_id(new_name)) then
          new_name << ' (1)'
          while (mbox_id(new_name))
            new_name.succ!
          end
        end

        new_name
      end
      private :make_mbox_repair_name

      def recovery_phase3_mbox_scan(logger: Logger.new(STDOUT))
        logger.info('recovery phase 3: start.')

        mbox_set = get_num_set('mbox_set')

        max_mbox_id = 0
        for mbox_id in mbox_set
          max_mbox_id = mbox_id if (mbox_id > max_mbox_id)
          if (name = mbox_name(mbox_id)) then
            mbox_id2 = mbox_id(name)
            unless (mbox_id2 && (mbox_id2 == mbox_id)) then
              logger.warn("repair mailbox name -> id: #{name.inspect} -> #{mbox_id}")
              put_num("mbox_name2id-#{name}", mbox_id)
            end
          else
            new_name = make_mbox_repair_name(mbox_id)
            logger.warn("repair mailbox id name pair: #{mbox_id}, #{new_name.inspect}")
            put_str("mbox_id2name-#{mbox_id}", new_name)
            put_num("mbox_name2id-#{new_name}", mbox_id)
          end
        end

        if (uidvalidity <= max_mbox_id) then
          next_uidvalidity = max_mbox_id + 1
          logger.warn("repair uidvalidity: #{next_uidvalidity}")
          put_num('uidvalidity', next_uidvalidity)
        end

        logger.info('recovery phase 3: end.')

        self
      end

      def recovery_phase4_mbox_scan(logger: Logger.new(STDOUT))
        logger.info('recovery phase 4: start.')

        mbox_set = get_num_set('mbox_set')

        del_key_list = []
        @kvs.each_key do |key|
          if (mbox_id = get_recover_entry(key, 'mbox_id2name-') {|s| s.to_i }) then
            unless (mbox_set.include? mbox_id) then
              del_key_list << key
            end
          elsif (name = get_recover_entry(key, 'mbox_name2id-')) then
            unless ((mbox_id = mbox_id(name)) && (mbox_set.include? mbox_id) && (mbox_name(mbox_id) == name)) then
              del_key_list << key
            end
          end
        end

        for key in del_key_list
          logger.warn("unlinked mailbox entry: #{key}")
          @kvs.delete(key)
        end

        logger.info('recovery phase 4: end.')

        self
      end

      def recovery_phase5_mbox_repair
      end

      def recovery_phase6_msg_scan
      end

      def recovery_phase7_mbox_msg_scan
      end

      def recovery_phase8_lost_found
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
