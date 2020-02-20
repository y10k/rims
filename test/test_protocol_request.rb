# -*- coding: utf-8 -*-

require 'logger'
require 'rims'
require 'stringio'
require 'test/unit'

module RIMS::Test
  class ProtocolRequestReaderTest < Test::Unit::TestCase
    def setup
      @input = StringIO.new('', 'r')
      @output = StringIO.new('', 'w')
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL
      @reader = RIMS::Protocol::RequestReader.new(@input, @output, @logger)
    end

    def test_scan_line
      assert_equal([], @reader.scan_line(''))
      assert_equal(%w[ abcd CAPABILITY ], @reader.scan_line('abcd CAPABILITY'))
      assert_equal(%w[ abcd OK CAPABILITY completed ], @reader.scan_line('abcd OK CAPABILITY completed'))
      assert_equal(%w[ * CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4 ], @reader.scan_line('* CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4'))
      assert_equal(%w[ * 172 EXISTS ], @reader.scan_line('* 172 EXISTS'))
      assert_equal([ '*', 'OK', '['.intern, 'UNSEEN', '12', ']'.intern, 'Message', '12', 'is', 'first', 'unseen' ],
                   @reader.scan_line('* OK [UNSEEN 12] Message 12 is first unseen'))
      assert_equal([ '*', 'FLAGS', '('.intern, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft', ')'.intern ],
                   @reader.scan_line('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)'))
      assert_equal([ '*', 'OK', '['.intern, 'PERMANENTFLAGS', '('.intern, '\Deleted', '\Seen', '\*', ')'.intern, ']'.intern, 'Limited' ],
                   @reader.scan_line('* OK [PERMANENTFLAGS (\Deleted \Seen \*)] Limited'))
      assert_equal([ 'A82', 'LIST', '', '*' ], @reader.scan_line('A82 LIST "" *'))
      assert_equal([ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, '/', 'foo' ], @reader.scan_line('* LIST (\Noselect) "/" foo',))
      assert_equal([ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, '/', 'foo [bar] (baz)' ],
                   @reader.scan_line('* LIST (\Noselect) "/" "foo [bar] (baz)"'))
      assert_equal([ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, :NIL, '' ], @reader.scan_line('* LIST (\Noselect) NIL ""'))
      assert_equal([ 'A654', 'FETCH', '2:4',
                     '('.intern,
                     [ :body, RIMS::Protocol.body(symbol: 'BODY', section: '') ],
                     ')'.intern
                   ],
                   @reader.scan_line('A654 FETCH 2:4 (BODY[])'))

      assert_equal('', @output.string)
    end

    def test_scan_line_string_literal
      literal = <<-'EOF'
Date: Mon, 7 Feb 1994 21:52:25 -0800 (PST)
From: Fred Foobar <foobar@Blurdybloop.COM>
Subject: afternoon meeting
To: mooch@owatagu.siam.edu
Message-Id: <B27397-0100000@Blurdybloop.COM>
MIME-Version: 1.0
Content-Type: TEXT/PLAIN; CHARSET=US-ASCII

Hello Joe, do you think we can meet at 3:30 tomorrow?
      EOF

      line = 'A003 APPEND saved-messages (\Seen) ' + "{#{literal.bytesize}}"
      @input.string = literal + "\r\n"

      assert_equal([ 'A003', 'APPEND', 'saved-messages', '('.intern, '\Seen', ')'.intern, literal ], @reader.scan_line(line))
      assert_equal('', @input.read)

      cmd_cont_req = @output.string.each_line
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_raise(StopIteration) { cmd_cont_req.next }
    end

    def test_read_line
      assert_nil(@reader.read_line)

      @input.string = "\n"
      assert_equal([], @reader.read_line)

      @input.string = "abcd CAPABILITY\n"
      assert_equal(%w[ abcd CAPABILITY ], @reader.read_line)

      @input.string = "abcd OK CAPABILITY completed\n"
      assert_equal(%w[ abcd OK CAPABILITY completed ], @reader.read_line)

      @input.string = "* CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4\n"
      assert_equal(%w[ * CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4 ], @reader.read_line)

      @input.string = "* 172 EXISTS\n"
      assert_equal(%w[ * 172 EXISTS ], @reader.read_line)

      @input.string = "* OK [UNSEEN 12] Message 12 is first unseen\n"
      assert_equal([ '*', 'OK', '['.intern, 'UNSEEN', '12', ']'.intern, 'Message', '12', 'is', 'first', 'unseen', ], @reader.read_line)

      @input.string = "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\n"
      assert_equal([ '*', 'FLAGS', '('.intern, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft', ')'.intern ], @reader.read_line)

      @input.string = "* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited\n"
      assert_equal([ '*', 'OK',
                     '['.intern, 'PERMANENTFLAGS', '('.intern, '\Deleted', '\Seen', '\*', ')'.intern, ']'.intern,
                     'Limited'
                   ], @reader.read_line)

      @input.string = "A82 LIST \"\" *\n"
      assert_equal([ 'A82', 'LIST', '', '*' ], @reader.read_line)

      @input.string = "* LIST (\\Noselect) \"/\" foo\n"
      assert_equal([ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, '/', 'foo' ], @reader.read_line)

      @input.string = "* LIST (\\Noselect) \"/\" \"foo [bar] (baz)\""
      assert_equal([ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, '/', 'foo [bar] (baz)' ], @reader.read_line)

      @input.string = '* LIST (\Noselect) NIL ""'
      assert_equal([ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, :NIL, '' ], @reader.read_line)

      @input.string = "A654 FETCH 2:4 (BODY[])\n"
      assert_equal([ 'A654', 'FETCH', '2:4',
                     '('.intern,
                     [ :body, RIMS::Protocol.body(symbol: 'BODY', section: '') ],
                     ')'.intern
                   ],
                   @reader.read_line)

      assert_equal('', @output.string)
    end

    def test_read_line_string_literal
      literal = <<-'EOF'
Date: Mon, 7 Feb 1994 21:52:25 -0800 (PST)
From: Fred Foobar <foobar@Blurdybloop.COM>
Subject: afternoon meeting
To: mooch@owatagu.siam.edu
Message-Id: <B27397-0100000@Blurdybloop.COM>
MIME-Version: 1.0
Content-Type: TEXT/PLAIN; CHARSET=US-ASCII

Hello Joe, do you think we can meet at 3:30 tomorrow?
      EOF

      @input.string = "A003 APPEND saved-messages (\\Seen) {#{literal.bytesize}}\n" + literal + "\n"
      assert_equal([ 'A003', 'APPEND', 'saved-messages', '('.intern, '\Seen', ')'.intern, literal ], @reader.read_line)
      assert_equal('', @input.read)

      cmd_cont_req = @output.string.each_line
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_raise(StopIteration) { cmd_cont_req.next }
    end

    def test_read_line_string_literal_multi
      literal1 = <<-'EOF'
Date: Mon, 7 Feb 1994 21:52:25 -0800 (PST)
From: Fred Foobar <foobar@Blurdybloop.COM>
Subject: afternoon meeting
To: mooch@owatagu.siam.edu
Message-Id: <B27397-0100000@Blurdybloop.COM>
MIME-Version: 1.0
Content-Type: TEXT/PLAIN; CHARSET=US-ASCII
      EOF

      literal2 = <<-'EOF'
Hello Joe, do you think we can meet at 3:30 tomorrow?
      EOF

      @input.string = "* ({#{literal1.bytesize}}\n" + literal1 + " {#{literal2.bytesize}}\n" + literal2 + ")\n"
      assert_equal([ '*', '('.intern, literal1, literal2, ')'.intern ], @reader.read_line)
      assert_equal('', @input.read)

      cmd_cont_req = @output.string.each_line
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_raise(StopIteration) { cmd_cont_req.next }
    end

    def test_parse
      assert_equal([], @reader.parse([]))
      assert_equal(%w[ abcd CAPABILITY ], @reader.parse(%w[ abcd CAPABILITY ]))
      assert_equal(%w[ abcd OK CAPABILITY completed ], @reader.parse(%w[ abcd OK CAPABILITY completed ]))
      assert_equal([ '*', 'OK', [ :block, 'UNSEEN', '12' ], 'Message', '12', 'is', 'first', 'unseen' ],
                   @reader.parse([ '*', 'OK', '['.intern, 'UNSEEN', '12', ']'.intern, 'Message', '12', 'is', 'first', 'unseen' ]))
      assert_equal([ '*', 'FLAGS', [ :group,  '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ] ],
                   @reader.parse([ '*', 'FLAGS', '('.intern, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft', ')'.intern ]))
      assert_equal([ '*', 'OK', [ :block, 'PERMANENTFLAGS', [ :group, '\Deleted', '\Seen', '\*' ] ], 'Limited' ],
                   @reader.parse([ '*', 'OK', '['.intern, 'PERMANENTFLAGS', '('.intern, '\Deleted', '\Seen', '\*', ')'.intern, ']'.intern, 'Limited' ]))
      assert_equal([ '*', 'LIST', [ :group, '\Noselect' ], :NIL, '' ],
                   @reader.parse([ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, :NIL, '' ]))
      assert_equal([ 'A654', 'FETCH', '2:4',
                     [ :group,
                       [ :body,
                         RIMS::Protocol.body(symbol: 'BODY',
                                             section: '',
                                             section_list: [])
                       ]
                     ]
                   ],
                   @reader.parse([ 'A654', 'FETCH', '2:4',
                                   '('.intern,
                                   [ :body, RIMS::Protocol.body(symbol: 'BODY', section: '') ],
                                   ')'.intern
                                 ]))
      assert_equal([ 'A003', 'APPEND', 'saved-messages', "foo\nbody[]\nbar\n" ],
                   @reader.parse([ 'A003', 'APPEND', 'saved-messages', "foo\nbody[]\nbar\n" ]))

      error = assert_raise(RIMS::SyntaxError) { @reader.parse([ '*', 'OK', '['.intern, 'UNSEEN', '12' ]) }
      assert_match(/not found a terminator/, error.message)

      error = assert_raise(RIMS::SyntaxError) { @reader.parse([ '*', 'LIST', '('.intern, '\Noselect' ]) }
      assert_match(/not found a terminator/, error.message)

      assert_equal('', @output.string)
    end

    def test_read_command
      assert_nil(@reader.read_command)

      @input.string = "\n"
      assert_nil(@reader.read_command)

      @input.string = " \t\n"
      assert_nil(@reader.read_command)

      @input.string = "abcd CAPABILITY\n"
      assert_equal(%w[ abcd CAPABILITY ], @reader.read_command)

      @input.string = "\n \n\t\nabcd CAPABILITY\n"
      assert_equal(%w[ abcd CAPABILITY ], @reader.read_command)

      @input.string = "abcd OK CAPABILITY completed\n"
      assert_equal(%w[ abcd OK CAPABILITY completed ], @reader.read_command)

      @input.string = "A003 STORE 2:4 +FLAGS (\\Deleted)\n"
      assert_equal([ 'A003', 'STORE', '2:4', '+FLAGS', [ :group, '\Deleted' ] ], @reader.read_command)

      @input.string = "abcd SEARCH (OR (FROM foo) (FROM bar))\n"
      assert_equal([ 'abcd', 'SEARCH',
                     [ :group,
                       'OR',
                       [ :group, 'FROM', 'foo' ],
                       [ :group, 'FROM', 'bar' ]
                     ]
                   ],
                   @reader.read_command)

      @input.string = "abcd SEARCH SUBJECT \"NIL\"\n"
      assert_equal([ 'abcd', 'SEARCH', 'SUBJECT', 'NIL'  ], @reader.read_command)

      @input.string = "abcd SEARCH SUBJECT \"(\"\n"
      assert_equal([ 'abcd', 'SEARCH', 'SUBJECT', '('  ], @reader.read_command)

      @input.string = "abcd SEARCH SUBJECT \")\"\n"
      assert_equal([ 'abcd', 'SEARCH', 'SUBJECT', ')'  ], @reader.read_command)

      @input.string = "abcd SEARCH SUBJECT \"[\"\n"
      assert_equal([ 'abcd', 'SEARCH', 'SUBJECT', '['  ], @reader.read_command)

      @input.string = "abcd SEARCH SUBJECT \"]\"\n"
      assert_equal([ 'abcd', 'SEARCH', 'SUBJECT', ']'  ], @reader.read_command)

      @input.string = "A654 FETCH 2:4 (BODY)\n"
      assert_equal([ 'A654', 'FETCH', '2:4', [ :group, 'BODY' ] ], @reader.read_command)

      @input.string = "A654 FETCH 2:4 (BODY[])\n"
      assert_equal([ 'A654', 'FETCH', '2:4', [
                       :group, [
                         :body,
                         RIMS::Protocol.body(symbol: 'BODY',
                                             section: '',
                                             section_list: [])
                       ]
                     ]
                   ], @reader.read_command)

      @input.string = "A654 FETCH 2:4 (FLAGS BODY.PEEK[HEADER.FIELDS (DATE FROM)]<0.1500>)\n"
      assert_equal([ 'A654', 'FETCH', '2:4',
                     [ :group,
                       'FLAGS',
                       [ :body,
                         RIMS::Protocol.body(symbol: 'BODY',
                                             option: 'PEEK',
                                             section: 'HEADER.FIELDS (DATE FROM)',
                                             section_list: [ 'HEADER.FIELDS', [ :group, 'DATE', 'FROM' ] ],
                                             partial_origin: 0,
                                             partial_size: 1500)
                       ]
                     ]
                   ],
                   @reader.read_command)

      @input.string = "A654 APPEND saved-messages \"body[]\"\n"
      assert_equal([ 'A654', 'APPEND', 'saved-messages', 'body[]' ], @reader.read_command)

      assert_equal('', @output.string)

      literal = <<-'EOF'
Date: Mon, 7 Feb 1994 21:52:25 -0800 (PST)
From: Fred Foobar <foobar@Blurdybloop.COM>
Subject: afternoon meeting
To: mooch@owatagu.siam.edu
Message-Id: <B27397-0100000@Blurdybloop.COM>
MIME-Version: 1.0
Content-Type: TEXT/PLAIN; CHARSET=US-ASCII

Hello Joe, do you think we can meet at 3:30 tomorrow?
      EOF

      @input.string = "A003 APPEND saved-messages (\\Seen) {#{literal.bytesize}}\n" + literal + "\n"
      @output.string = ''
      assert_equal([ 'A003', 'APPEND', 'saved-messages', [ :group, '\Seen' ], literal ], @reader.read_command)

      cmd_cont_req = @output.string.each_line
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_raise(StopIteration) { cmd_cont_req.next }


      literal2 = <<-'EOF'
Subject: parse test

body[]
      EOF

      @input.string = "A004 APPEND saved-messages {#{literal2.bytesize}}\n" + literal2 + "\n"
      @output.string = ''
      assert_equal([ 'A004', 'APPEND', 'saved-messages', literal2 ], @reader.read_command)

      cmd_cont_req = @output.string.each_line
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_raise(StopIteration) { cmd_cont_req.next }

      literal3 = 'body[]'

      @input.string = "A005 APPEND saved-messages {#{literal3.bytesize}}\n" + literal3 + "\n"
      @output.string = ''
      assert_equal([ 'A005', 'APPEND', 'saved-messages', literal3 ], @reader.read_command)

      cmd_cont_req = @output.string.each_line
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_raise(StopIteration) { cmd_cont_req.next }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
