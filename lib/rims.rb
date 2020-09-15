# -*- coding: utf-8 -*-

require "rims/version"

autoload :OpenSSL, 'openssl'

module RIMS
  autoload :Authentication,           'rims/auth'
  autoload :Checksum_KeyValueStore,   'rims/cksum_kvs'
  autoload :Cmd,                      'rims/cmd'
  autoload :CommandSizeTooLargeError, 'rims/protocol'
  autoload :DB,                       'rims/db'
  autoload :Dump,                     'rims/dump'
  autoload :DumpReader,               'rims/dump'
  autoload :DumpWriter,               'rims/dump'
  autoload :Error,                    'rims/error'
  autoload :GDBM_KeyValueStore,       'rims/gdbm_kvs'
  autoload :Hash_KeyValueStore,       'rims/hash_kvs'
  autoload :IllegalLockError,         'rims/lock'
  autoload :KeyValueStore,            'rims/kvs'
  autoload :LineTooLongError,         'rims/protocol'
  autoload :LiteralSizeTooLargeError, 'rims/protocol'
  autoload :LockError,                'rims/lock'
  autoload :MailFolder,               'rims/mail_store'
  autoload :MailStore,                'rims/mail_store'
  autoload :MessageSetSyntaxError,    'rims/protocol'
  autoload :Password,                 'rims/passwd'
  autoload :Protocol,                 'rims/protocol'
  autoload :ProtocolError,            'rims/protocol'
  autoload :RFC822,                   'rims/rfc822'
  autoload :ReadLockError,            'rims/lock'
  autoload :ReadLockTimeoutError,     'rims/lock'
  autoload :ReadSizeError,            'rims/protocol'
  autoload :ReadWriteLock,            'rims/lock'
  autoload :RecoverableReadSizeError, 'rims/protocol'
  autoload :ServerResponseChannel,    'rims/channel'
  autoload :Service,                  'rims/service'
  autoload :SimpleText_DumpReader,    'rims/simple_dump'
  autoload :SimpleText_DumpWriter,    'rims/simple_dump'
  autoload :SyntaxError,              'rims/protocol'
  autoload :Test,                     'rims/test'
  autoload :WriteLockError,           'rims/lock'
  autoload :WriteLockTimeoutError,    'rims/lock'
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
