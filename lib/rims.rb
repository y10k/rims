# -*- coding: utf-8 -*-

require "rims/version"

module RIMS
  autoload :Authentication, 'rims/auth'
  autoload :BufferedWriter, 'rims/server'
  autoload :Checksum_KeyValueStore, 'rims/cksum_kvs'
  autoload :Cmd, 'rims/cmd'
  autoload :Config, 'rims/server'
  autoload :DB, 'rims/db'
  autoload :Daemon, 'rims/daemon'
  autoload :Error, 'rims/error'
  autoload :GDBM_KeyValueStore, 'rims/gdbm_kvs'
  autoload :GlobalDB, 'rims/db'
  autoload :Hash_KeyValueStore, 'rims/hash_kvs'
  autoload :IllegalLockError, 'rims/lock'
  autoload :KeyValueStore, 'rims/kvs'
  autoload :LockError, 'rims/lock'
  autoload :MailFolder, 'rims/mail_store'
  autoload :MailStore, 'rims/mail_store'
  autoload :MailStoreHolder, 'rims/mail_store'
  autoload :MailboxDB, 'rims/db'
  autoload :MessageDB, 'rims/db'
  autoload :MessageSetSyntaxError, 'rims/protocol'
  autoload :Multiplexor, 'rims/server'
  autoload :ObjectPool, 'rims/pool'
  autoload :Password, 'rims/passwd'
  autoload :Protocol, 'rims/protocol'
  autoload :ProtocolError, 'rims/protocol'
  autoload :RFC822, 'rims/rfc822'
  autoload :ReadLockError, 'rims/lock'
  autoload :ReadLockTimeoutError, 'rims/lock'
  autoload :ReadWriteLock, 'rims/lock'
  autoload :Server, 'rims/server'
  autoload :SyntaxError, 'rims/protocol'
  autoload :Test, 'rims/test'
  autoload :WriteLockError, 'rims/lock'
  autoload :WriteLockTimeoutError, 'rims/lock'
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
