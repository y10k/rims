# RIMS

RIMS is Ruby IMap Server.

## Installation

Add this line to your application's Gemfile:

    gem 'rims', git: 'git://github.com/y10k/rims.git', tag: 'v0.0.4'

And then execute:

    $ bundle

## Simple Usage

Type following to show usage.

    $ rims

To start IMAP server, type following and read usage.

    $ rims server --help

To append messages to IMAP mailbox, type following and read usage.

    $ rims imap-append --help

## Server Configuration

Server options on start may be described at config.yml file.
Config.yml is a YAML format file and its contents are explained
at later.

To start server with config.yml file, type following.

    $ rims server -f a_server_directory/config.yml

### Config.yml Parameters

<dl>
  <dt>base_dir</dt>
  <dd>This parameter describes a base directory of server. Mailbox
  data is located at inside of base directory. Default is a parent
  directory of config.yml file. Explicit description of this parameter
  is interpreted as a relative path from a parent directory of
  config.yml file.</dd>

  <dt>log_file</dt>
  <dd>This parameter describes a path of log file. Default is
  "imap.log" under the base_dir. Explicit description of this
  parameter is interpreted as a relative path from a base_dir.</dd>

  <dt>log_level</dt>
  <dd>This parameter describes a severity level of logging
  messages. See description of Logger class for more detail of
  logging. This parameter is one value selected from DEBUG, INFO,
  WARN, ERROR or FATAL. Default is INFO. The danger is that password
  may be embedded in message on user authentication in DEBUG logging
  level.</dd>

  <dt>log_shift_age</dt>
  <dd>This parameter describes a number of old rotated log files to
  keep or periodical log rotation. Decimal number is interpreted as a
  number of files to keep. Periodical log rotation is one value
  selected from daily, weekly or monthly. Default is none. See
  description of Logger.new class method for more detail of log
  rotation.</dd>

  <dt>log_shift_size</dt>
  <dd>This parameter describes a maximum log file size on log file
  rotation. Default is none. See description of Logger.new class
  method for more detail of log rotation.</dd>

  <dt>key_value_store_type</dt>
  <dd>This parameter describes a type of key-value store. Key-value
  store is used to save a mailbox data. This parameter is only one
  value of GDBM, and it is default value.</dd>

  <dt>use_key_value_store_checksum</dt>
  <dd>This parameter decides whether to use checksum. This parameter
  is boolean, true or false. If this parameter is true, a mailbox data
  is saved with its checksum to an entry of key-value store, and a
  checksum is checked on loading a mailbox data from an entry of
  key-value store. Default is true.</dd>

  <dt>hostname</dt>
  <dd>This parameter describes a hostname of server. Default is the
  name displayed by hostname(1) command.</dd>

  <dt>username</dt>
  <dd>This parameter describes a name of mailbox user. This parameter
  and the next password parameter are the pair. If there are two or
  many users, user_list parameter should be used instead of this
  parameter. At least one user is need to start a server.</dd>

  <dt>password</dt>
  <dd>This parameter describes a password of mailbox user. This
  parameter and the previous username parameter are the pair. If there
  are two or many users, user_list parameter should be used instead of
  this parameter. At least one user is need to start a server.</dd>

  <dt>user_list</dt>
  <dd>This parameter describes many users of mailbox. The value of
  this parameter is a sequence of maps. A map in the sequence should
  have two entries, the two entries are user and pass. user entry
  describes name of a user. pass entry describes password of a
  user. At least one user is need to start a server.</dd>

  <dt>ip_addr</dt>
  <dd>This parameter describes IP address of a server socket to
  listen(2) and accept(2). Default is 0.0.0.0.</dd>

  <dt>ip_port</dt>
  <dd>This parameter describes IP port of a server socket to listen(2)
  and accept(2). Default is 1430.</dd>

  <dt>mail_delivery_user</dt>
  <dd>This parameter describes a special user to deliver mail to any
  user. Password definition of this special user is same to a normal
  user. Default is "#postman".</dd>

  <dt>process_privilege_user</dt>
  <dd>This parameter describes a privilege user name or ID for server
  process.  When server process starts on root user, setuid(2) is
  called and server process privilege user is changed from root user
  to this parameter user.  Default is 65534 (typical user ID of
  nobody) and should be changed.</dd>

  <dt>process_privilege_group</dt>
  <dd>This parameter describes a privilege group name or ID for server
  process.  When server process starts on root user, setgid(2) is
  called and server process privilege group is changed from root group
  to this parameter group.  Default is 65534 (typical group ID of
  nogroup) and should be changed.</dd>
</dl>

## Mailbox Data

Mailbox data exists under the base directory. Next picture is a
overview of mailbox data filesystem under the base directory.

    a_base_directory
    |
    +-- mailbox.2/
        |
        +-- 2c/
            |
            +-- 26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae/
                |
                +-- message
                |
                +-- meta
                |
                +-- mailbox_1
                |
                +-- mailbox_2
                |
				...

There is a MAILBOX\_DATA\_STRUCTURE\_VERSION directory under first
inside of the base directory.  When mailbox data structure will be
changed in future, MAILBOX\_DATA\_STRUCTURE\_VERSION directory will be
changed too.  Now latest version is "mailbox.2".

There are user directories under the MAILBOX\_DATA\_STRUCTURE\_VERSION
directory.  A user is identified by unique user ID.  Unique user ID is
a SHA256 HEX digest of a username.  For example, type following to
display a "foo" user's unique user ID.

    $ rims unique-user-id foo
    2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae 

First two characters of unique user ID is used as a bucket directory.
Unique user ID substring from 3rd character to last exists as a user
directory under the bucket directory.  Shortcut tool to search a two
level directory of a user under a base directory exists.  For example,
type following to display a "foo" user's directory.

    $ rims show-user-mbox a_base_directory foo
    a_base_directory/mailbox.2/2c/26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae

There are three types of files under the user directory.  Three types
are message, meta and mailbox.  Each file is key-value store.  Only
one type of key-value store is available now, it is GDBM.  A GDBM
key-value store file has a filename suffix, the suffix is ".gdbm".
Mailbox data does not depend on a specific type of key-value store.

### Message key-value store

Message key-value store file preserves all messages of a user.  Per
one user, only one file exists about this file type.  Contents of
message key-value store is simple.  A key is a message ID, and a value
is message text.  A message ID is a unique number of a message in RIMS
internal.  For example, type following to see overview of contents at
a message key-value store.

    $ rims debug-dump-kvs --dump-size --no-dump-value a_base_directory/mailbox.2/2c/26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae/message
    "2": 21938 bytes
    "1": 126014 bytes
    "4": 22928 bytes
    "0": 6326 bytes
    "3": 65168 bytes

### Meta key-value store

Meta key-value store file preserves all meta data of message and
folders.  Per one user, only one file exists about this file type.
Contents of meta key-value store is complex, and only outline of
content is described here.

<dl>
  <dt>dirty</dt>
  <dd>Dirty flag. If enabled, this flag exists. If disabled, this flag
  doesn't exists. This flag will be enabled on updating mailbox
  data.</dd>

  <dt>cnum</dt>
  <dd>A change number of mailbox data. If mailbox data is modified,
  this number is increased.</dd>

  <dt>msg_id</dt>
  <dd>The next number of message ID. Message ID is unique number of
  message in RIMS internal.</dd>

  <dt>uidvalidity</dt>
  <dd>The next number of uidvalidity. Uidvalidity is unique number of
  mailbox in IMAP.</dd>

  <dt>mbox_set</dt>
  <dd>Mailbox set of a user.</dd>

  <dt>mbox_id2name-#</dt>
  <dd>Mapping from mailbox ID to mailbox name.</dd>

  <dt>mbox_name2id-#</dt>
  <dd>Mapping from mailbox name to mailbox ID.</dd>

  <dt>mbox_id2uid-#</dt>
  <dd>The next uid at a mailbox. Uid is unique number of message at a
  mailbox in IMAP.</dd>

  <dt>mbox_id2msgnum-#</dt>
  <dd>Number of messages at a mailbox.</dd>

  <dt>mbox_id2flagnum-#-#</dt>
  <dd>Number of flags at a mailbox.</dd>

  <dt>msg_id2date-#</dt>
  <dd>Mapping from message ID to internal date of a message. Internal
  date is a message attribute in IMAP.</dd>

  <dt>msg_id2flag-#</dt>
  <dd>Set of flags at a message.</dd>

  <dt>msg_id2mbox-#</dt>
  <dd>Mapping from message ID to mailbox's uid.</dd>
</dl>

For example, type following to see overview of contents at a meta key-value store.

    $ rims debug-dump-kvs a_base_directory/mailbox.2/2c/26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae/meta
    "msg_id2mbox-3": 25 bytes: {1=>#<Set: {4}>}
    "msg_id2date-2": 49 bytes: 2013-11-08 13:34:10 +0900
    "mbox_id2uid-1": 1 bytes: "6"
    "msg_id2mbox-1": 25 bytes: {1=>#<Set: {2}>}
    "msg_id2flag-2": 6 bytes: "recent"
    "mbox_id2msgnum-1": 1 bytes: "5"
    "uidvalidity": 1 bytes: "2"
    "mbox_id2flagnum-1-recent": 1 bytes: "5"
    "msg_id2date-0": 49 bytes: 2013-11-08 06:47:50 +0900
    "cnum": 1 bytes: "6"
    "msg_id2date-4": 49 bytes: 2013-11-08 11:57:28 +0900
    "msg_id2mbox-2": 25 bytes: {1=>#<Set: {3}>}
    "mbox_set": 1 bytes: "1"
    "msg_id2flag-0": 6 bytes: "recent"
    "msg_id2flag-4": 6 bytes: "recent"
    "msg_id2date-1": 49 bytes: 2013-11-08 19:31:03 +0900
    "msg_id": 1 bytes: "5"
    "mbox_id2name-1": 5 bytes: "INBOX"
    "msg_id2mbox-0": 25 bytes: {1=>#<Set: {1}>}
    "mbox_name2id-INBOX": 1 bytes: "1"
    "msg_id2mbox-4": 25 bytes: {1=>#<Set: {5}>}
    "msg_id2flag-1": 6 bytes: "recent"
    "msg_id2date-3": 49 bytes: 2013-11-08 12:47:17 +0900
    "msg_id2flag-3": 6 bytes: "recent"

### Mailbox key-value store

Mailbox key-value store file preserves key-value pairs of uid and
message ID.  Per one user, plural files exist about this type of file
because plural mailboxes are allowed at one user.  Mailbox key-value
store filenames are "mailbox\_1", "mailbox\_2", ...  And 1,2,... are
mailbox ID.  Contents of mailbox key-value store is simple.  A key is
a uid, and a value is message ID.  A uid is a unique number of a
message in a mailbox in IMAP.  A message ID is a unique number of a
message in RIMS internal.  For example, type following to see overview
of contents at a mailbox key-value store.

    $ rims debug-dump-kvs a_base_directory/mailbox.2/2c/26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae/mailbox_1
    "2": 1 bytes: "1"
    "5": 1 bytes: "4"
    "1": 1 bytes: "0"
    "4": 1 bytes: "3"
    "3": 1 bytes: "2"

## History

* v0.0.4 (Latest version)
    - Mail parser is replaced from mail gem to RIMS::RFC822 parser.
    - Optimization to fast search and fast fetch.
    - Strict e-mail address data at fetch envelope response.
    - Charset search.
    - Refactored unit test codes.
* v0.0.3
    - DB structure is changed and IMAP UID behavior will follow rules
      that is described at RFC. Incompatible mailbox data!
    - DB data checksum is added. mail data is verified with checksum
      at default.
    - data recovery process is added to mail data DB.
    - mbox-dirty-flag command is added to force recovery.
* v0.0.2
    - Fast error recovery on connection fatal error (ex. Errno::EPIPE).
    - Server log rotation.
    - debug-dump-kvs command.
    - Fine grain lock for one user multiple connection.
* v0.0.1
    - First release.

## Roadmap of development

* v0.0.5
    - Login authentication mechanisms.
    - Corresponding to multi-user mailbox. Incompatible mailbox data!
* v0.0.6
    - Fixed some connection errors at windows mail client.
    - Autologout timer.
    - Command utility to deliver mail to mailbox.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
