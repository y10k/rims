# -*- coding: utf-8 -*-

require 'gdbm'
require 'rims'
require 'test/unit'

module RIMS::Test
  class GDBM_KeyValueStoreTest < Test::Unit::TestCase
    include KeyValueStoreTestUtility

    def open_database
      GDBM.new(@name)
    end

    def make_key_value_store
      RIMS::GDBM_KeyValueStore.new(@db, @name)
    end
  end

  class GDBM_KeyValueStoreOpenCloseTest < Test::Unit::TestCase
    include KeyValueStoreOpenCloseTestUtility

    def get_kvs_name
      'gdbm'
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
