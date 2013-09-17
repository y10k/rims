# -*- coding: utf-8 -*-

module RIMS
  class MailStore
    def initialize(store_dir, &block) # :yields: path
      @store_dir = store_dir
      @open_kvs = block
    end

    def open_kvs(name)
      @open_kvs.call(File.join(@store_dir, name))
    end
    private :open_kvs

    def open
      @global_db = GlobalDB.new(open_kvs('global.db'))
      @msg_db = GlobalDB.new(open_kvs('message.db'))

      @mbox_db = []
      @global_db.each_mbox_id do |id|
        @mbox_db[id] = MessageDB.new(open_kvs("mbox_#{id}.db"))
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
      @global_db.uid
    end

    def uidvalidity
      @global_db.uidvalidity
    end

    def add_mbox(name)
      if (@global_db.mbox_id(name)) then
        raise "duplicated mailbox name: #{name}."
      end

      cnum = @global_db.cnum
      next_id = @global_db.uidvalidity

      @mbox_db[next_id] = MessageDB.new(open_kvs("mbox_#{next_id}.db"))
      @mbox_db[next_id].mbox_id = next_id
      @mbox_db[next_id].mbox_name = name

      @global_db.uidvalidity = next_id + 1
      @global_db.add_mbox(next_id, name)
      @global_db.cnum = cnum + 1

      next_id
    end

    def del_mbox(id)
      cnum = @global_db.cnum

      mbox_db = @mbox_db[id] or raise "not found a mailbox: #{id}."
      mbox_db.each_msg_id do |msg_id|
        @msg_db.del_msg_mbox(msg_id, id)
      end
      mbox_db.close

      name = @global_db.del_mbox(id) or raise "internal error: not found a mailbox: #{id}"
      @global_db.cnum = cnum + 1

      name
    end

    def each_mbox_id
      return enum_for(:each_mbox_id) unless block_given?
      @global_db.each_mbox_id do |id|
        yield(id)
      end
      self
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
