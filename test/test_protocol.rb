# -*- coding: utf-8 -*-

require 'rims'
require 'stringio'
require 'test/unit'

module RIMS::Test
  class ProtocolTest < Test::Unit::TestCase
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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
