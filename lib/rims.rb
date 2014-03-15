# -*- coding: utf-8 -*-

require "rims/version"

module RIMS
  autoload :Cmd, 'rims/cmd'
  autoload :Config, 'rims/server'
  autoload :DB, 'rims/db'
  autoload :Error, 'rims/error'
  autoload :GDBM_KeyValueStore, 'rims/gdbm_kvs'
  autoload :GlobalDB, 'rims/db'
  autoload :Hash_KeyValueStore, 'rims/hash_kvs'
  autoload :KeyValueStore, 'rims/kvs'
  autoload :MailFolder, 'rims/mail_store'
  autoload :MailStore, 'rims/mail_store'
  autoload :MailStorePool, 'rims/mail_store'
  autoload :MailboxDB, 'rims/db'
  autoload :MessageDB, 'rims/db'
  autoload :MessageSetSyntaxError, 'rims/error'
  autoload :Protocol, 'rims/protocol'
  autoload :ProtocolError, 'rims/error'
  autoload :Server, 'rims/server'
  autoload :SyntaxError, 'rims/error'
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
