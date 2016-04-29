# RIMS

RIMS is Ruby IMap Server.

## Installation

Add this line to your application's Gemfile:

    gem 'rims', git: 'git://github.com/y10k/rims.git'

Execute to install your local directory:

    $ bundle install --path=vendor

Or execute to install your gem home:

    $ bundle install

## Simple Usage

Type following to show usage.

    $ bundle exec rims help
    usage: rims command options
    
    commands:
        help               Show this message.
        version            Show software version.
        server             Run IMAP server.
        daemon             Daemon start/stop/status tool.
        post-mail          Post mail to any user.
        imap-append        Append message to IMAP mailbox.
        mbox-dirty-flag    Show/enable/disable dirty flag of mailbox database.
        unique-user-id     Show unique user ID from username.
        show-user-mbox     Show the path in which user's mailbox data is stored.
    
    command help options:
        -h, --help

## Tutorial

Something to need for RIMS setup are following:

* IP address of your server to run RIMS.
* At least one pair of username and password.
* Your e-mail client that can use IMAP.

In this tutorial, IP address is `192.168.56.101`, username is `foo`,
and password is `bar`.

### First step

Let's try to start RIMS. Type following on your console. And some
messages are shown at console.

    $ bundle exec rims server -u foo -w bar
    I, [2015-01-24T21:02:37.030415 #24475]  INFO -- : start server.
    I, [2015-01-24T21:02:37.035052 #24475]  INFO -- : open socket: 0.0.0.0:1430
    I, [2015-01-24T21:02:37.036329 #24475]  INFO -- : opened: [AF_INET][1430][0.0.0.0][0.0.0.0]
    I, [2015-01-24T21:02:37.036569 #24475]  INFO -- : process ID: 24475
    I, [2015-01-24T21:02:37.037105 #24475]  INFO -- : process privilege user: toki(1000)
    I, [2015-01-24T21:02:37.037401 #24475]  INFO -- : process privilege group: toki(1000)

Add e-mail account to your e-mail client:

* Username is `foo`.
* IMAP server is `192.168.56.101`. This may be replaced to your server
  hostname or IP address.
* IMAP port number is `1430`. This is default of RIMS.
* IMAP authentication password is `bar`.

If setup is success, empty mailbox named INBOX is shown at new mail
account of your e-mail client.

Last, type Ctrl+C on your console to stop server.

### Configuration file

Password at command line parameter is insecure because password is
peeped from another user using `ps aux`. Username and password should
be written at configuration file.

RIMS configuration file format is YAML. Type following in file of
`config.yml` and save.

    user_list:
      - { user: foo, pass: bar }

And start RIMS with `-f config.yml` option.

    $ bundle exec rims server -f config.yml
    I, [2015-01-26T23:20:24.573462 #6106]  INFO -- : start server.
    I, [2015-01-26T23:20:24.574507 #6106]  INFO -- : open socket: 0.0.0.0:1430
    I, [2015-01-26T23:20:24.581892 #6106]  INFO -- : opened: [AF_INET][1430][0.0.0.0][0.0.0.0]
    I, [2015-01-26T23:20:24.582044 #6106]  INFO -- : process ID: 6106
    I, [2015-01-26T23:20:24.596335 #6106]  INFO -- : process privilege user: toki(1000)
    I, [2015-01-26T23:20:24.596985 #6106]  INFO -- : process privilege group: toki(1000)

If setup is success, empty mailbox named INBOX is shown at mail
account of your e-mail client.

Last, type Ctrl+C on your console to stop server.

### Mail delivery to mailbox

In this section, the way that you deliver mail to mailbox on RIMS is
described. Prepare a sample mail text file that is picked from your
e-mail client. The sample mail file is named `mail.txt` on description
of this section.

Simple way is that you use IMAP APPEND command. `rims` tool has IMAP
APPEND command. Type following on your console.

    $ bundle exec rims imap-append -v -n 192.168.56.101 -o 1430 -u foo -w bar mail.txt
    store flags: ()
    server greeting: OK RIMS vX.Y.Z IMAP4rev1 service ready.
    server capability: IMAP4REV1 UIDPLUS AUTH=PLAIN AUTH=CRAM-MD5
    login: OK LOGIN completed
    append: OK  APPEND completed

The option of `-v` is verbose mode. If you don't need display
information, no verbose option exists. If mail delivery is success,
you will see that message appears in INBOX on your e-mail client.

The advantage of IMAP APPEND is to be able to use it by any IMAP mail
server as well as RIMS. The disadvantage of IMAP APPEND is that it
requires your password. This may be insecure.

Special user is defined to deliver mail to any user's mailbox on RIMS.
By special user, it is possible to deliver mail without your password.
The disadvantage of special user is that it can be used only in RIMS.

At first, you prepare a special user to deliver mail. Type following
in configuration file. And start RIMS.

    user_list:
      - { user: foo, pass: bar }
      - { user: "#postman", pass: "#postman" }

And type following on your console.

    $ bundle exec rims post-mail -v -n 192.168.56.101 -o 1430 -w '#postman' foo mail.txt
    store flags: ()
    server greeting: OK RIMS vX.Y.Z IMAP4rev1 service ready.
    server capability: IMAP4REV1 UIDPLUS AUTH=PLAIN AUTH=CRAM-MD5
    login: OK LOGIN completed
    append: OK  APPEND completed

The option of `-v` is verbose mode. If you don't need display
information, no verbose option exists. If mail delivery is success,
you will see that message appears in INBOX on your e-mail client.

### IMAP well known port and server process privilege

Default port number of RIMS is 1430. IMAP protocol well known port
number is 143. If RIMS opens server socket with 143 port, it needs to
be root user process at unix. But RIMS doesn't need to be root user
process as IMAP server.

To open server socket with well known 143 port at RIMS:

1. RIMS starts at root user.
2. RIMS opens server socket with 143 port by root user privilege.
3. RIMS calls setuid(2). And privilege of process is changed from root
   user to another.
4. RIMS starts IMAP server with another's process privilege.

For example, port number is `imap2` (it is service name of well known
port of 143), process user privilege is `toki` (uid 1000), and process
group privilege is `toki` (gid 1000). Type following in configuration
file.

    user_list:
      - { user: foo, pass: bar }
      - { user: "#postman", pass: "#postman" }
    imap_port: imap2
    process_privilege_user: toki
    process_privilege_group: toki

And type following on your console.

    $ sudo bundle exec rims server -f config.yml
    [sudo] password for toki: 
    I, [2015-01-31T21:32:30.069848 #9381]  INFO -- : start server.
    I, [2015-01-31T21:32:30.070068 #9381]  INFO -- : open socket: 0.0.0.0:imap2
    I, [2015-01-31T21:32:30.070374 #9381]  INFO -- : opened: [AF_INET][143][0.0.0.0][0.0.0.0]
    I, [2015-01-31T21:32:30.070559 #9381]  INFO -- : process ID: 9381
    I, [2015-01-31T21:32:30.070699 #9381]  INFO -- : process privilege user: toki(1000)
    I, [2015-01-31T21:32:30.070875 #9381]  INFO -- : process privilege group: toki(1000)

### Daemon

If RIMS server is started from console terminal, RIMS server process
is terminated on closing its console terminal.  At unix, server
process has to be started as daemon process for the server to keep
running its service.

RIMS server can start as daemon process. Type following on your
console.

    $ sudo bundle exec rims daemon start -f config.yml

`sudo` is required for well known 143 port (see previous section).
Daemon process is started quietly and prompt of console terminal is
returned immediately. But daemon process is running at background.
To see background daemon process, type following on your console.

    $ ps -elf | grep rims
    5 S root      3191  1720  0  80   0 - 23026 wait   21:10 ?        00:00:00 ruby /home/toki/rims/vendor/ruby/2.2.0/bin/rims daemon start -f config.yml
    5 S toki      3194  3191  0  80   0 - 26382 inet_c 21:10 ?        00:00:00 ruby /home/toki/rims/vendor/ruby/2.2.0/bin/rims daemon start -f config.yml

RIMS daemon is two processes. 1st root process is controller process.
2nd process that isn't root is server process. RIMS daemon doesn't
display messages and errors at console. You should see log files to
verify normal running of RIMS daemon.

To see log of controller process, watch syslog at system directory.
Type following on your console.

    $ tail -f /var/log/syslog
    Feb  1 21:10:00 vbox-linux rims-daemon[3191]: start daemon.
    Feb  1 21:10:00 vbox-linux rims-daemon[3191]: run server process: 3194

To see log of server process, watch imap.log at local directory. Type
following on your console.

    $ tail -f imap.log
    I, [2015-02-01T21:10:00.989859 #3194]  INFO -- : start server.
    I, [2015-02-01T21:10:00.990084 #3194]  INFO -- : open socket: 0.0.0.0:imap2
    I, [2015-02-01T21:10:00.990989 #3194]  INFO -- : opened: [AF_INET][143][0.0.0.0][0.0.0.0]
    I, [2015-02-01T21:10:00.991393 #3194]  INFO -- : process ID: 3194
    I, [2015-02-01T21:10:00.991615 #3194]  INFO -- : process privilege user: toki(1000)
    I, [2015-02-01T21:10:00.991703 #3194]  INFO -- : process privilege group: toki(1000)

RIMS daemon process can be controlled from command line tool. Defined
operations are start, stop, restart and status. Start operation is
already described.

Stop operation:

    $ sudo bundle exec rims daemon stop -f config.yml

Restart operation:

    $ sudo bundle exec rims daemon restart -f config.yml

Status operation:

    $ sudo bundle exec rims daemon status -f config.yml
    daemon is running.

    $ sudo bundle exec rims daemon status -f config.yml
    daemon is stopped.

## Server Configuration

Server options on start may be described at config.yml file.
Config.yml is a YAML format file and its contents are explained
at later.

To start server with config.yml file, type following.

    $ bundle exec rims server -f a_server_directory/config.yml

### Config.yml Parameters

<dl>
  <dt>base_dir</dt>
  <dd>This parameter describes a base directory of server. Mailbox
  data is located at inside of base directory. Default is a parent
  directory of config.yml file. Explicit description of this parameter
  is interpreted as a relative path from a parent directory of
  config.yml file.</dd>

  <dt>log_stdout</dt>
  <dd>This parameter describes a severity level of logging messages
  that is written to standard output.  See description of Logger class
  for more detail of logging. This parameter is one value selected
  from DEBUG, INFO, WARN, ERROR or FATAL. If QUIET value is chosen,
  standard output logging is disabled. Default is INFO. The danger is
  that password may be embedded in message on user authentication in
  DEBUG logging level.</dd>

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

  <dt>imap_host</dt>
  <dd>This parameter describes hostname or IP address of a server
  socket to listen(2) and accept(2). Default is 0.0.0.0.</dd>

  <dt>imap_port</dt>
  <dd>This parameter describes IP port number or service name of a
  server socket to listen(2) and accept(2). Default is 1430.</dd>

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

    $ bundle exec rims unique-user-id foo
    2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae 

First two characters of unique user ID is used as a bucket directory.
Unique user ID substring from 3rd character to last exists as a user
directory under the bucket directory.  Shortcut tool to search a two
level directory of a user under a base directory exists.  For example,
type following to display a "foo" user's directory.

    $ bundle exec rims show-user-mbox a_base_directory foo
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

    $ bundle exec rims debug-dump-kvs --dump-size --no-dump-value a_base_directory/mailbox.2/2c/26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae/message
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

    $ bundle exec rims debug-dump-kvs a_base_directory/mailbox.2/2c/26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae/meta
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

    $ bundle exec rims debug-dump-kvs a_base_directory/mailbox.2/2c/26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae/mailbox_1
    "2": 1 bytes: "1"
    "5": 1 bytes: "4"
    "1": 1 bytes: "0"
    "4": 1 bytes: "3"
    "3": 1 bytes: "2"

## History

* v0.1.0 (Latest version)
    - Login authentication mechanisms.
    - Multi-user mailbox.
    - Command utility to deliver mail to mailbox.
    - Server process privilege separated from root user.
    - UIDPLUS extension. Contributed by Joe Yates, thanks.
    - Daemon tool.
    - Fixed some bad response of search command.
    - Tutorial is written.
* v0.0.4
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

## Next Tasks

* Users defined by LDAP.
* Fixed some connection errors at windows mail client.
* Autologout timer.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
