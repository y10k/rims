# -*- coding: utf-8 -*-

require 'rims'
require 'test/unit'

module RIMS::Test
  class MailStoreTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @mail_store = RIMS::MailStore.new('foo') {|path|
        RIMS::GDBM_KeyValueStore.new(@kv_store[path] = {})
      }
    end

    def test_open
      @mail_store.open
      assert_equal({ 'foo/global.db' => {}, 'foo/message.db' => {} }, @kv_store)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
