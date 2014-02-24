# RIMS

RIMS is Ruby IMap Server.

## Installation

Add this line to your application's Gemfile:

    source 'https://rubygems.org' # for dependency of RIMS
    gem 'rims', git: 'git://github.com/y10k/rims.git', tag: 'v0.0.1'

And then execute:

    $ bundle

## Usage

Type following to show usage.

    $ rims

To start IMAP server, type following and read usage.

    $ rims server --help

To append messages to IMAP mailbox, type following and read usage.

    $ rims imap-append --help

## Roadmap of development

* v0.0.1
    - Now version.
* v0.0.2
    - Fast error recovery on connection fatal error (ex. Errno::EPIPE).
    - Fine grain lock for one user multiple connection.
* v0.0.3
    - DB structure is changed and IMAP UID behavior will follow rules
      that is described at RFC. Incompatible mailbox data!
    - DB data checksum is added.
    - Recovery from broken DB.
* v0.0.4
    - Optimization to fast search and fast fetch.
    - Charset search.
    - Strict e-mail address data at fetch envelope response.
    - Login authentication mechanisms.
* v0.0.5
    - Corresponding to multi-user mailbox. Incompatible mailbox data!

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
