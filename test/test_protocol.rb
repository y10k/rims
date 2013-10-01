# -*- coding: utf-8 -*-

require 'logger'
require 'rims'
require 'stringio'
require 'test/unit'

module RIMS::Test
  class ProtocolTest < Test::Unit::TestCase
    def test_quote
      assert_equal('""', RIMS::Protocol.quote(''))
      assert_equal('"foo"', RIMS::Protocol.quote('foo'))
      assert_equal("{1}\r\n\"", RIMS::Protocol.quote('"'))
      assert_equal("{8}\r\nfoo\nbar\n", RIMS::Protocol.quote("foo\nbar\n"))
    end

    def test_compile_wildcard
      assert(RIMS::Protocol.compile_wildcard('xxx') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('xxx') !~ 'yyy')
      assert(RIMS::Protocol.compile_wildcard('x*') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('x*') !~ 'yxx')
      assert(RIMS::Protocol.compile_wildcard('*x') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('*x') !~ 'xxy')
      assert(RIMS::Protocol.compile_wildcard('*x*') =~ 'xyy')
      assert(RIMS::Protocol.compile_wildcard('*x*') =~ 'yxy')
      assert(RIMS::Protocol.compile_wildcard('*x*') =~ 'yyx')
      assert(RIMS::Protocol.compile_wildcard('*x*') !~ 'yyy')

      assert(RIMS::Protocol.compile_wildcard('xxx') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('xxx') !~ 'yyy')
      assert(RIMS::Protocol.compile_wildcard('x%') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('x%') !~ 'yxx')
      assert(RIMS::Protocol.compile_wildcard('%x') =~ 'xxx')
      assert(RIMS::Protocol.compile_wildcard('%x') !~ 'xxy')
      assert(RIMS::Protocol.compile_wildcard('%x%') =~ 'xyy')
      assert(RIMS::Protocol.compile_wildcard('%x%') =~ 'yxy')
      assert(RIMS::Protocol.compile_wildcard('%x%') =~ 'yyx')
      assert(RIMS::Protocol.compile_wildcard('%x%') !~ 'yyy')
    end

    def test_scan_line
      assert_equal([], RIMS::Protocol.scan_line('', StringIO.new))
      assert_equal(%w[ abcd CAPABILITY ],
                   RIMS::Protocol.scan_line('abcd CAPABILITY', StringIO.new))
      assert_equal(%w[ abcd OK CAPABILITY completed ],
                   RIMS::Protocol.scan_line('abcd OK CAPABILITY completed', StringIO.new))
      assert_equal(%w[ * CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4 ],
                   RIMS::Protocol.scan_line('* CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4', StringIO.new))
      assert_equal(%w[ * 172 EXISTS ],
                   RIMS::Protocol.scan_line('* 172 EXISTS', StringIO.new))
      assert_equal(%w[ * OK [ UNSEEN 12 ] Message 12 is first unseen ],
                   RIMS::Protocol.scan_line('* OK [UNSEEN 12] Message 12 is first unseen', StringIO.new))
      assert_equal(%w[ * FLAGS ( \\Answered \\Flagged \\Deleted \\Seen \\Draft ) ],
                   RIMS::Protocol.scan_line('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)', StringIO.new))
      assert_equal(%w[ * OK [ PERMANENTFLAGS ( \\Deleted \\Seen \\* ) ] Limited ],
                   RIMS::Protocol.scan_line('* OK [PERMANENTFLAGS (\Deleted \Seen \*)] Limited', StringIO.new))
      assert_equal([ 'A82', 'LIST', '', '*' ],
                   RIMS::Protocol.scan_line('A82 LIST "" *', StringIO.new))
      assert_equal([ '*', 'LIST', '(', '\Noselect', ')', '/', 'foo' ],
                   RIMS::Protocol.scan_line('* LIST (\Noselect) "/" foo', StringIO.new))
      assert_equal([ '*', 'LIST', '(', '\Noselect', ')', '/', 'foo [bar] (baz)' ],
                   RIMS::Protocol.scan_line('* LIST (\Noselect) "/" "foo [bar] (baz)"', StringIO.new))
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
      input = StringIO.new(literal + "\n")

      assert_equal([ 'A003', 'APPEND', 'saved-messages', '(', '\Seen', ')', literal ],
                   RIMS::Protocol.scan_line(line, input))
      assert_equal('', input.read)
    end

    def test_read_line
      assert_nil(RIMS::Protocol.read_line(StringIO.new))
      assert_equal([], RIMS::Protocol.read_line(StringIO.new("\n")))
      assert_equal(%w[ abcd CAPABILITY ],
                   RIMS::Protocol.read_line(StringIO.new("abcd CAPABILITY\n")))
      assert_equal(%w[ abcd OK CAPABILITY completed ],
                   RIMS::Protocol.read_line(StringIO.new("abcd OK CAPABILITY completed\n")))
      assert_equal(%w[ * CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4 ],
                   RIMS::Protocol.read_line(StringIO.new("* CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4\n")))
      assert_equal(%w[ * 172 EXISTS ],
                   RIMS::Protocol.read_line(StringIO.new("* 172 EXISTS\n")))
      assert_equal(%w[ * OK [ UNSEEN 12 ] Message 12 is first unseen ],
                   RIMS::Protocol.read_line(StringIO.new("* OK [UNSEEN 12] Message 12 is first unseen\n")))
      assert_equal(%w[ * FLAGS ( \\Answered \\Flagged \\Deleted \\Seen \\Draft ) ],
                   RIMS::Protocol.read_line(StringIO.new("* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\n")))
      assert_equal(%w[ * OK [ PERMANENTFLAGS ( \\Deleted \\Seen \\* ) ] Limited ],
                   RIMS::Protocol.read_line(StringIO.new("* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited\n")))
      assert_equal([ 'A82', 'LIST', '', '*' ],
                   RIMS::Protocol.read_line(StringIO.new("A82 LIST \"\" *\n")))
      assert_equal([ '*', 'LIST', '(', '\Noselect', ')', '/', 'foo' ],
                   RIMS::Protocol.read_line(StringIO.new("* LIST (\\Noselect) \"/\" foo\n")))
      assert_equal([ '*', 'LIST', '(', '\Noselect', ')', '/', 'foo [bar] (baz)' ],
                   RIMS::Protocol.read_line(StringIO.new("* LIST (\\Noselect) \"/\" \"foo [bar] (baz)\"")))
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

      input = StringIO.new("A003 APPEND saved-messages (\\Seen) {#{literal.bytesize}}\n" + literal + "\n")
      assert_equal([ 'A003', 'APPEND', 'saved-messages', '(', '\Seen', ')', literal ],
                   RIMS::Protocol.read_line(input))
      assert_equal('', input.read)
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

      input = StringIO.new("* ({#{literal1.bytesize}}\n" + literal1 + " {#{literal2.bytesize}}\n" + literal2 + ")\n")
      assert_equal([ '*', '(', literal1, literal2, ')' ], RIMS::Protocol.read_line(input))
      assert_equal('', input.read)
    end

    def test_parse
      assert_equal([], RIMS::Protocol.parse([]))
      assert_equal(%w[ abcd CAPABILITY ],
                   RIMS::Protocol.parse(%w[ abcd CAPABILITY ]))
      assert_equal(%w[ abcd OK CAPABILITY completed ],
                   RIMS::Protocol.parse(%w[ abcd OK CAPABILITY completed ]))
      assert_equal([ '*', 'OK', [ :block, 'UNSEEN', '12' ], 'Message', '12', 'is', 'first', 'unseen' ],
                   RIMS::Protocol.parse(%w[ * OK [ UNSEEN 12 ] Message 12 is first unseen ]))
      assert_equal([ '*', 'FLAGS', [ :group,  '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ] ],
                   RIMS::Protocol.parse(%w[ * FLAGS ( \\Answered \\Flagged \\Deleted \\Seen \\Draft ) ]))
      assert_equal([ '*', 'OK', [ :block, 'PERMANENTFLAGS', [ :group, '\Deleted', '\Seen', '\*' ] ], 'Limited' ],
                   RIMS::Protocol.parse(%w[ * OK [ PERMANENTFLAGS ( \\Deleted \\Seen \\* ) ] Limited ]))
    end

    def test_read_command
      assert_nil(RIMS::Protocol.read_command(StringIO.new))
      assert_nil(RIMS::Protocol.read_command(StringIO.new("\n")))
      assert_nil(RIMS::Protocol.read_command(StringIO.new(" \t\n")))
      assert_equal(%w[ abcd CAPABILITY ],
                   RIMS::Protocol.read_command(StringIO.new("abcd CAPABILITY\n")))
      assert_equal(%w[ abcd CAPABILITY ],
                   RIMS::Protocol.read_command(StringIO.new("\n \n\t\nabcd CAPABILITY\n")))
      assert_equal(%w[ abcd OK CAPABILITY completed ],
                   RIMS::Protocol.read_command(StringIO.new("abcd OK CAPABILITY completed\n")))
      assert_equal([ 'A003', 'STORE', '2:4', '+FLAGS', [ :group, '\Deleted' ] ],
                   RIMS::Protocol.read_command(StringIO.new("A003 STORE 2:4 +FLAGS (\\Deleted)\n")))

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

      input = StringIO.new("A003 APPEND saved-messages (\\Seen) {#{literal.bytesize}}\n" + literal + "\n")
      assert_equal([ 'A003', 'APPEND', 'saved-messages', [ :group, '\Seen' ], literal ],
		   RIMS::Protocol.read_command(input))
    end
  end

  class ProtocolDecoderTest < Test::Unit::TestCase
    def setup
      @kv_store = {}
      @mail_store = RIMS::MailStore.new('foo') {|path|
        kvs = {}
        def kvs.close
          self
        end
        RIMS::GDBM_KeyValueStore.new(@kv_store[path] = kvs)
      }
      @mail_store.open
      @mail_store.add_mbox('INBOX')
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL
      @decoder = RIMS::ProtocolDecoder.new(@mail_store, @logger)
      @decoder.username = 'foo'
      @decoder.password = 'open_sesame'
    end

    def teardown
      @mail_store.close
    end

    def test_capability
      res = @decoder.capability('T001').each
      assert_equal('* CAPABILITY IMAP4rev1', res.next)
      assert_equal('T001 OK CAPABILITY completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_logout
      res = @decoder.logout('T003').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T003 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }
    end

    def test_login
      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T001', 'foo', 'detarame').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)

      res = @decoder.logout('T003').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T003 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
    end

    def test_select
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.select('T001', 'INBOX').each
      assert_match(/^T001 NO /, res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.login('T002', 'foo', 'open_sesame').each
      assert_equal('T002 OK LOGIN completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      res = @decoder.select('T003', 'INBOX').each
      assert_equal('* 0 EXISTS', res.next)
      assert_equal('* 0 RECENT', res.next)
      assert_equal('* [UNSEEN 0]', res.next)
      assert_equal('* [UIDVALIDITY 1]', res.next)
      assert_equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)', res.next)
      assert_equal('T003 OK [READ-WRITE] SELECT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      res = @decoder.logout('T004').each
      assert_match(/^\* BYE /, res.next)
      assert_equal('T004 OK LOGOUT completed', res.next)
      assert_raise(StopIteration) { res.next }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
    end

    def test_command_loop_capability
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 CAPABILITY
T002 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_equal("* CAPABILITY IMAP4rev1\r\n", res.next)
      assert_equal("T001 OK CAPABILITY completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T002 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_login
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 LOGIN foo detarame
T002 LOGIN foo open_sesame
T003 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T003 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end

    def test_command_loop_select
      output = StringIO.new('', 'w')
      input = StringIO.new(<<-'EOF', 'r')
T001 SELECT INBOX
T002 LOGIN foo open_sesame
T003 SELECT INBOX
T004 LOGOUT
      EOF

      RIMS::ProtocolDecoder.repl(@decoder, input, output, @logger)
      res = output.string.each_line

      assert_match(/^T001 NO /, res.next)

      assert_equal("T002 OK LOGIN completed\r\n", res.next)

      assert_equal("* 0 EXISTS\r\n", res.next)
      assert_equal("* 0 RECENT\r\n", res.next)
      assert_equal("* [UNSEEN 0]\r\n", res.next)
      assert_equal("* [UIDVALIDITY 1]\r\n", res.next)
      assert_equal("* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n", res.next)
      assert_equal("T003 OK [READ-WRITE] SELECT completed\r\n", res.next)

      assert_match(/^\* BYE /, res.next)
      assert_equal("T004 OK LOGOUT completed\r\n", res.next)

      assert_raise(StopIteration) { res.next }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
