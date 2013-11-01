# -*- coding: utf-8 -*-

require "rims/version"

module RIMS
  autoload :GDBM_KeyValueStore, 'rims/gdbm_kv'
  autoload :GlobalDB, 'rims/db'
  autoload :KeyValueStore, 'rims/kv'
  autoload :MailFolder, 'rims/mail_store'
  autoload :MailStore, 'rims/mail_store'
  autoload :MailStorePool, 'rims/mail_store'
  autoload :MailboxDB, 'rims/db'
  autoload :MessageDB, 'rims/db'
  autoload :Protocol, 'rims/protocol'
  autoload :ProtocolDecoder, 'rims/protocol'
  autoload :Server, 'rims/server'
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
