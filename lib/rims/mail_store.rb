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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
