# RIMS

RIMS is Ruby IMap Server.

## Installation

Add this line to your application's Gemfile:

    gem 'rims', git: 'git://github.com/y10k/rims.git', tag: 'v0.0.4'

And then execute:

    $ bundle

## Usage

Type following to show usage.

    $ rims

To start IMAP server, type following and read usage.

    $ rims server --help

To append messages to IMAP mailbox, type following and read usage.

    $ rims imap-append --help

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
