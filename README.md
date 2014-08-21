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
</dl>

## Mailbox Data

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
