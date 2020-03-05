# -*- coding: utf-8 -*-

require 'logger'
require 'rims'
require 'stringio'
require 'test/unit'

module RIMS::Test
  class ProtocolRequestReaderTest < Test::Unit::TestCase
    LINE_LENGTH_LIMIT = 128

    def setup
      @input = StringIO.new('', 'r')
      @output = StringIO.new('', 'w')
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL
      @reader = RIMS::Protocol::RequestReader.new(@input, @output, @logger, line_length_limit: LINE_LENGTH_LIMIT)
    end

    data('EOF' => [
           nil,
           ''
         ],
         'short_line_length' => [
           "foo\r\n",
           "foo\r\n"
         ],
         'upper_bound_line_length' => [
           'x' * (LINE_LENGTH_LIMIT - 2) + "\r\n",
           'x' * (LINE_LENGTH_LIMIT - 2) + "\r\n"
         ])
    def test_gets(data)
      expected_line, input_line = data
      @input.string = input_line
      assert_equal(expected_line, @reader.gets)
    end

    data('too_long_line_length' => [
           'x' * LINE_LENGTH_LIMIT,
           'x' * LINE_LENGTH_LIMIT + "yyy\r\n"
         ],
         'upper_bound_line_length' => [
           'x' * LINE_LENGTH_LIMIT,
           'x' * LINE_LENGTH_LIMIT
         ])
    def test_gets_line_too_long_error
      expected_line_fragment, input_line = data
      @input.string = input_line
      error = assert_raise(RIMS::LineTooLongError) { @reader.gets }
      assert_equal(expected_line_fragment, error.optional_data[:line_fragment])
    end

    LITERAL_1 = <<-'EOF'
Date: Mon, 7 Feb 1994 21:52:25 -0800 (PST)
From: Fred Foobar <foobar@Blurdybloop.COM>
Subject: afternoon meeting
To: mooch@owatagu.siam.edu
Message-Id: <B27397-0100000@Blurdybloop.COM>
MIME-Version: 1.0
Content-Type: TEXT/PLAIN; CHARSET=US-ASCII

Hello Joe, do you think we can meet at 3:30 tomorrow?
    EOF

    LITERAL_2 = <<-'EOF'
Subject: parse test

body[]
    EOF

    LITERAL_3 = 'body[]'

    data('empty'                           => [ nil,                                nil ],
         'newline'                         => [ nil,                                "\n" ],
         'whitespaces'                     => [ nil,                                " \t\n" ],
         'tagged_command'                  => [ %w[ abcd CAPABILITY ],              "abcd CAPABILITY\n" ],
         'tagged_command_with_whitespaces' => [ %w[ abcd CAPABILITY ],              "\n \n\t\nabcd CAPABILITY\n" ],
         'tagged_response'                 => [ %w[ abcd OK CAPABILITY completed ], "abcd OK CAPABILITY completed\n" ],
         'group' => [
           [ 'A003', 'STORE', '2:4', '+FLAGS', [ :group, '\Deleted' ] ],
           "A003 STORE 2:4 +FLAGS (\\Deleted)\n"
         ],
         'nested_group' => [
           [ 'abcd', 'SEARCH',
             [ :group,
               'OR',
               [ :group, 'FROM', 'foo' ],
               [ :group, 'FROM', 'bar' ]
             ]
           ],
           "abcd SEARCH (OR (FROM foo) (FROM bar))\n"
         ],
         'quoted_special_nil' => [
           [ 'abcd', 'SEARCH', 'SUBJECT', 'NIL'  ],
           "abcd SEARCH SUBJECT \"NIL\"\n"
         ],
         'quoted_special_parenthesis_begin' => [
           [ 'abcd', 'SEARCH', 'SUBJECT', '(' ],
           "abcd SEARCH SUBJECT \"(\"\n"
         ],
         'quoted_special_parenthesis_end' => [
           [ 'abcd', 'SEARCH', 'SUBJECT', ')' ],
           "abcd SEARCH SUBJECT \")\"\n"
         ],
         'quoted_special_square_bracket_begin' => [
           [ 'abcd', 'SEARCH', 'SUBJECT', '['  ],
           "abcd SEARCH SUBJECT \"[\"\n"
         ],
         'quoted_special_square_bracket_end' => [
           [ 'abcd', 'SEARCH', 'SUBJECT', ']' ],
           "abcd SEARCH SUBJECT \"]\"\n"
         ],
         'fetch_non_extensible_bodystructure' => [
           [ 'A654', 'FETCH', '2:4', [ :group, 'BODY' ] ],
           "A654 FETCH 2:4 (BODY)\n"
         ],
         'fetch_body_section' => [
           [ 'A654', 'FETCH', '2:4', [
               :group, [
                 :body,
                 RIMS::Protocol.body(symbol: 'BODY',
                                     section: '',
                                     section_list: [])
               ]
             ]
           ],
           "A654 FETCH 2:4 (BODY[])\n"
         ],
         'fetch_multiple_items' => [
           [ 'A654', 'FETCH', '2:4',
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
           "A654 FETCH 2:4 (FLAGS BODY.PEEK[HEADER.FIELDS (DATE FROM)]<0.1500>)\n"
         ],
         'append_inline' => [
           [ 'A654', 'APPEND', 'saved-messages', 'body[]' ],
           "A654 APPEND saved-messages \"body[]\"\n"
         ],
         'append_literal_1' => [
           [ 'A003', 'APPEND', 'saved-messages', [ :group, '\Seen' ], LITERAL_1 ],
           "A003 APPEND saved-messages (\\Seen) {#{LITERAL_1.bytesize}}\n" + LITERAL_1 + "\n",
           true
         ],
         'append_literal_2' => [
           [ 'A004', 'APPEND', 'saved-messages', LITERAL_2 ],
           "A004 APPEND saved-messages {#{LITERAL_2.bytesize}}\n" + LITERAL_2 + "\n",
           true
         ],
         'append_literal_3' => [
           [ 'A005', 'APPEND', 'saved-messages', LITERAL_3 ],
           "A005 APPEND saved-messages {#{LITERAL_3.bytesize}}\n" + LITERAL_3 + "\n",
           true
         ])
    def test_read_command(data)
      expected_atom_list, input_string, is_literal = data
      @input.string = input_string if input_string
      assert_equal(expected_atom_list, @reader.read_command)
      assert_equal(expected_atom_list[0], @reader.command_tag) if expected_atom_list

      if (is_literal) then
        cmd_cont_req = @output.string.each_line
        assert_match(/^\+ /, cmd_cont_req.next)
        assert_raise(StopIteration) { cmd_cont_req.next }
      else
        assert_equal('', @output.string)
      end
    end

    def test_read_command_string_literal_multi
      literal = RIMS::RFC822::Parse.split_message(LITERAL_1)

      @input.string = "A284 SEARCH CHARSET UTF-8 TEXT {#{literal[0].bytesize}}\n" + literal[0] + " TEXT {#{literal[1].bytesize}}\n" + literal[1] + "\n"
      assert_equal([ 'A284', 'SEARCH', 'CHARSET', 'UTF-8', 'TEXT', literal[0], 'TEXT', literal[1] ], @reader.read_command)
      assert_equal('A284', @reader.command_tag)
      assert_equal('', @input.read)

      cmd_cont_req = @output.string.each_line
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_match(/^\+ /, cmd_cont_req.next)
      assert_raise(StopIteration) { cmd_cont_req.next }
    end

    def test_read_command_no_tag_error
      @input.string = "noop\r\n"
      error = assert_raise(RIMS::SyntaxError) { @reader.read_command }
      assert_match(/need for tag/, error.message)
    end

    data('*'          => %w[ * * ],
         '+'          => %w[ + + ],
         'not_string' => [ '{123}', [ :literal, 123 ] ])
    def test_read_command_invalid_tag_error(data)
      invalid_tag, parsed_tag = data
      @input.string = invalid_tag
      error = assert_raise(RIMS::SyntaxError) { @reader.read_command }
      assert_match(/invalid command tag/, error.message)
      assert_include(error.message, parsed_tag.to_s)
    end

    def test_read_command_line_too_long_error
      line = 'X001 x'
      while (line.bytesize < LINE_LENGTH_LIMIT)
        line << 'x'
      end
      line << "x\r\n"
      assert_operator(line.bytesize, :>, LINE_LENGTH_LIMIT)

      @input.string = line
      assert_raise(RIMS::LineTooLongError) { @reader.read_command }
      assert_equal("x\r\n", @input.read, 'not read end of line')
    end
  end

  class ProtocolRequestReaderClassMethodTest < Test::Unit::TestCase
    data('empty'             => [ [],                                            '' ],
         'tagged_command'    => [ %w[ abcd CAPABILITY ],                         'abcd CAPABILITY' ],
         'tagged_response'   => [ %w[ abcd OK CAPABILITY completed ],            'abcd OK CAPABILITY completed' ],
         'untagged_response' => [ %w[ * CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4 ], '* CAPABILITY IMAP4rev1 AUTH=KERBEROS_V4' ],
         'untagged_exists'   => [ %w[ * 172 EXISTS ],                            '* 172 EXISTS' ],
         'untagged_unseen' => [
           [ '*', 'OK', '['.intern, 'UNSEEN', '12', ']'.intern, 'Message', '12', 'is', 'first', 'unseen' ],
           '* OK [UNSEEN 12] Message 12 is first unseen'
         ],
         'untagged_flags' => [
           [ '*', 'FLAGS', '('.intern, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft', ')'.intern ],
           '* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)'
         ],
         'untagged_permanentflags' => [
           [ '*', 'OK', '['.intern, 'PERMANENTFLAGS', '('.intern, '\Deleted', '\Seen', '\*', ')'.intern, ']'.intern, 'Limited' ],
           '* OK [PERMANENTFLAGS (\Deleted \Seen \*)] Limited'
         ],
         'list_empty_reference' => [
           [ 'A82', 'LIST', '', '*' ],
           'A82 LIST "" *'
         ],
         'untagged_list_delimiter' => [
           [ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, '/', 'foo' ],
           '* LIST (\Noselect) "/" foo'
         ],
         'untagged_list_quoted_name' => [
           [ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, '/', 'foo [bar] (baz)' ],
           '* LIST (\Noselect) "/" "foo [bar] (baz)"'
         ],
         'untagged_list_nil_delimiter' => [
           [ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, :NIL, '' ],
           '* LIST (\Noselect) NIL ""'
         ],
         'fetch_body_command' => [
           [ 'A654', 'FETCH', '2:4',
             '('.intern,
             [ :body, RIMS::Protocol.body(symbol: 'BODY', section: '') ],
             ')'.intern
           ],
           'A654 FETCH 2:4 (BODY[])'
         ],
         'append_literal' => [
           [ 'A003', 'APPEND', 'saved-messages', '('.intern, '\Seen', ')'.intern, [ :literal, 310 ] ],
           'A003 APPEND saved-messages (\Seen) {310}'
         ])
    def test_scan(data)
      expected_atom_list, line = data
      assert_equal(expected_atom_list, RIMS::Protocol::RequestReader.scan(line))
    end

    data('empty'           => [ [],                                 [] ],
         'tagged_command'  => [ %w[ abcd CAPABILITY ],              %w[ abcd CAPABILITY ] ],
         'tagged_response' => [ %w[ abcd OK CAPABILITY completed ], %w[ abcd OK CAPABILITY completed ] ],
         'untagged_unseen' => [
           [ '*', 'OK', [ :block, 'UNSEEN', '12' ], 'Message', '12', 'is', 'first', 'unseen' ],
           [ '*', 'OK', '['.intern, 'UNSEEN', '12', ']'.intern, 'Message', '12', 'is', 'first', 'unseen' ]
         ],
         'untagged_flags' =>[
           [ '*', 'FLAGS', [ :group,  '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ] ],
           [ '*', 'FLAGS', '('.intern, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft', ')'.intern ]
         ],
         'untagged_permanentflags' => [
           [ '*', 'OK', [ :block, 'PERMANENTFLAGS', [ :group, '\Deleted', '\Seen', '\*' ] ], 'Limited' ],
           [ '*', 'OK', '['.intern, 'PERMANENTFLAGS', '('.intern, '\Deleted', '\Seen', '\*', ')'.intern, ']'.intern, 'Limited' ]
         ],
         'untagged_list_nil_delimiter' => [
           [ '*', 'LIST', [ :group, '\Noselect' ], :NIL, '' ],
           [ '*', 'LIST', '('.intern, '\Noselect', ')'.intern, :NIL, '' ]
         ],
         'fetch_body_command' => [
           [ 'A654', 'FETCH', '2:4',
             [ :group,
               [ :body,
                 RIMS::Protocol.body(symbol:       'BODY',
                                     section:      '',
                                     section_list: [])
               ]
             ]
           ],
           [ 'A654',                   'FETCH',                             '2:4',
             '('.intern,
             [ :body,                  RIMS::Protocol.body(symbol:  'BODY', section: '') ],
             ')'.intern
           ]
         ],
         'append_command' => [
           [ 'A003',                   'APPEND',                            'saved-messages', "foo\nbody[]\nbar\n" ],
           [ 'A003',                   'APPEND',                            'saved-messages', "foo\nbody[]\nbar\n" ]
         ])
    def test_parse(data)
      expected_atom_list, input_atom_list = data
      assert_equal(expected_atom_list, RIMS::Protocol::RequestReader.parse(input_atom_list))
    end

    data('unclosed_square_bracket' => [ '*', 'OK',   '['.intern, 'UNSEEN', '12' ],
         'unclosed_parenthesis'    => [ '*', 'LIST', '('.intern, '\Noselect' ])
    def test_parse_not_found_a_terminator_error(data)
      input_atom_list = data
      error = assert_raise(RIMS::SyntaxError) { RIMS::Protocol::RequestReader.parse(input_atom_list) }
      assert_match(/not found a terminator/, error.message)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
