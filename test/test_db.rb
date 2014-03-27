# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'rims'
require 'set'
require 'test/unit'

module RIMS::Test
  class DBMetaTest < Test::Unit::TestCase
    def setup
      @kvs = {}
      @db = RIMS::DB::Meta.new(RIMS::Hash_KeyValueStore.new(@kvs))
    end

    def teardown
      pp @kvs if $DEBUG
    end

    def test_cnum
      assert_equal(0, @db.cnum)
      assert_equal(0, @db.cnum_succ!)
      assert_equal(1, @db.cnum)
    end

    def test_msg_id
      assert_equal(0, @db.msg_id)
      assert_equal(0, @db.msg_id_succ!)
      assert_equal(1, @db.msg_id)
    end

    def test_uidvalidity
      assert_equal(1, @db.uidvalidity)
      assert_equal(1, @db.uidvalidity_succ!)
      assert_equal(2, @db.uidvalidity)
    end

    def test_mbox
      assert_equal(1, @db.uidvalidity)
      assert_equal([], @db.each_mbox_id.to_a)
      assert_nil(@db.mbox_name(1))
      assert_nil(@db.mbox_id('foo'))

      id = @db.add_mbox('foo')
      assert_equal(1, id)

      assert_equal(2, @db.uidvalidity)
      assert_equal([ 1 ], @db.each_mbox_id.to_a)
      assert_equal('foo', @db.mbox_name(1))
      assert_equal(1, @db.mbox_id('foo'))

      assert_nil(@db.rename_mbox(1, 'foo'))

      assert_equal(2, @db.uidvalidity)
      assert_equal([ 1 ], @db.each_mbox_id.to_a)
      assert_equal('foo', @db.mbox_name(1))
      assert_equal(1, @db.mbox_id('foo'))

      assert_not_nil(@db.rename_mbox(1, 'bar'))

      assert_equal(2, @db.uidvalidity)
      assert_equal([ 1 ], @db.each_mbox_id.to_a)
      assert_equal('bar', @db.mbox_name(1))
      assert_nil(@db.mbox_id('foo'))
      assert_equal(1, @db.mbox_id('bar'))

      assert_nil(@db.del_mbox(2))

      assert_equal(2, @db.uidvalidity)
      assert_equal([ 1 ], @db.each_mbox_id.to_a)
      assert_equal('bar', @db.mbox_name(1))
      assert_nil(@db.mbox_id('foo'))
      assert_equal(1, @db.mbox_id('bar'))

      assert_not_nil(@db.del_mbox(1))

      assert_equal(2, @db.uidvalidity)
      assert_equal([], @db.each_mbox_id.to_a)
      assert_nil(@db.mbox_name(1))
      assert_nil(@db.mbox_id('foo'))
      assert_nil(@db.mbox_id('bar'))
    end

    def test_mbox_uid
      id = @db.add_mbox('foo')
      assert_equal(1, @db.mbox_uid(id))
      assert_equal(1, @db.mbox_uid_succ!(id))
      assert_equal(2, @db.mbox_uid(id))
    end

    def test_mbox_msg_num
      id = @db.add_mbox('foo')
      assert_equal(0, @db.mbox_msg_num(id))
      @db.mbox_msg_num_increment(id)
      assert_equal(1, @db.mbox_msg_num(id))
      @db.mbox_msg_num_decrement(id)
      assert_equal(0, @db.mbox_msg_num(id))
    end

    def test_mbox_flags
      id = @db.add_mbox('foo')
      assert_equal(0, @db.mbox_flag_num(id, 'flagged'))
      @db.mbox_flag_num_increment(id, 'flagged')
      assert_equal(1, @db.mbox_flag_num(id, 'flagged'))
      @db.mbox_flag_num_decrement(id, 'flagged')
      assert_equal(0, @db.mbox_flag_num(id, 'flagged'))
      @db.mbox_flag_num_increment(id, 'flagged')
      @db.mbox_flag_num_increment(id, 'flagged')
      assert_equal(2, @db.mbox_flag_num(id, 'flagged'))
      assert_not_nil(@db.clear_mbox_flag_num(id, 'flagged'))
      assert_equal(0, @db.mbox_flag_num(id, 'flagged'))
      assert_nil(@db.clear_mbox_flag_num(id, 'flagged'))
      assert_equal(0, @db.mbox_flag_num(id, 'flagged'))
    end

    def test_msg_date
      t = Time.mktime(2014, 3, 7, 18, 15, 56)
      @db.set_msg_date(0, t)
      assert_equal(t, @db.msg_date(0))
      @db.clear_msg_date(0)
      assert_raise(RuntimeError) { @db.clear_msg_date(0) }
    end

    def test_msg_flag
      assert_equal(false, @db.msg_flag(0, 'recent'))
      assert_equal(false, @db.msg_flag(0, 'seen'))

      @db.set_msg_flag(0, 'recent', true)
      assert_equal(true, @db.msg_flag(0, 'recent'))
      assert_equal(false, @db.msg_flag(0, 'seen'))

      @db.set_msg_flag(0, 'seen', true)
      assert_equal(true, @db.msg_flag(0, 'recent'))
      assert_equal(true, @db.msg_flag(0, 'seen'))

      @db.set_msg_flag(0, 'recent', false)
      assert_equal(false, @db.msg_flag(0, 'recent'))
      assert_equal(true, @db.msg_flag(0, 'seen'))

      assert_not_nil(@db.clear_msg_flag(0))
      assert_equal(false, @db.msg_flag(0, 'recent'))
      assert_equal(false, @db.msg_flag(0, 'seen'))

      assert_nil(@db.clear_msg_flag(0))
      assert_equal(false, @db.msg_flag(0, 'recent'))
      assert_equal(false, @db.msg_flag(0, 'seen'))
    end

    def test_msg_mbox_uid_mapping
      assert_equal(1, @db.add_mbox('INBOX'))
      assert_equal(2, @db.add_mbox('foo'))

      assert_equal({}, @db.msg_mbox_uid_mapping(0))

      assert_equal(1, @db.add_msg_mbox_uid(0, 1))
      assert_equal({ 1 => [ 1 ].to_set
                   }, @db.msg_mbox_uid_mapping(0))

      assert_equal(2, @db.add_msg_mbox_uid(0, 1))
      assert_equal({ 1 => [ 1, 2 ].to_set
                   }, @db.msg_mbox_uid_mapping(0))

      assert_equal(1, @db.add_msg_mbox_uid(0, 2))
      assert_equal({ 1 => [ 1, 2 ].to_set,
                     2 => [ 1 ].to_set
                   }, @db.msg_mbox_uid_mapping(0))

      assert_nil(@db.del_msg_mbox_uid(0, 2, 2))
      assert_equal({ 1 => [ 1, 2 ].to_set,
                     2 => [ 1 ].to_set
                   }, @db.msg_mbox_uid_mapping(0))

      assert_equal({ 1 => [ 1, 2 ].to_set
                   }, @db.del_msg_mbox_uid(0, 2, 1))
      assert_equal({ 1 => [ 1, 2 ].to_set
                   }, @db.msg_mbox_uid_mapping(0))

      assert_nil(@db.del_msg_mbox_uid(0, 2, 1))
      assert_equal({ 1 => [ 1, 2 ].to_set
                   }, @db.msg_mbox_uid_mapping(0))

      assert_equal({ 1 => [ 2 ].to_set
                   }, @db.del_msg_mbox_uid(0, 1, 1))
      assert_equal({ 1 => [ 2 ].to_set
                   }, @db.msg_mbox_uid_mapping(0))

      assert_equal({}, @db.del_msg_mbox_uid(0, 1, 2))
      assert_equal({}, @db.msg_mbox_uid_mapping(0))

      assert_not_nil(@db.clear_msg_mbox_uid_mapping(0))
      assert_equal({}, @db.msg_mbox_uid_mapping(0))

      assert_nil(@db.clear_msg_mbox_uid_mapping(0))
      assert_equal({}, @db.msg_mbox_uid_mapping(0))
    end

    def test_mbox_msg_num_auto_increment_decrement
      inbox_id = @db.add_mbox('INBOX')
      foo_id = @db.add_mbox('foo')

      msg_a = 0
      msg_b = 1

      assert_equal(0, @db.mbox_msg_num(inbox_id))
      assert_equal(0, @db.mbox_msg_num(foo_id))

      assert_equal(1, @db.add_msg_mbox_uid(msg_a, inbox_id))

      assert_equal(1, @db.mbox_msg_num(inbox_id))
      assert_equal(0, @db.mbox_msg_num(foo_id))

      assert_equal(2, @db.add_msg_mbox_uid(msg_b, inbox_id))

      assert_equal(2, @db.mbox_msg_num(inbox_id))
      assert_equal(0, @db.mbox_msg_num(foo_id))

      assert_equal(3, @db.add_msg_mbox_uid(msg_a, inbox_id))

      assert_equal(3, @db.mbox_msg_num(inbox_id))
      assert_equal(0, @db.mbox_msg_num(foo_id))

      assert_equal(1, @db.add_msg_mbox_uid(msg_a, foo_id))

      assert_equal(3, @db.mbox_msg_num(inbox_id))
      assert_equal(1, @db.mbox_msg_num(foo_id))

      assert_equal({ inbox_id => [ 1, 3 ].to_set,
                     foo_id => [ 1 ].to_set
                   }, @db.msg_mbox_uid_mapping(msg_a))
      assert_equal({ inbox_id => [ 2 ].to_set,
                   }, @db.msg_mbox_uid_mapping(msg_b))

      @db.del_msg_mbox_uid(msg_a, inbox_id, 1)

      assert_equal(2, @db.mbox_msg_num(inbox_id))
      assert_equal(1, @db.mbox_msg_num(foo_id))

      @db.del_msg_mbox_uid(msg_a, foo_id, 1)

      assert_equal(2, @db.mbox_msg_num(inbox_id))
      assert_equal(0, @db.mbox_msg_num(foo_id))

      @db.del_msg_mbox_uid(msg_b, inbox_id, 2)

      assert_equal(1, @db.mbox_msg_num(inbox_id))
      assert_equal(0, @db.mbox_msg_num(foo_id))

      assert_equal({ inbox_id => [ 3 ].to_set,
                   }, @db.msg_mbox_uid_mapping(msg_a))
      assert_equal({}, @db.msg_mbox_uid_mapping(msg_b))
    end

    def test_mbox_flag_num_auto_increment_decrement
      inbox_id = @db.add_mbox('INBOX')
      foo_id = @db.add_mbox('foo')

      msg_a = 0
      msg_b = 1

      assert_equal({}, @db.msg_mbox_uid_mapping(msg_a))
      assert_equal({}, @db.msg_mbox_uid_mapping(msg_b))

      assert_equal([ 0, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      assert_equal(1, @db.add_msg_mbox_uid(msg_a, inbox_id))
      assert_equal({ inbox_id => [ 1 ].to_set
                   }, @db.msg_mbox_uid_mapping(msg_a))

      assert_equal([ 0, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.set_msg_flag(msg_a, 'recent', true)

      assert_equal([ 1, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      assert_equal(1, @db.add_msg_mbox_uid(msg_a, foo_id))
      assert_equal({ inbox_id => [ 1 ].to_set,
                     foo_id => [ 1 ].to_set
                   }, @db.msg_mbox_uid_mapping(msg_a))

      assert_equal([ 1, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 1, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.set_msg_flag(msg_a, 'seen', true)

      assert_equal([ 1, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 1, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.set_msg_flag(msg_b, 'recent', true)

      assert_equal([ 1, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 1, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      assert_equal(2, @db.add_msg_mbox_uid(msg_b, inbox_id))
      assert_equal({ inbox_id => [ 2 ].to_set
                   }, @db.msg_mbox_uid_mapping(msg_b))

      assert_equal([ 2, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 1, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      assert_equal(3, @db.add_msg_mbox_uid(msg_b, inbox_id))
      assert_equal({ inbox_id => [ 2, 3 ].to_set
                   }, @db.msg_mbox_uid_mapping(msg_b))

      assert_equal([ 3, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 1, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.set_msg_flag(msg_b, 'seen', true)

      assert_equal([ 3, 3 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 1, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.set_msg_flag(msg_a, 'recent', false)

      assert_equal([ 2, 3 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.set_msg_flag(msg_b, 'recent', false)

      assert_equal([ 0, 3 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.del_msg_mbox_uid(msg_a, inbox_id, 1)
      assert_equal({ foo_id => [ 1 ].to_set
                   }, @db.msg_mbox_uid_mapping(msg_a))

      assert_equal([ 0, 2 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.del_msg_mbox_uid(msg_b, inbox_id, 2)
      assert_equal({ inbox_id => [ 3 ].to_set
                   }, @db.msg_mbox_uid_mapping(msg_b))

      assert_equal([ 0, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.del_msg_mbox_uid(msg_a, foo_id, 1)
      assert_equal({}, @db.msg_mbox_uid_mapping(msg_a))

      assert_equal([ 0, 1 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })

      @db.del_msg_mbox_uid(msg_b, inbox_id, 3)
      assert_equal({}, @db.msg_mbox_uid_mapping(msg_b))

      assert_equal([ 0, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(inbox_id, name) })
      assert_equal([ 0, 0 ], %w[ recent seen ].map{|name| @db.mbox_flag_num(foo_id, name) })
    end
  end

  class DBMessageTest < Test::Unit::TestCase
    def setup
      @kvs = {}
      @db = RIMS::DB::Message.new(RIMS::Hash_KeyValueStore.new(@kvs))
    end

    def teardown
      pp @kvs if $DEBUG
    end

    def test_msg
      assert_equal([], @db.each_msg_id.to_a)
      assert_nil(@db.msg_text(0))
      assert_nil(@db.msg_text(1))
      assert_nil(@db.msg_text(2))
      assert_equal(false, (@db.msg_exist? 0))
      assert_equal(false, (@db.msg_exist? 1))
      assert_equal(false, (@db.msg_exist? 2))

      @db.add_msg(0, 'foo')
      assert_equal([ 0 ], @db.each_msg_id.to_a)
      assert_equal('foo', @db.msg_text(0))
      assert_nil(@db.msg_text(1))
      assert_nil(@db.msg_text(2))
      assert_equal(true, (@db.msg_exist? 0))
      assert_equal(false, (@db.msg_exist? 1))
      assert_equal(false, (@db.msg_exist? 2))

      @db.add_msg(1, 'bar')
      assert_equal([ 0, 1 ], @db.each_msg_id.to_a)
      assert_equal('foo', @db.msg_text(0))
      assert_equal('bar', @db.msg_text(1))
      assert_nil(@db.msg_text(2))
      assert_equal(true, (@db.msg_exist? 0))
      assert_equal(true, (@db.msg_exist? 1))
      assert_equal(false, (@db.msg_exist? 2))

      @db.add_msg(2, 'baz')
      assert_equal([ 0, 1, 2 ], @db.each_msg_id.to_a)
      assert_equal('foo', @db.msg_text(0))
      assert_equal('bar', @db.msg_text(1))
      assert_equal('baz', @db.msg_text(2))
      assert_equal(true, (@db.msg_exist? 0))
      assert_equal(true, (@db.msg_exist? 1))
      assert_equal(true, (@db.msg_exist? 2))

      @db.del_msg(1)
      assert_equal([ 0, 2 ], @db.each_msg_id.to_a)
      assert_equal('foo', @db.msg_text(0))
      assert_nil(@db.msg_text(1))
      assert_equal('baz', @db.msg_text(2))
      assert_equal(true, (@db.msg_exist? 0))
      assert_equal(false, (@db.msg_exist? 1))
      assert_equal(true, (@db.msg_exist? 2))

      assert_raise(RuntimeError) { @db.del_msg(1) }
    end
  end

  class DBMailboxTest < Test::Unit::TestCase
    def setup
      @kvs = {}
      @db = RIMS::DB::Mailbox.new(RIMS::Hash_KeyValueStore.new(@kvs))
    end

    def teardown
      pp @kvs if $DEBUG
    end

    def test_msg
      assert_equal([], @db.each_msg_uid.to_a)
      [ [ 1, false, nil, nil ],
        [ 2, false, nil, nil ],
        [ 3, false, nil, nil ]
      ].each do |uid, exist, msg_id, deleted|
        assert_equal(exist, (@db.msg_exist? uid))
        assert_equal(msg_id, @db.msg_id(uid))
        assert_equal(deleted, @db.msg_flag_deleted(uid))
      end

      @db.add_msg(1, 0)

      assert_equal([ 1 ], @db.each_msg_uid.to_a)
      [ [ 1, true, 0, false ],
        [ 2, false, nil, nil ],
        [ 3, false, nil, nil ]
      ].each do |uid, exist, msg_id, deleted|
        assert_equal(exist, (@db.msg_exist? uid))
        assert_equal(msg_id, @db.msg_id(uid))
        assert_equal(deleted, @db.msg_flag_deleted(uid))
      end

      @db.add_msg(2, 1)

      assert_equal([ 1, 2 ], @db.each_msg_uid.to_a)
      [ [ 1, true, 0, false ],
        [ 2, true, 1, false ],
        [ 3, false, nil, nil ]
      ].each do |uid, exist, msg_id, deleted|
        assert_equal(exist, (@db.msg_exist? uid))
        assert_equal(msg_id, @db.msg_id(uid))
        assert_equal(deleted, @db.msg_flag_deleted(uid))
      end

      @db.add_msg(3, 0)

      assert_equal([ 1, 2, 3 ], @db.each_msg_uid.to_a)
      [ [ 1, true, 0, false ],
        [ 2, true, 1, false ],
        [ 3, true, 0, false ]
      ].each do |uid, exist, msg_id, deleted|
        assert_equal(exist, (@db.msg_exist? uid))
        assert_equal(msg_id, @db.msg_id(uid))
        assert_equal(deleted, @db.msg_flag_deleted(uid))
      end

      @db.set_msg_flag_deleted(1, true)

      [ [ 1, true, 0, true ],
        [ 2, true, 1, false ],
        [ 3, true, 0, false ]
      ].each do |uid, exist, msg_id, deleted|
        assert_equal(exist, (@db.msg_exist? uid))
        assert_equal(msg_id, @db.msg_id(uid))
        assert_equal(deleted, @db.msg_flag_deleted(uid))
      end

      @db.expunge_msg(1)

      [ [ 1, false, nil, nil ],
        [ 2, true, 1, false ],
        [ 3, true, 0, false ]
      ].each do |uid, exist, msg_id, deleted|
        assert_equal(exist, (@db.msg_exist? uid))
        assert_equal(msg_id, @db.msg_id(uid))
        assert_equal(deleted, @db.msg_flag_deleted(uid))
      end

      assert_raise(RuntimeError) { @db.expunge_msg(1) }
      assert_raise(RuntimeError) { @db.expunge_msg(2) }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
