# -*- coding: utf-8 -*-

require 'logger'
require 'net/imap'
require 'pp' if $DEBUG
require 'rims'
require 'stringio'
require 'test/unit'
require 'time'

module RIMS::Test
  class ProtocolDecoderTest < Test::Unit::TestCase
    include RIMS::Test::AssertUtility
    include RIMS::Test::ProtocolFetchMailSample
    include RIMS::Test::PseudoAuthenticationUtility

    UTF8_MBOX_NAME = '~peter/mail/日本語/台北'.freeze
    UTF7_MBOX_NAME = '~peter/mail/&ZeVnLIqe-/&U,BTFw-'.b.freeze

    def encode_utf7(utf8_str)
      Net::IMAP.encode_utf7(utf8_str) # -> utf7_str
    end
    private :encode_utf7

    def decode_utf7(utf7_str)
      Net::IMAP.decode_utf7(utf7_str) # -> utf8_str
    end
    private :decode_utf7

    class IMAPResponseAssertionDSL
      include Test::Unit::Assertions

      def initialize(response_lines, crlf_at_eol: true)
        @lines = response_lines
        @crlf_at_eol = crlf_at_eol
      end

      def fetch_line(peek_next_line: false)
        if (peek_next_line) then
          @lines.peek
        else
          @lines.next
        end
      end
      private :fetch_line

      def skip_while(&cond)
        while (cond.call(@lines.peek))
          @lines.next
        end
        self
      end

      def equal(expected_string, peek_next_line: false)
        expected_string += "\r\n" if (@crlf_at_eol && expected_string !~ /\n\z/)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_equal(expected_string, line)
        self
      end

      def strenc_equal(expected_string, peek_next_line: false)
        expected_string += "\r\n" if (@crlf_at_eol && expected_string !~ /\n\z/)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_equal(expected_string.encoding, line.encoding)
        assert_equal(expected_string, line)
        self
      end

      def match(expected_regexp, peek_next_line: false)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_match(expected_regexp, line)
        assert_match(/\r\n\z/, line) if @crlf_at_eol
        self
      end

      def no_match(expected_regexp, peek_next_line: false)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_not_nil(expected_regexp, line)
        assert_match(/\r\n\z/, line) if @crlf_at_eol
        self
      end

      def equal_lines(expected_multiline_string)
        expected_multiline_string.each_line do |line|
          self.equal(line)
        end
        self
      end
    end

    def assert_imap_response(response_lines, crlf_at_eol: true)
      dsl = IMAPResponseAssertionDSL.new(response_lines, crlf_at_eol: crlf_at_eol)
      yield(dsl)
      assert_raise(StopIteration) { response_lines.next }

      nil
    end
    private :assert_imap_response

    def setup
      @kvs = Hash.new{|h, k| h[k] = {} }
      @kvs_open = proc{|mbox_version, unique_user_id, db_name|
        RIMS::Hash_KeyValueStore.new(@kvs["#{mbox_version}/#{unique_user_id[0, 7]}/#{db_name}"])
      }
      @unique_user_id = RIMS::Authentication.unique_user_id('foo')

      @mail_store_pool = RIMS::MailStorePool.new(@kvs_open, @kvs_open)
      @mail_store_holder = @mail_store_pool.get(@unique_user_id)
      @mail_store = @mail_store_holder.mail_store
      @inbox_id = @mail_store.mbox_id('INBOX')

      src_time = Time.at(1404369876)
      random_seed = 8091822677904057789202046265537518639

      @time_source = make_pseudo_time_source(src_time)
      @random_string_source = make_pseudo_random_string_source(random_seed)

      @auth = RIMS::Authentication.new(time_source: make_pseudo_time_source(src_time),
                                       random_string_source: make_pseudo_random_string_source(random_seed))
      @auth.entry('foo', 'open_sesame')
      @auth.entry('#postman', 'password_of_mail_delivery_user')

      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL

      @decoder = RIMS::Protocol::Decoder.new_decoder(@mail_store_pool, @auth, @logger)
      @tag = 'T000'
    end

    def reload_mail_store
      @mail_store_holder.return_pool
      assert(@mail_store_pool.empty?)

      @mail_store_holder = nil
      @mail_store = nil

      begin
        yield
      ensure
        @mail_store_holder = @mail_store_pool.get(@unique_user_id)
        @mail_store = @mail_store_holder.mail_store
      end
    end
    private :reload_mail_store

    def teardown
      @decoder.cleanup
      @mail_store_holder.return_pool
      assert(@mail_store_pool.empty?)
      pp @kvs if $DEBUG
    end

    def tag
      @tag.dup
    end
    private :tag

    def tag!
      @tag.succ!.dup
    end
    private :tag!

    def assert_imap_command(cmd_method_symbol, *cmd_str_args, crlf_at_eol: true, client_response_input_text: nil, **cmd_opts)
      tag!

      case (cmd_method_symbol)
      when :authenticate
        assert(cmd_opts.empty?)
        execute_imap_command_authenticate(tag, cmd_str_args, client_response_input_text) {|response_lines|
          assert_imap_response(response_lines, crlf_at_eol: crlf_at_eol) {|assert| yield(assert) }
        }
      when :login
        assert(cmd_opts.empty?)
        execute_imap_command_login(tag, cmd_str_args) {|response_lines|
          assert_imap_response(response_lines, crlf_at_eol: crlf_at_eol) {|assert| yield(assert) }
        }
      else
        if (cmd_opts.empty?) then
          execute_imap_command(cmd_method_symbol, tag, cmd_str_args) {|response_lines|
            assert_imap_response(response_lines, crlf_at_eol: crlf_at_eol) {|assert| yield(assert) }
          }
        else
          execute_imap_command_with_options(cmd_method_symbol, tag, cmd_str_args, cmd_opts) {|response_lines|
            assert_imap_response(response_lines, crlf_at_eol: crlf_at_eol) {|assert| yield(assert) }
          }
        end
      end

      nil
    end
    private :assert_imap_command

    def execute_imap_command(cmd_method_symbol, tag, cmd_str_args)
      response_lines = @decoder.__send__(cmd_method_symbol, tag, *cmd_str_args)
      yield(response_lines.each)
    end
    private :execute_imap_command

    def execute_imap_command_with_options(cmd_method_symbol, tag, cmd_str_args, cmd_opts)
      response_lines = @decoder.__send__(cmd_method_symbol, tag, *cmd_str_args, **cmd_opts)
      yield(response_lines.each)
    end
    private :execute_imap_command_with_options

    def execute_imap_command_authenticate(tag, cmd_str_args, client_response_input_text)
      input = StringIO.new(client_response_input_text, 'r')
      output = StringIO.new('', 'w')

      response_lines, @decoder = @decoder.authenticate(input, output, tag, *cmd_str_args)
      ret_val = yield(response_lines.each)

      if ($DEBUG) then
        pp input.string, output.string
      end

      ret_val
    end
    private :execute_imap_command_authenticate

    def execute_imap_command_login(tag, cmd_str_args)
      response_lines, @decoder = @decoder.login(tag, *cmd_str_args)
      yield(response_lines.each)
    end
    private :execute_imap_command_login

    def assert_imap_command_loop(client_command_list_text, autotag: true)
      if (autotag) then
        tag = 'T000'
        tag_command_list = []
        client_command_list_text.each_line do |line|
          tag_command_list << "#{tag.succ!} #{line}"
        end
        client_command_list_text = tag_command_list.join('')
      end

      input = StringIO.new(client_command_list_text, 'r')
      output = StringIO.new('', 'w')

      RIMS::Protocol::Decoder.repl(@decoder, input, output, @logger)
      response_lines = output.string.each_line

      assert_imap_response(response_lines) {|assert|
        yield(assert)
      }
    end
    private :assert_imap_command_loop

    def client_plain_response_base64(authentication_id, plain_password)
      response_txt = [ authentication_id, authentication_id, plain_password ].join("\0")
      RIMS::Protocol.encode_base64(response_txt)
    end
    private :client_plain_response_base64

    def make_cram_md5_server_client_data_base64(username, password)
      server_challenge_data = RIMS::Authentication.cram_md5_server_challenge_data('rims', @time_source, @random_string_source)
      client_response_data = username + ' ' + RIMS::Authentication.hmac_md5_hexdigest(password, server_challenge_data)

      server_challenge_data_base64 = RIMS::Protocol.encode_base64(server_challenge_data)
      client_response_data_base64 = RIMS::Protocol.encode_base64(client_response_data)

      return server_challenge_data_base64, client_response_data_base64
    end
    private :make_cram_md5_server_client_data_base64

    def add_msg(msg_txt, *optional_args, mbox_id: @inbox_id)
      @mail_store.add_msg(mbox_id, msg_txt, *optional_args)
    end
    private :add_msg

    def get_msg_text(uid, mbox_id: @inbox_id)
      @mail_store.msg_text(mbox_id, uid)
    end
    private :get_msg_text

    def get_msg_date(uid, mbox_id: @inbox_id)
      @mail_store.msg_date(mbox_id, uid)
    end
    private :get_msg_date

    def assert_msg_text(*msg_txt_list, mbox_id: @inbox_id)
      assert_equal(msg_txt_list,
                   @mail_store.each_msg_uid(mbox_id).map{|uid|
                     get_msg_text(uid, mbox_id: mbox_id)
                   })
    end
    private :assert_msg_text

    def expunge(*uid_list)
      for uid in uid_list
        set_msg_flag(uid, 'deleted', true)
      end
      @mail_store.expunge_mbox(@inbox_id)
      nil
    end
    private :expunge

    def assert_msg_uid(*uid_list, mbox_id: @inbox_id)
      assert_equal(uid_list, @mail_store.each_msg_uid(mbox_id).to_a)
    end
    private :assert_msg_uid

    def get_msg_flag(uid, flag_name, mbox_id: @inbox_id)
      @mail_store.msg_flag(mbox_id, uid, flag_name)
    end
    private :get_msg_flag

    def set_msg_flag(uid, flag_name, flag_value, mbox_id: @inbox_id)
      @mail_store.set_msg_flag(mbox_id, uid, flag_name, flag_value)
      nil
    end
    private :set_msg_flag

    def set_msg_flags(flag_name, flag_value, *uid_list, mbox_id: @inbox_id)
      for uid in uid_list
        set_msg_flag(uid, flag_name, flag_value, mbox_id: mbox_id)
      end
      nil
    end
    private :set_msg_flags

    def assert_msg_flags(uid, answered: false, flagged: false, deleted: false, seen: false, draft: false, recent: false, mbox_id: @inbox_id)
      [ [ 'answered', answered],
        [ 'flagged', flagged ],
        [ 'deleted', deleted ],
        [ 'seen', seen ],
        [ 'draft', draft ],
        [ 'recent', recent ]
      ].each do |flag_name, flag_value|
        assert_equal([ flag_name, flag_value ],
                     [ flag_name, @mail_store.msg_flag(mbox_id, uid, flag_name) ])
      end
      nil
    end
    private :assert_msg_flags

    def assert_flag_enabled_msgs(flag_name, *uid_list, mbox_id: @inbox_id)
      assert_equal([ flag_name, uid_list ],
                   [ flag_name,
                     @mail_store.each_msg_uid(mbox_id).find_all{|uid|
                       @mail_store.msg_flag(mbox_id, uid, flag_name)
                     }
                   ])
    end
    private :assert_flag_enabled_msgs

    def assert_mbox_flag_num(answered: 0, flagged: 0, deleted: 0, seen: 0, draft: 0, recent: 0, mbox_id: @inbox_id)
      [ [ :answered, answered ],
        [ :flagged, flagged ],
        [ :deleted, deleted ],
        [ :seen, seen ],
        [ :draft, draft ],
        [ :recent, recent ]
      ].each do |flag_sym, flag_num|
        assert_equal([ flag_sym, flag_num ], [ flag_sym, @mail_store.mbox_flag_num(mbox_id, flag_sym.to_s) ])
      end
      nil
    end
    private :assert_mbox_flag_num

    def get_mbox_id_list(*mbox_name_list)
      mbox_name_list.map{|name| @mail_store.mbox_id(name) }
    end
    private :get_mbox_id_list

    def assert_mbox_exists(name)
      assert_not_nil(@mail_store.mbox_id(name))
    end
    private :assert_mbox_exists

    def assert_mbox_not_exists(name)
      assert_nil(@mail_store.mbox_id(name))
    end
    private :assert_mbox_not_exists

    def add_mail_simple
      make_mail_simple
      add_msg(@simple_mail.raw_source, Time.parse('2013-11-08 06:47:50 +0900'))
    end
    private :add_mail_simple

    def add_mail_multipart
      make_mail_multipart
      add_msg(@mpart_mail.raw_source, Time.parse('2013-11-08 19:31:03 +0900'))
    end
    private :add_mail_multipart

    def make_string_source(start_string)
      Enumerator.new{|y|
        s = start_string.dup
        loop do
          y << s
          s = s.succ
        end
      }
    end
    private :make_string_source

    def test_capability
      assert_imap_command(:capability) {|assert|
        assert.equal('* CAPABILITY IMAP4rev1 AUTH=PLAIN AUTH=CRAM-MD5')
        assert.equal("#{tag} OK CAPABILITY completed")
      }
    end

    def test_logout
      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_authenticate_plain_inline
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:authenticate, 'plain',
                          client_plain_response_base64('foo', 'detarame'),
                          client_response_input_text: '') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:authenticate, 'plain',
                          client_plain_response_base64('foo', 'open_sesame'),
                          client_response_input_text: '') {|assert|
        assert.equal("#{tag} OK AUTHENTICATE plain success")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:authenticate, 'plain',
                          client_plain_response_base64('foo', 'open_sesame'),
                          client_response_input_text: '') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
    end

    def test_authenticate_plain_stream
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:authenticate, 'plain', client_response_input_text: "*\r\n") {|assert|
        assert.match(/^#{tag} BAD /)
      }

      assert_imap_command(:authenticate, 'plain',
                          client_response_input_text: client_plain_response_base64('foo', 'detarame') + "\r\n") {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:authenticate, 'plain',
                          client_response_input_text: client_plain_response_base64('foo', 'open_sesame') + "\r\n") {|assert|
        assert.equal("#{tag} OK AUTHENTICATE plain success")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:authenticate, 'plain', client_response_input_text: '') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
    end

    def test_authenticate_cram_md5_stream
      server_client_data_base64_pair_list = [
        make_cram_md5_server_client_data_base64('foo', 'open_sesame'),
        make_cram_md5_server_client_data_base64('foo', 'detarame'),
        make_cram_md5_server_client_data_base64('foo', 'open_sesame')
      ]

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:authenticate, 'cram-md5', client_response_input_text: "*\r\n") {|assert|
        assert.match(/^#{tag} BAD /)
      }

      assert_imap_command(:authenticate, 'cram-md5',
                          client_response_input_text: server_client_data_base64_pair_list[1][1] + "\r\n") {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:authenticate, 'cram-md5',
                          client_response_input_text: server_client_data_base64_pair_list[2][1] + "\r\n") {|assert|
        assert.equal("#{tag} OK AUTHENTICATE cram-md5 success")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:authenticate, 'cram-md5', client_response_input_text: '') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
    end

    def test_login
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'detarame') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.match(/^#{tag} NO/)
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
    end

    def test_select
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    , 2   )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  ,     )
      assert_mbox_flag_num(seen: 1)
    end

    def test_select_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:select, UTF7_MBOX_NAME) {|assert|
        assert.equal('* 0 EXISTS')
        assert.equal('* 0 RECENT')
        assert.equal('* OK [UNSEEN 0]')
        assert.equal("* OK [UIDVALIDITY #{utf8_name_mbox_id}]")
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_examine
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)
    end

    def test_examine_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:examine, UTF7_MBOX_NAME) {|assert|
        assert.equal('* 0 EXISTS')
        assert.equal('* 0 RECENT')
        assert.equal('* OK [UNSEEN 0]')
        assert.equal("* OK [UIDVALIDITY #{utf8_name_mbox_id}]")
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_create
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:create, 'foo') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_nil(@mail_store.mbox_id('foo'))

      assert_imap_command(:create, 'foo') {|assert|
        assert.equal("#{tag} OK CREATE completed")
      }

      assert_not_nil(@mail_store.mbox_id('foo'))

      assert_imap_command(:create, 'inbox') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_create_utf7_mbox_name
      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_nil(@mail_store.mbox_id(UTF8_MBOX_NAME))

      assert_imap_command(:create, UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK CREATE completed")
      }

      assert_not_nil(@mail_store.mbox_id(UTF8_MBOX_NAME))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_delete
      @mail_store.add_mbox('foo')

      assert_equal(false, @decoder.auth?)

      assert_mbox_exists('foo')
      assert_imap_command(:delete, 'foo') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_mbox_exists('foo')

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_mbox_exists('foo')
      assert_imap_command(:delete, 'foo') {|assert|
        assert.equal("#{tag} OK DELETE completed")
      }
      assert_mbox_not_exists('foo')

      assert_mbox_not_exists('bar')
      assert_imap_command(:delete, 'bar') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_mbox_not_exists('bar')

      assert_mbox_exists('INBOX')
      assert_imap_command(:delete, 'inbox') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_mbox_exists('INBOX')

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_delete_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_mbox_exists(UTF8_MBOX_NAME)
      assert_imap_command(:delete, UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK DELETE completed")
      }
      assert_mbox_not_exists(UTF8_MBOX_NAME)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_rename
      mbox_id = @mail_store.add_mbox('foo')

      assert_equal(false, @decoder.auth?)

      assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))
      assert_imap_command(:rename, 'foo', 'bar') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))
      assert_imap_command(:rename, 'foo', 'bar') {|assert|
        assert.equal("#{tag} OK RENAME completed")
      }
      assert_equal([ nil, mbox_id ], get_mbox_id_list('foo', 'bar'))

      assert_imap_command(:rename, 'nobox', 'baz') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal([ @inbox_id, nil ], get_mbox_id_list('INBOX', 'baz'))
      assert_imap_command(:rename, 'INBOX', 'baz') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_equal([ @inbox_id, nil ], get_mbox_id_list('INBOX', 'baz'))

      assert_equal([ mbox_id, @inbox_id ], get_mbox_id_list('bar', 'INBOX'))
      assert_imap_command(:rename, 'bar', 'inbox') {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_equal([ mbox_id, @inbox_id ], get_mbox_id_list('bar', 'INBOX'))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_rename_utf7_mbox_name
      mbox_id = @mail_store.add_mbox('foo')

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', UTF8_MBOX_NAME))
      assert_imap_command(:rename, 'foo', UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK RENAME completed")
      }
      assert_equal([ nil, mbox_id ], get_mbox_id_list('foo', UTF8_MBOX_NAME))

      assert_equal([ mbox_id, nil ], get_mbox_id_list(UTF8_MBOX_NAME, 'bar'))
      assert_imap_command(:rename, UTF7_MBOX_NAME, 'bar') {|assert|
        assert.equal("#{tag} OK RENAME completed")
      }
      assert_equal([ nil, mbox_id ], get_mbox_id_list(UTF8_MBOX_NAME, 'bar'))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_subscribe_dummy
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:subscribe, 'INBOX') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:subscribe, 'INBOX') {|assert|
        assert.equal("#{tag} OK SUBSCRIBE completed")
      }

      assert_imap_command(:subscribe, 'NOBOX') {|assert|
        assert.equal("#{tag} NO not found a mailbox")
      }
    end

    def test_subscribe_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:subscribe, UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK SUBSCRIBE completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_unsubscribe_dummy
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:unsubscribe, 'INBOX') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:unsubscribe, 'INBOX') {|assert|
        assert.equal("#{tag} NO not implemented subscribe/unsbscribe command")
      }
    end

    def test_list
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:list, '', '') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:list, '', '') {|assert|
        assert.equal('* LIST (\Noselect) NIL ""')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list, '', 'nobox') {|assert|
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list, '', '*') {|assert|
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "INBOX"')
        assert.equal("#{tag} OK LIST completed")
      }

      add_msg('')

      assert_imap_command(:list, '', '*') {|assert|
        assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        assert.equal("#{tag} OK LIST completed")
      }

      @mail_store.add_mbox('foo')

      assert_imap_command(:list, '', '*') {|assert|
        assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list, '', 'f*') {|assert|
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list, 'IN', '*') {|assert|
        assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_list_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:list,
                          encode_utf7(UTF8_MBOX_NAME[0..6]),
                          '*' + encode_utf7(UTF8_MBOX_NAME[12..14]) + '*') {|assert|
        assert.equal(%Q'* LIST (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:list,
                          encode_utf7(UTF8_MBOX_NAME[0..13]),
                          '*' + encode_utf7(UTF8_MBOX_NAME[16]) + '*') {|assert|
        assert.equal(%Q'* LIST (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
        assert.equal("#{tag} OK LIST completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_status
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:status, 'nobox', [ :group, 'MESSAGES' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:status, 'nobox', [ :group, 'MESSAGES' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES' ]) {|assert|
        assert.equal('* STATUS "INBOX" (MESSAGES 0)')
        assert.equal("#{tag} OK STATUS completed")
      }

      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 0 RECENT 0 UIDNEXT 1 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
        assert.equal("#{tag} OK STATUS completed")
      }

      add_msg('')
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 1 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
        assert.equal("#{tag} OK STATUS completed")
      }

      set_msg_flag(1, 'recent', false)
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
        assert.equal("#{tag} OK STATUS completed")
      }

      set_msg_flag(1, 'seen', true)
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
        assert.equal("#{tag} OK STATUS completed")
      }

      add_msg('')
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 2 RECENT 1 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
        assert.equal("#{tag} OK STATUS completed")
      }

      expunge(2)
      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
        assert.equal("#{tag} OK STATUS completed")
      }

      assert_imap_command(:status, 'INBOX', 'MESSAGES') {|assert|
        assert.match(/^#{tag} BAD /)
      }

      assert_imap_command(:status, 'INBOX', [ :group, 'DETARAME' ]) {|assert|
        assert.match(/^#{tag} BAD /)
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_status_utf7_mbox_name
      mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:status, UTF7_MBOX_NAME, [ :group, 'UIDVALIDITY', 'MESSAGES', 'RECENT', 'UNSEEN' ]) {|assert|
        assert.equal(%Q'* STATUS "#{UTF7_MBOX_NAME}" (UIDVALIDITY #{mbox_id} MESSAGES 0 RECENT 0 UNSEEN 0)')
        assert.equal("#{tag} OK STATUS completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_lsub_dummy
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:lsub, '', '*') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:lsub, '', '*') {|assert|
        assert.equal('* LSUB (\Noinferiors \Unmarked) NIL "INBOX"')
        assert.equal("#{tag} OK LSUB completed")
      }
    end

    def test_lsub_dummy_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:lsub,
                          encode_utf7(UTF8_MBOX_NAME[0..6]),
                          '*' + encode_utf7(UTF8_MBOX_NAME[12..14]) + '*') {|assert|
        assert.equal(%Q'* LSUB (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
        assert.equal("#{tag} OK LSUB completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_append
      assert_equal(false, @decoder.auth?)

      assert_imap_command(:append, 'INBOX', 'a') {|assert|
        assert.match(/^#{tag} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }
      assert_msg_uid()

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:append, 'INBOX', 'a') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1)
      assert_equal('a', get_msg_text(1))
      assert_msg_flags(1, recent: true)

      assert_imap_command(:append, 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], 'b') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1, 2)
      assert_equal('b', get_msg_text(2))
      assert_msg_flags(2, answered: true, flagged: true, deleted: true, seen: true, draft: true, recent: true)

      assert_imap_command(:append, 'INBOX', '19-Nov-1975 12:34:56 +0900', 'c') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1, 2, 3)
      assert_equal('c', get_msg_text(3))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(3))
      assert_msg_flags(3, recent: true)

      assert_imap_command(:append, 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], '19-Nov-1975 12:34:56 +0900', 'd') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1, 2, 3, 4)
      assert_equal('d', get_msg_text(4))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(4))
      assert_msg_flags(4, answered: true, flagged: true, deleted: true, seen: true, draft: true, recent: true)

      assert_imap_command(:append, 'INBOX', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], '19-Nov-1975 12:34:56 +0900', :NIL, 'x') {|assert|
        assert.match(/^#{tag} BAD /)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:append, 'INBOX', '19-Nov-1975 12:34:56 +0900', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], 'x') {|assert|
        assert.match(/^#{tag} BAD /)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:append, 'INBOX', [ :group, '\Recent' ], 'x') {|assert|
        assert.match(/^#{tag} BAD /)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:append, 'INBOX', 'bad date-time', 'x') {|assert|
        assert.match(/^#{tag} BAD /)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:append, 'nobox', 'x') {|assert|
        assert.match(/^#{tag} NO \[TRYCREATE\]/)
      }
      assert_msg_uid(1, 2, 3, 4)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_append_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_msg_uid(mbox_id: utf8_name_mbox_id)
      assert_imap_command(:append, UTF7_MBOX_NAME, 'Hello world.') {|assert|
        assert.equal("#{tag} OK APPEND completed")
      }
      assert_msg_uid(1, mbox_id: utf8_name_mbox_id)
      assert_equal('Hello world.', get_msg_text(1, mbox_id: utf8_name_mbox_id))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_check
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:check) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:check) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* /}
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:check) {|assert|
        assert.equal("#{tag} OK CHECK completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_close
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.equal("#{tag} OK CLOSE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    , 2   )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  ,     )
      assert_mbox_flag_num(seen: 1)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
    end

    def test_close_read_only
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:close) {|assert|
        assert.equal("#{tag} OK CLOSE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
    end

    def test_expunge
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:expunge) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:expunge) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:expunge) {|assert|
        assert.equal("#{tag} OK EXPUNGE completed")
      }

      add_msg('')
      add_msg('')
      add_msg('')

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' ,        )
      assert_flag_enabled_msgs('seen'    ,        )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  , 1, 2, 3)
      assert_mbox_flag_num(recent: 3)

      assert_imap_command(:expunge) {|assert|
        assert.equal("#{tag} OK EXPUNGE completed")
      }

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' ,        )
      assert_flag_enabled_msgs('seen'    ,        )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  , 1, 2, 3)
      assert_mbox_flag_num(recent: 3)

      set_msg_flags('answered', true, 2, 3)
      set_msg_flags('flagged',  true, 2, 3)
      set_msg_flags('deleted',  true, 2)
      set_msg_flags('seen',     true, 2, 3)
      set_msg_flags('draft',    true, 2, 3)

      assert_msg_uid(1, 2, 3)
      assert_flag_enabled_msgs('answered',    2, 3)
      assert_flag_enabled_msgs('flagged' ,    2, 3)
      assert_flag_enabled_msgs('deleted' ,    2   )
      assert_flag_enabled_msgs('seen'    ,    2, 3)
      assert_flag_enabled_msgs('draft'   ,    2, 3)
      assert_flag_enabled_msgs('recent'  , 1, 2, 3)
      assert_mbox_flag_num(answered: 2, flagged: 2, deleted: 1, seen: 2, draft: 2, recent: 3)

      assert_imap_command(:expunge) {|assert|
        assert.equal('* 2 EXPUNGE')
        assert.equal("#{tag} OK EXPUNGE completed")
      }

      assert_msg_uid(                      1, 3)
      assert_flag_enabled_msgs('answered',    3)
      assert_flag_enabled_msgs('flagged' ,    3)
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    ,    3)
      assert_flag_enabled_msgs('draft'   ,    3)
      assert_flag_enabled_msgs('recent'  , 1, 3)
      assert_mbox_flag_num(answered: 1, flagged: 1, deleted: 0, seen: 1, draft: 1, recent: 2)

      set_msg_flags('deleted', true, 1, 3)

      assert_msg_uid(                      1, 3)
      assert_flag_enabled_msgs('answered',    3)
      assert_flag_enabled_msgs('flagged' ,    3)
      assert_flag_enabled_msgs('deleted' , 1, 3)
      assert_flag_enabled_msgs('seen'    ,    3)
      assert_flag_enabled_msgs('draft'   ,    3)
      assert_flag_enabled_msgs('recent'  , 1, 3)
      assert_mbox_flag_num(answered: 1, flagged: 1, deleted: 2, seen: 1, draft: 1, recent: 2)

      assert_imap_command(:expunge) {|assert|
        assert.equal('* 1 EXPUNGE')
        assert.equal('* 2 EXPUNGE')
        assert.equal("#{tag} OK EXPUNGE completed")
      }

      assert_msg_uid(                      )
      assert_flag_enabled_msgs('answered', )
      assert_flag_enabled_msgs('flagged' , )
      assert_flag_enabled_msgs('deleted' , )
      assert_flag_enabled_msgs('seen'    , )
      assert_flag_enabled_msgs('draft'   , )
      assert_flag_enabled_msgs('recent'  , )
      assert_mbox_flag_num(answered: 0, flagged: 0, deleted: 0, seen: 0, draft: 0, recent: 0)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_expunge_read_only
      add_msg('')
      set_msg_flag(1, 'deleted', true)

      assert_msg_uid(1)
      assert_msg_flags(1, deleted: true, recent: true)
      assert_mbox_flag_num(deleted: 1, recent: 1)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:expunge) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:expunge) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:expunge) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_msg_uid(1)
      assert_msg_flags(1, deleted: true, recent: true)
      assert_mbox_flag_num(deleted: 1, recent: 1)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_search
      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:search, 'ALL') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:search, 'ALL') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:search, 'ALL', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      add_msg("Content-Type: text/plain\r\n" +
              "From: alice\r\n" +
              "\r\n" +
              "apple")
      add_msg('')
      add_msg("Content-Type: text/plain\r\n" +
              "From: bob\r\n" +
              "\r\n" +
              "orange")
      add_msg('')
      add_msg("Content-Type: text/plain\r\n" +
              "From: bob\r\n" +
              "\r\n" +
              "pineapple")
      expunge(2, 4)

      assert_equal([ 1, 3, 5 ], @mail_store.each_msg_uid(@inbox_id).to_a)

      assert_imap_command(:search, 'ALL', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 1').equal(' 2').equal(' 3').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'ALL', uid: true, crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 1').equal(' 3').equal(' 5').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'OR', 'FROM', 'alice', 'FROM', 'bob', 'BODY', 'apple', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 1').equal(' 3').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'OR', 'FROM', 'alice', 'FROM', 'bob', 'BODY', 'apple', uid: true, crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 1').equal(' 5').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_search_charset_body
      add_msg("Content-Type: text/plain\r\n" +
              "\r\n" +
              "foo")
      add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
              "\r\n" +
              "foo")
      add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
              "\r\n" +
              "foo")
      add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
              "\r\n" +
              "\u3053\u3093\u306B\u3061\u306F\r\n" +
              "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
              "\u3042\u3044\u3046\u3048\u304A\r\n")
      add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
              "\r\n" +
              "\e$B$3$s$K$A$O\e(B\r\n\e$B$$$m$O$K$[$X$H\e(B\r\n\e$B$\"$$$&$($*\e(B\r\n")

      assert_msg_uid(1, 2, 3, 4, 5)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'ALL') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'ALL') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'ALL', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 1').equal(' 2').equal(' 3').equal(' 4').equal(' 5').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'BODY', 'foo', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 1').equal(' 2').equal(' 3').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'BODY', 'bar', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'BODY', "\u306F\u306B\u307B".b, crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 4').equal(' 5').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_search_charset_text
      add_msg("Content-Type: text/plain\r\n" +
              "foo")
      add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
              "X-foo: dummy\r\n" +
              "\r\n" +
              "bar")
      add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
              "X-dummy: foo\r\n" +
              "\r\n" +
              "bar")
      add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
              "\r\n" +
              "\u3053\u3093\u306B\u3061\u306F\r\n" +
              "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
              "\u3042\u3044\u3046\u3048\u304A\r\n")
      add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
              "\r\n" +
              "\e$B$3$s$K$A$O\e(B\r\n\e$B$$$m$O$K$[$X$H\e(B\r\n\e$B$\"$$$&$($*\e(B\r\n")

      assert_msg_uid(1, 2, 3, 4, 5)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'ALL') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'ALL') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'ALL', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 1').equal(' 2').equal(' 3').equal(' 4').equal(' 5').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'TEXT', 'foo', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 1').equal(' 2').equal(' 3').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'TEXT', 'bar', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 2').equal(' 3').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'TEXT', 'baz', crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:search, 'CHARSET', 'utf-8', 'TEXT', "\u306F\u306B\u307B".b, crlf_at_eol: false) {|assert|
        assert.equal('* SEARCH').equal(' 4').equal(' 5').equal("\r\n")
        assert.equal("#{tag} OK SEARCH completed\r\n")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_fetch
      add_msg('')
      expunge(1)
      add_mail_simple
      add_mail_multipart

      assert_msg_uid(2, 3)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:fetch, '1:*', 'FAST') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:fetch, '1:*', 'FAST') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:fetch, '1:*', 'FAST') {|assert|
        assert.strenc_equal(%Q'* 1 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE #{@simple_mail.raw_source.bytesize})'.b)
        assert.strenc_equal(%Q'* 2 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})'.b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_imap_command(:fetch, '1:*', [ :group, 'FAST' ]) {|assert|
        assert.strenc_equal(%Q'* 1 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE #{@simple_mail.raw_source.bytesize})'.b)
        assert.strenc_equal(%Q'* 2 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})'.b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_imap_command(:fetch, '1:*', [ :group, 'FLAGS', 'RFC822.HEADER', 'UID' ]) {|assert|
        assert.strenc_equal("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@simple_mail.header.raw_source)} UID 2)".b)
        assert.strenc_equal("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@mpart_mail.header.raw_source)} UID 3)".b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: false, recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:fetch, '1', 'RFC822') {|assert|
        assert.strenc_equal("* 1 FETCH (FLAGS (\\Seen \\Recent) RFC822 #{literal(@simple_mail.raw_source)})".b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: true,  recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:fetch, '2', make_body('BODY.PEEK[1]')) {|assert|
        assert.strenc_equal(%Q'* 2 FETCH (BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")'.b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: true,  recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:fetch, '2', 'RFC822', uid: true) {|assert|
        assert.strenc_equal("* 1 FETCH (UID 2 RFC822 #{literal(@simple_mail.raw_source)})".b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: true,  recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:fetch, '3', [ :group, 'UID', make_body('BODY.PEEK[1]') ], uid: true) {|assert|
        assert.strenc_equal(%Q'* 2 FETCH (UID 3 BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")'.b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: true,  recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_fetch_read_only
      add_msg('')
      expunge(1)
      add_mail_simple
      add_mail_multipart

      assert_msg_uid(2, 3)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:fetch, '1:*', 'FAST') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:fetch, '1:*', 'FAST') {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:fetch, '1:*', 'FAST') {|assert|
        assert.strenc_equal(%Q'* 1 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE #{@simple_mail.raw_source.bytesize})'.b)
        assert.strenc_equal(%Q'* 2 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})'.b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_imap_command(:fetch, '1:*', [ :group, 'FAST' ]) {|assert|
        assert.strenc_equal(%Q'* 1 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE #{@simple_mail.raw_source.bytesize})'.b)
        assert.strenc_equal(%Q'* 2 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})'.b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_imap_command(:fetch, '1:*', [ :group, 'FLAGS', 'RFC822.HEADER', 'UID' ]) {|assert|
        assert.strenc_equal("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@simple_mail.header.raw_source)} UID 2)".b)
        assert.strenc_equal("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@mpart_mail.header.raw_source)} UID 3)".b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: false, recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:fetch, '1', 'RFC822') {|assert|
        assert.strenc_equal("* 1 FETCH (RFC822 #{literal(@simple_mail.raw_source)})".b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: false, recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:fetch, '2', make_body('BODY.PEEK[1]')) {|assert|
        assert.strenc_equal(%Q'* 2 FETCH (BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")'.b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: false, recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:fetch, '2', 'RFC822', uid: true) {|assert|
        assert.strenc_equal("* 1 FETCH (UID 2 RFC822 #{literal(@simple_mail.raw_source)})".b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: false, recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:fetch, '3', [ :group, 'UID', make_body('BODY.PEEK[1]') ], uid: true) {|assert|
        assert.strenc_equal(%Q'* 2 FETCH (UID 3 BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")'.b)
        assert.equal("#{tag} OK FETCH completed")
      }

      assert_msg_flags(2, seen: false, recent: true)
      assert_msg_flags(3, seen: false, recent: true)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_store
      msg_src = make_string_source('a')
      10.times do
        add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, recent: 5)

      assert_imap_command(:store, '1:2', '+FLAGS', [ :group, '\Flagged' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, recent: 5)

      assert_imap_command(:store, '1:3', '+FLAGS', [ :group, '\Deleted' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, recent: 5)

      assert_imap_command(:store, '1:4', '+FLAGS', [ :group, '\Seen' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Seen \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, recent: 5)

      assert_imap_command(:store, '1:5', '+FLAGS', [ :group, '\Draft' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, draft: 5, recent: 5)

      assert_imap_command(:store, '1:*', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 5, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1', '-FLAGS', [ :group, '\Answered' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1:2', '-FLAGS', [ :group, '\Flagged' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1:3', '-FLAGS', [ :group, '\Deleted' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1:4', '-FLAGS', [ :group, '\Seen' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    ,             9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 5, recent: 5)

      assert_imap_command(:store, '1:5', '-FLAGS', [ :group, '\Draft' ]) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    ,             9)
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_store_silent
      msg_src = make_string_source('a')
      10.times do
        add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS.SILENT', [ :group, '\Answered' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS.SILENT', [ :group, '\Answered' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      assert_imap_command(:store, '1', '+FLAGS.SILENT', [ :group, '\Answered' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, recent: 5)

      assert_imap_command(:store, '1:2', '+FLAGS.SILENT', [ :group, '\Flagged' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, recent: 5)

      assert_imap_command(:store, '1:3', '+FLAGS.SILENT', [ :group, '\Deleted' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, recent: 5)

      assert_imap_command(:store, '1:4', '+FLAGS.SILENT', [ :group, '\Seen' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, recent: 5)

      assert_imap_command(:store, '1:5', '+FLAGS.SILENT', [ :group, '\Draft' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, draft: 5, recent: 5)

      assert_imap_command(:store, '1:*', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 5, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1', '-FLAGS.SILENT', [ :group, '\Answered' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1:2', '-FLAGS.SILENT', [ :group, '\Flagged' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1:3', '-FLAGS.SILENT', [ :group, '\Deleted' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1:4', '-FLAGS.SILENT', [ :group, '\Seen' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    ,             9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 5, recent: 5)

      assert_imap_command(:store, '1:5', '-FLAGS.SILENT', [ :group, '\Draft' ]) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    ,             9)
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_uid_store
      msg_src = make_string_source('a')
      10.times do
        add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, recent: 5)

      assert_imap_command(:store, '1,3', '+FLAGS', [ :group, '\Flagged' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, recent: 5)

      assert_imap_command(:store, '1,3,5', '+FLAGS', [ :group, '\Deleted' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, recent: 5)

      assert_imap_command(:store, '1,3,5,7', '+FLAGS', [ :group, '\Seen' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Seen \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, recent: 5)

      assert_imap_command(:store, '1,3,5,7,9', '+FLAGS', [ :group, '\Draft' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, draft: 5, recent: 5)

      assert_imap_command(:store, '1:*', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 5, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1', '-FLAGS', [ :group, '\Answered' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1,3', '-FLAGS', [ :group, '\Flagged' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1,3,5', '-FLAGS', [ :group, '\Deleted' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1,3,5,7', '-FLAGS', [ :group, '\Seen' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    ,             9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 5, recent: 5)

      assert_imap_command(:store, '1,3,5,7,9', '-FLAGS', [ :group, '\Draft' ], uid: true) {|assert|
        assert.equal('* 1 FETCH FLAGS (\Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    ,             9)
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_uid_store_silent
      msg_src = make_string_source('a')
      10.times do
        add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      assert_imap_command(:store, '1', '+FLAGS.SILENT', [ :group, '\Answered' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, recent: 5)

      assert_imap_command(:store, '1,3', '+FLAGS.SILENT', [ :group, '\Flagged' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, recent: 5)

      assert_imap_command(:store, '1,3,5', '+FLAGS.SILENT', [ :group, '\Deleted' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, recent: 5)

      assert_imap_command(:store, '1,3,5,7', '+FLAGS.SILENT', [ :group, '\Seen' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, recent: 5)

      assert_imap_command(:store, '1,3,5,7,9', '+FLAGS.SILENT', [ :group, '\Draft' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1            )
      assert_flag_enabled_msgs('flagged' , 1, 3         )
      assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, draft: 5, recent: 5)

      assert_imap_command(:store, '1:*', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered', 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 5, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1', '-FLAGS.SILENT', [ :group, '\Answered' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1,3', '-FLAGS.SILENT', [ :group, '\Flagged' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 5, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1,3,5', '-FLAGS.SILENT', [ :group, '\Deleted' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 5, draft: 5, recent: 5)

      assert_imap_command(:store, '1,3,5,7', '-FLAGS.SILENT', [ :group, '\Seen' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    ,             9)
      assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 5, recent: 5)

      assert_imap_command(:store, '1,3,5,7,9', '-FLAGS.SILENT', [ :group, '\Draft' ], uid: true) {|assert|
        assert.equal("#{tag} OK STORE completed")
      }

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
      assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,          7, 9)
      assert_flag_enabled_msgs('seen'    ,             9)
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_store_read_only
      add_msg('')
      set_msg_flag(1, 'flagged', true)
      set_msg_flag(1, 'seen', true)

      assert_msg_uid(1)
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted',  '\Seen','\Draft' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', '-FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', '+FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', '-FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', 'FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', '-FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', '+FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', 'FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:store, '1', '-FLAGS.SILENT', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ], uid: true) {|assert|
        assert.match(/^#{tag} NO /)
      }
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_copy
      msg_src = make_string_source('a')
      10.times do
        uid = add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)
      set_msg_flags('flagged', true, 1, 3, 5, 7, 9)
      work_id = @mail_store.add_mbox('WORK')

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       mbox_id: work_id)
      assert_flag_enabled_msgs('answered',  mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,  mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,  mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  mbox_id: work_id)
      assert_mbox_flag_num(                 mbox_id: work_id)
      assert_msg_text(                      mbox_id: work_id)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:copy, '2:4', 'WORK') {|assert|
        assert.match(/^#{tag} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:copy, '2:4', 'WORK') {|assert|
        assert.match(/^#{tag} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       mbox_id: work_id)
      assert_flag_enabled_msgs('answered',  mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,  mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,  mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  mbox_id: work_id)
      assert_mbox_flag_num(                 mbox_id: work_id)
      assert_msg_text(                      mbox_id: work_id)

      assert_imap_command(:copy, '2:4', 'WORK') {|assert|
        assert.equal("#{tag} OK COPY completed")
      }

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       1, 2, 3, mbox_id: work_id)
      assert_flag_enabled_msgs('answered',           mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  1, 2, 3, mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,           mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,           mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,           mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  1, 2, 3, mbox_id: work_id)
      assert_mbox_flag_num(flagged: 3, recent: 3,    mbox_id: work_id)
      assert_msg_text('c', 'e', 'g',                 mbox_id: work_id)

      # duplicted message copy
      assert_imap_command(:copy, '2:4', 'WORK') {|assert|
        assert.equal("#{tag} OK COPY completed")
      }

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('answered',                    mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_mbox_flag_num(flagged: 6, recent: 6,             mbox_id: work_id)
      assert_msg_text('c', 'e', 'g', 'c', 'e', 'g',           mbox_id: work_id)

      # copy of empty messge set
      assert_imap_command(:copy, '100', 'WORK') {|assert|
        assert.equal("#{tag} OK COPY completed")
      }

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('answered',                    mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_mbox_flag_num(flagged: 6, recent: 6,             mbox_id: work_id)
      assert_msg_text('c', 'e', 'g', 'c', 'e', 'g',           mbox_id: work_id)

      assert_imap_command(:copy, '1:*', 'nobox') {|assert|
        assert.match(/^#{tag} NO \[TRYCREATE\]/)
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_uid_copy
      msg_src = make_string_source('a')
      10.times do
        uid = add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)
      set_msg_flags('flagged', true, 1, 3, 5, 7, 9)
      work_id = @mail_store.add_mbox('WORK')

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       mbox_id: work_id)
      assert_flag_enabled_msgs('answered',  mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,  mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,  mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  mbox_id: work_id)
      assert_mbox_flag_num(                 mbox_id: work_id)
      assert_msg_text(                      mbox_id: work_id)

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:copy, '3,5,7', 'WORK', uid: true) {|assert|
        assert.match(/^#{tag} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:copy, '3,5,7', 'WORK', uid: true) {|assert|
        assert.match(/^#{tag} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       mbox_id: work_id)
      assert_flag_enabled_msgs('answered',  mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,  mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,  mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  mbox_id: work_id)
      assert_mbox_flag_num(                 mbox_id: work_id)
      assert_msg_text(                      mbox_id: work_id)

      assert_imap_command(:copy, '3,5,7', 'WORK', uid: true) {|assert|
        assert.equal("#{tag} OK COPY completed")
      }

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       1, 2, 3, mbox_id: work_id)
      assert_flag_enabled_msgs('answered',           mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  1, 2, 3, mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,           mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,           mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,           mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  1, 2, 3, mbox_id: work_id)
      assert_mbox_flag_num(flagged: 3, recent: 3,    mbox_id: work_id)
      assert_msg_text('c', 'e', 'g',                 mbox_id: work_id)

      # duplicted message copy
      assert_imap_command(:copy, '3,5,7', 'WORK', uid: true) {|assert|
        assert.equal("#{tag} OK COPY completed")
      }

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('answered',                    mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_mbox_flag_num(flagged: 6, recent: 6,             mbox_id: work_id)
      assert_msg_text('c', 'e', 'g', 'c', 'e', 'g',           mbox_id: work_id)

      # copy of empty messge set
      assert_imap_command(:copy, '100', 'WORK', uid: true) {|assert|
        assert.equal("#{tag} OK COPY completed")
      }

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('answered',                    mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_mbox_flag_num(flagged: 6, recent: 6,             mbox_id: work_id)
      assert_msg_text('c', 'e', 'g', 'c', 'e', 'g',           mbox_id: work_id)

      assert_imap_command(:copy, '1:*', 'nobox', uid: true) {|assert|
        assert.match(/^#{tag} NO \[TRYCREATE\]/)
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_copy_utf7_mbox_name
      add_msg('Hello world.')
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_msg_uid(1)
      assert_msg_uid(mbox_id: utf8_name_mbox_id)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_msg_uid(1)
      assert_msg_uid(mbox_id: utf8_name_mbox_id)

      assert_imap_command(:copy, '1', UTF7_MBOX_NAME) {|assert|
        assert.equal("#{tag} OK COPY completed")
      }

      assert_msg_uid(1)
      assert_msg_uid(1, mbox_id: utf8_name_mbox_id)
      assert_equal('Hello world.', get_msg_text(1, mbox_id: utf8_name_mbox_id))

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }
    end

    def test_noop
      add_msg('')

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:noop) {|assert|
        assert.equal("#{tag} OK NOOP completed")
      }

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:noop) {|assert|
        assert.equal("#{tag} OK NOOP completed")
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* /}
        assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:noop) {|assert|
        assert.equal('* 1 EXISTS')
        assert.equal('* 1 RECENTS')
        assert.equal("#{tag} OK NOOP completed")
      }

      assert_imap_command(:close) {|assert|
        assert.equal("#{tag} OK CLOSE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(false, @decoder.selected?)

      assert_imap_command(:noop) {|assert|
        assert.equal("#{tag} OK NOOP completed")
      }

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.skip_while{|line| line =~ /^\* /}
        assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
      }

      assert_equal(true, @decoder.auth?)
      assert_equal(true, @decoder.selected?)

      assert_imap_command(:noop) {|assert|
        assert.equal('* 1 EXISTS')
        assert.equal('* 0 RECENTS')
        assert.equal("#{tag} OK NOOP completed")
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
      assert_equal(false, @decoder.selected?)
    end

    def test_db_recovery
      reload_mail_store{
        meta_db = RIMS::DB::Meta.new(RIMS::Hash_KeyValueStore.new(@kvs["#{RIMS::MAILBOX_DATA_STRUCTURE_VERSION}/#{@unique_user_id[0, 7]}/meta"]))
        meta_db.dirty = true
        meta_db.close
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, 'foo', 'open_sesame') {|assert|
        assert.match(/^\* OK \[ALERT\] recovery/)
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
    end

    def test_mail_delivery_user
      assert_imap_command(:capability) {|assert|
        assert.match(/^\* CAPABILITY /, peek_next_line: true).no_match(/ X-RIMS-MAIL-DELIVERY-USER/)
        assert.equal("#{tag} OK CAPABILITY completed")
      }

      assert_equal(false, @decoder.auth?)

      assert_imap_command(:login, '#postman', 'password_of_mail_delivery_user') {|assert|
        assert.equal("#{tag} OK LOGIN completed")
      }

      assert_equal(true, @decoder.auth?)

      assert_imap_command(:capability) {|assert|
        assert.match(/^\* CAPABILITY /, peek_next_line: true).match(/ X-RIMS-MAIL-DELIVERY-USER/)
        assert.equal("#{tag} OK CAPABILITY completed")
      }

      assert_imap_command(:select, 'INBOX') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:examine, 'INBOX') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:create, 'foo') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:delete, 'foo') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:rename, 'foo', 'bar') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:subscribe, 'foo') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:unsubscribe, 'foo') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:list, '', '*') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:lsub, '', '*') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:status, 'INBOX', [ :group, 'MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN' ]) {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:check) {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:close) {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:expunge) {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:search, '*') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:fetch, '*', 'RFC822') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:store, '1', '+FLAGS', [ :group, '\Answered', '\Flagged', '\Deleted', '\Seen', '\Draft' ]) {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:copy, '*', 'foo') {|assert|
        assert.match(/#{tag} NO not allowed command/)
      }

      assert_imap_command(:logout) {|assert|
        assert.match(/^\* BYE /)
        assert.equal("#{tag} OK LOGOUT completed")
      }

      assert_equal(false, @decoder.auth?)
    end

    def test_command_loop_empty
      assert_imap_command_loop(''.b, autotag: false) {|assert|
	assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
      }

      assert_imap_command_loop("\n\t\n \r\n ".b, autotag: false) {|assert|
	assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
      }
    end

    def test_command_loop_capability
      cmd_txt = <<-'EOF'.b
CAPABILITY
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal('* CAPABILITY IMAP4rev1 AUTH=PLAIN AUTH=CRAM-MD5')
        assert.equal("#{tag!} OK CAPABILITY completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_authenticate_plain_inline
      cmd_txt = <<-"EOF".b
AUTHENTICATE plain #{client_plain_response_base64('foo', 'detarame')}
AUTHENTICATE plain #{client_plain_response_base64('foo', 'open_sesame')}
AUTHENTICATE plain #{client_plain_response_base64('foo', 'open_sesame')}
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK AUTHENTICATE plain success")
        assert.match(/^#{tag!} NO /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_authenticate_plain_stream
      cmd_txt = <<-"EOF".b
T001 AUTHENTICATE plain
*
T002 AUTHENTICATE plain
#{client_plain_response_base64('foo', 'detarame')}
T003 AUTHENTICATE plain
#{client_plain_response_base64('foo', 'open_sesame')}
T004 AUTHENTICATE plain
T005 LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt, autotag: false) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal('+ ')
        assert.match(/^#{tag!} BAD /)
        assert.equal('+ ')
        assert.match(/^#{tag!} NO /)
        assert.equal('+ ')
        assert.equal("#{tag!} OK AUTHENTICATE plain success")
        assert.match(/^#{tag!} NO /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_authenticate_cram_md5_stream
      server_client_data_base64_pair_list = [
        make_cram_md5_server_client_data_base64('foo', 'open_sesame'),
        make_cram_md5_server_client_data_base64('foo', 'detarame'),
        make_cram_md5_server_client_data_base64('foo', 'open_sesame')
      ]

      cmd_txt = <<-"EOF".b
T001 AUTHENTICATE cram-md5
*
T002 AUTHENTICATE cram-md5
#{server_client_data_base64_pair_list[1][1]}
T003 AUTHENTICATE cram-md5
#{server_client_data_base64_pair_list[2][1]}
T004 AUTHENTICATE cram-md5
T005 LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt, autotag: false) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("+ #{server_client_data_base64_pair_list[0][0]}")
        assert.match(/^#{tag!} BAD /)
        assert.equal("+ #{server_client_data_base64_pair_list[1][0]}")
        assert.match(/^#{tag!} NO /)
        assert.equal("+ #{server_client_data_base64_pair_list[2][0]}")
        assert.equal("#{tag!} OK AUTHENTICATE cram-md5 success")
        assert.match(/^#{tag!} NO /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_login
      cmd_txt = <<-'EOF'.b
LOGIN foo detarame
LOGIN foo open_sesame
LOGIN foo open_sesame
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO/)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_select
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      cmd_txt = <<-'EOF'.b
SELECT INBOX
LOGIN foo open_sesame
SELECT INBOX
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    , 2   )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  ,     )
      assert_mbox_flag_num(seen: 1)
    end

    def test_command_loop_select_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
SELECT "#{UTF7_MBOX_NAME}"
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal('* 0 EXISTS')
        assert.equal('* 0 RECENT')
        assert.equal('* OK [UNSEEN 0]')
        assert.equal("* OK [UIDVALIDITY #{utf8_name_mbox_id}]")
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_examine
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      cmd_txt = <<-'EOF'.b
EXAMINE INBOX
LOGIN foo open_sesame
EXAMINE INBOX
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag!} OK [READ-ONLY] EXAMINE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)
    end

    def test_command_loop_examine_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
EXAMINE "#{UTF7_MBOX_NAME}"
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal('* 0 EXISTS')
        assert.equal('* 0 RECENT')
        assert.equal('* OK [UNSEEN 0]')
        assert.equal("* OK [UIDVALIDITY #{utf8_name_mbox_id}]")
        assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
        assert.equal("#{tag!} OK [READ-ONLY] EXAMINE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_create
      assert_mbox_not_exists('foo')

      cmd_txt = <<-'EOF'.b
CREATE foo
LOGIN foo open_sesame
CREATE foo
CREATE inbox
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK CREATE completed")
        assert.match(/^#{tag!} NO /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_mbox_exists('foo')
    end

    def test_command_loop_create_utf7_mbox_name
      assert_mbox_not_exists(UTF8_MBOX_NAME)

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
CREATE "#{UTF7_MBOX_NAME}"
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK CREATE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_mbox_exists(UTF8_MBOX_NAME)
    end

    def test_command_loop_delete
      @mail_store.add_mbox('foo')

      assert_mbox_exists('inbox')
      assert_mbox_exists('foo')
      assert_mbox_not_exists('bar')

      cmd_txt = <<-'EOF'.b
DELETE foo
LOGIN foo open_sesame
DELETE foo
DELETE bar
DELETE inbox
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK DELETE completed")
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_mbox_exists('inbox')
      assert_mbox_not_exists('foo')
      assert_mbox_not_exists('bar')
    end

    def test_command_loop_delete_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_mbox_exists(UTF8_MBOX_NAME)

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
DELETE "#{UTF7_MBOX_NAME}"
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK DELETE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_mbox_not_exists(UTF8_MBOX_NAME)
    end

    def test_command_loop_rename
      mbox_id = @mail_store.add_mbox('foo')

      assert_equal([ mbox_id, nil, @inbox_id ], get_mbox_id_list('foo', 'bar', 'INBOX'))

      cmd_txt = <<-'EOF'.b
RENAME foo bar
LOGIN foo open_sesame
RENAME foo bar
RENAME nobox baz
RENAME INBOX baz
RENAME bar inbox
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK RENAME completed")
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_equal([ nil, mbox_id, @inbox_id ], get_mbox_id_list('foo', 'bar', 'INBOX'))
    end

    def test_command_loop_rename_utf7_mbox_name
      mbox_id = @mail_store.add_mbox('foo')

      assert_equal([ mbox_id, nil, nil ], get_mbox_id_list('foo', UTF8_MBOX_NAME, 'bar'))

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
RENAME foo "#{UTF7_MBOX_NAME}"
RENAME "#{UTF7_MBOX_NAME}" bar
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK RENAME completed")
        assert.equal("#{tag!} OK RENAME completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_equal([ nil, nil, mbox_id ], get_mbox_id_list('foo', UTF8_MBOX_NAME, 'bar'))
    end

    def test_command_loop_list
      add_msg('foo')
      @mail_store.add_mbox('foo')

      cmd_txt = <<-'EOF'.b
LIST "" ""
LOGIN foo open_sesame
LIST "" ""
LIST "" *
LIST "" f*
LIST IN *
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal('* LIST (\Noselect) NIL ""')
        assert.equal("#{tag!} OK LIST completed")
        assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
        assert.equal("#{tag!} OK LIST completed")
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
        assert.equal("#{tag!} OK LIST completed")
        assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
        assert.equal("#{tag!} OK LIST completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_list_utf7_mbox_name
      @mail_store.add_mbox(UTF8_MBOX_NAME)

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
LIST "#{encode_utf7(UTF8_MBOX_NAME[0..6])}" "#{'*' + encode_utf7(UTF8_MBOX_NAME[12..14]) + '*'}"
LIST "#{encode_utf7(UTF8_MBOX_NAME[0..13])}" "#{'*' + encode_utf7(UTF8_MBOX_NAME[16]) + '*'}"
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "~peter/mail/&ZeVnLIqe-/&U,BTFw-"')
        assert.equal("#{tag!} OK LIST completed")
        assert.equal('* LIST (\Noinferiors \Unmarked) NIL "~peter/mail/&ZeVnLIqe-/&U,BTFw-"')
        assert.equal("#{tag!} OK LIST completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_status
      add_msg('')
      add_msg('')
      set_msg_flag(1, 'recent', false)
      set_msg_flag(1, 'seen',   true)

      cmd_txt = <<-'EOF'.b
STATUS nobox (MESSAGES)
LOGIN foo open_sesame
STATUS nobox (MESSAGES)
STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)
STATUS INBOX MESSAGES
STATUS INBOX (DETARAME)
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.equal("* STATUS \"INBOX\" (MESSAGES 2 RECENT 1 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
        assert.equal("#{tag!} OK STATUS completed")
        assert.match(/^#{tag!} BAD /)
        assert.match(/^#{tag!} BAD /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_status_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
STATUS "#{UTF7_MBOX_NAME}" (UIDVALIDITY MESSAGES RECENT UNSEEN)
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal(%Q'* STATUS "#{UTF7_MBOX_NAME}" (UIDVALIDITY #{utf8_name_mbox_id} MESSAGES 0 RECENT 0 UNSEEN 0)')
        assert.equal("#{tag!} OK STATUS completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_append
      cmd_txt = <<-'EOF'.b
T001 APPEND INBOX a
T002 LOGIN foo open_sesame
T003 APPEND INBOX a
T004 APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) "b"
T005 APPEND INBOX "19-Nov-1975 12:34:56 +0900" {1}
c
T006 APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) "19-Nov-1975 12:34:56 +0900" d
T007 APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) "19-Nov-1975 12:34:56 +0900" NIL x
T008 APPEND INBOX "19-Nov-1975 12:34:56 +0900" (\Answered \Flagged \Deleted \Seen \Draft) x
T009 APPEND INBOX (\Recent) x
T010 APPEND INBOX "bad date-time" x
T011 APPEND nobox x
T012 LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt, autotag: false) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK APPEND completed")
        assert.equal("#{tag!} OK APPEND completed")
        assert.match(/^\+ /)
        assert.equal("#{tag!} OK APPEND completed")
        assert.equal("#{tag!} OK APPEND completed")
        assert.match(/^#{tag!} BAD /)
        assert.match(/^#{tag!} BAD /)
        assert.match(/^#{tag!} BAD /)
        assert.match(/^#{tag!} BAD /)
        assert.match(/^#{tag!} NO \[TRYCREATE\]/)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      1, 2, 3, 4)
      assert_flag_enabled_msgs('answered',    2,    4)
      assert_flag_enabled_msgs('flagged' ,    2,    4)
      assert_flag_enabled_msgs('deleted' ,    2,    4)
      assert_flag_enabled_msgs('seen'    ,    2,    4)
      assert_flag_enabled_msgs('draft'   ,    2,    4)
      assert_flag_enabled_msgs('recent'  , 1, 2, 3, 4)
      assert_mbox_flag_num(answered: 2, flagged: 2, deleted: 2, seen: 2, draft: 2, recent: 4)
      assert_msg_text('a', 'b', 'c', 'd')
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(3))
      assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(4))
    end

    def test_command_loop_append_utf7_mbox_name
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
APPEND "#{UTF7_MBOX_NAME}" "Hello world."
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK APPEND completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(1, mbox_id: utf8_name_mbox_id)
      assert_equal('Hello world.', get_msg_text(1, mbox_id: utf8_name_mbox_id))
    end

    def test_command_loop_check
      cmd_txt = <<-'EOF'.b
CHECK
LOGIN foo open_sesame
CHECK
SELECT INBOX
CHECK
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal("#{tag!} OK CHECK completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_close
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      cmd_txt = <<-'EOF'.b
CLOSE
LOGIN foo open_sesame
CLOSE
SELECT INBOX
CLOSE
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)')
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal("#{tag!} OK CLOSE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    , 2   )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  ,     )
      assert_mbox_flag_num(seen: 1)
    end

    def test_command_loop_close_read_only
      add_msg('')
      add_msg('')
      add_msg('')
      set_msg_flags('recent',  false, 1, 2)
      set_msg_flags('seen',    true,  1, 2)
      set_msg_flags('deleted', true,  1)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)

      cmd_txt = <<-'EOF'.b
CLOSE
LOGIN foo open_sesame
CLOSE
EXAMINE INBOX
CLOSE
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.equal('* 3 EXISTS')
        assert.equal('* 1 RECENT')
        assert.equal('* OK [UNSEEN 1]')
        assert.equal('* OK [UIDVALIDITY 1]')
        assert.equal('* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)')
        assert.equal("#{tag!} OK [READ-ONLY] EXAMINE completed")
        assert.equal("#{tag!} OK CLOSE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',        )
      assert_flag_enabled_msgs('flagged' ,        )
      assert_flag_enabled_msgs('deleted' , 1      )
      assert_flag_enabled_msgs('seen'    , 1, 2   )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,       3)
      assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)
    end

    def test_command_loop_expunge
      add_msg('a')
      add_msg('b')
      add_msg('c')
      set_msg_flags('answered', true, 2, 3)
      set_msg_flags('flagged',  true, 2, 3)
      set_msg_flags('deleted',  true, 2)
      set_msg_flags('seen',     true, 2, 3)
      set_msg_flags('draft',    true, 2, 3)

      assert_msg_uid(                      1, 2, 3)
      assert_flag_enabled_msgs('answered',    2, 3)
      assert_flag_enabled_msgs('flagged' ,    2, 3)
      assert_flag_enabled_msgs('deleted' ,    2   )
      assert_flag_enabled_msgs('seen'    ,    2, 3)
      assert_flag_enabled_msgs('draft'   ,    2, 3)
      assert_flag_enabled_msgs('recent'  , 1, 2, 3)
      assert_mbox_flag_num(answered: 2, flagged: 2, deleted: 1, seen: 2, draft: 2, recent: 3)

      cmd_txt = <<-'EOF'.b
EXPUNGE
LOGIN foo open_sesame
EXPUNGE
SELECT INBOX
EXPUNGE
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal('* 2 EXPUNGE')
        assert.equal("#{tag!} OK EXPUNGE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      1, 3)
      assert_flag_enabled_msgs('answered',    3)
      assert_flag_enabled_msgs('flagged' ,    3)
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    ,    3)
      assert_flag_enabled_msgs('draft'   ,    3)
      assert_flag_enabled_msgs('recent'  ,     )
      assert_mbox_flag_num(answered: 1, flagged: 1, seen: 1, draft: 1)
    end

    def test_command_loop_expunge_read_only
      add_msg('a')
      set_msg_flag(1, 'deleted', true)

      assert_msg_uid(1)
      assert_msg_flags(1, deleted: true, recent: true)

      cmd_txt = <<-'EOF'.b
EXPUNGE
LOGIN foo open_sesame
EXPUNGE
EXAMINE INBOX
EXPUNGE
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-ONLY] EXAMINE completed")
        assert.match(/^#{tag!} NO /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(1)
      assert_msg_flags(1, deleted: true, recent: true)
    end

    def test_command_loop_search
      add_msg("Content-Type: text/plain\r\n" +
              "From: alice\r\n" +
              "\r\n" +
              "apple")
      add_msg('')
      add_msg("Content-Type: text/plain\r\n" +
              "From: bob\r\n" +
              "\r\n" +
              "orange")
      add_msg('')
      add_msg("Content-Type: text/plain\r\n" +
              "From: bob\r\n" +
              "\r\n" +
              "pineapple")
      expunge(2, 4)

      assert_msg_uid(1, 3, 5)

      cmd_txt = <<-'EOF'.b
SEARCH ALL
LOGIN foo open_sesame
SEARCH ALL
SELECT INBOX
SEARCH ALL
UID SEARCH ALL
SEARCH OR FROM alice FROM bob BODY apple
UID SEARCH OR FROM alice FROM bob BODY apple
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal('* SEARCH 1 2 3')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH 1 3 5')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH 1 3')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH 1 5')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_search_charset_body
      add_msg("Content-Type: text/plain\r\n" +
              "\r\n" +
              "foo")
      add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
              "\r\n" +
              "foo")
      add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
              "\r\n" +
              "foo")
      add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
              "\r\n" +
              "\u3053\u3093\u306B\u3061\u306F\r\n" +
              "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
              "\u3042\u3044\u3046\u3048\u304A\r\n")
      add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
              "\r\n" +
              "\e$B$3$s$K$A$O\e(B\r\n\e$B$$$m$O$K$[$X$H\e(B\r\n\e$B$\"$$$&$($*\e(B\r\n")

      assert_msg_uid(1, 2, 3, 4, 5)

      cmd_txt = <<-"EOF".b
SEARCH CHARSET "utf-8" ALL
LOGIN foo open_sesame
SEARCH CHARSET "utf-8" ALL
SELECT INBOX
SEARCH CHARSET "utf-8" ALL
SEARCH CHARSET "utf-8" BODY foo
SEARCH CHARSET "utf-8" BODY bar
SEARCH CHARSET "utf-8" BODY "\u306F\u306B\u307B"
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal('* SEARCH 1 2 3 4 5')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH 1 2 3')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH 4 5')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_search_charset_text
      add_msg("Content-Type: text/plain\r\n" +
              "foo")
      add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
              "X-foo: dummy\r\n" +
              "\r\n" +
              "bar")
      add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
              "X-dummy: foo\r\n" +
              "\r\n" +
              "bar")
      add_msg("Content-Type: text/plain; charset=utf-8\r\n" +
              "\r\n" +
              "\u3053\u3093\u306B\u3061\u306F\r\n" +
              "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
              "\u3042\u3044\u3046\u3048\u304A\r\n")
      add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
              "\r\n" +
              "\e$B$3$s$K$A$O\e(B\r\n\e$B$$$m$O$K$[$X$H\e(B\r\n\e$B$\"$$$&$($*\e(B\r\n")

      assert_msg_uid(1, 2, 3, 4, 5)

      cmd_txt = <<-"EOF".b
SEARCH CHARSET "utf-8" ALL
LOGIN foo open_sesame
SEARCH CHARSET "utf-8" ALL
SELECT INBOX
SEARCH CHARSET "utf-8" ALL
SEARCH CHARSET "utf-8" TEXT foo
SEARCH CHARSET "utf-8" TEXT bar
SEARCH CHARSET "utf-8" TEXT baz
SEARCH CHARSET "utf-8" TEXT "\u306F\u306B\u307B"
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal('* SEARCH 1 2 3 4 5')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH 1 2 3')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH 2 3')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.equal('* SEARCH 4 5')
        assert.equal("#{tag!} OK SEARCH completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_fetch
      add_msg('')
      add_mail_simple
      add_mail_multipart
      expunge(1)

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    ,     )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  , 2, 3)
      assert_mbox_flag_num(recent: 2)

      cmd_txt = <<-'EOF'.b
FETCH 1:* FAST
LOGIN foo open_sesame
FETCH 1:* FAST
SELECT INBOX
FETCH 1:* FAST
FETCH 1:* (FAST)
FETCH 1:* (FLAGS RFC822.HEADER UID)
FETCH 1 RFC822
FETCH 2 BODY.PEEK[1]
UID FETCH 2 RFC822
UID FETCH 3 (UID BODY.PEEK[1])
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE 203)')
        assert.equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE 1545)')
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE 203)')
        assert.equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE 1545)')
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal_lines("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@simple_mail.header.raw_source)} UID 2)")
        assert.equal_lines("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@mpart_mail.header.raw_source)} UID 3)")
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal_lines("* 1 FETCH (FLAGS (\\Seen \\Recent) RFC822 #{literal(@simple_mail.raw_source)})")
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal(%Q'* 2 FETCH (BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")')
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal_lines("* 1 FETCH (UID 2 RFC822 #{literal(@simple_mail.raw_source)})")
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal(%Q'* 2 FETCH (UID 3 BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")')
        assert.equal("#{tag!} OK FETCH completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    , 2   )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  ,     )
      assert_mbox_flag_num(seen: 1)
    end

    def test_command_loop_fetch_read_only
      add_msg('')
      add_mail_simple
      add_mail_multipart
      expunge(1)

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    ,     )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  , 2, 3)
      assert_mbox_flag_num(recent: 2)

      cmd_txt = <<-'EOF'.b
FETCH 1:* FAST
LOGIN foo open_sesame
FETCH 1:* FAST
EXAMINE INBOX
FETCH 1:* FAST
FETCH 1:* (FAST)
FETCH 1:* (FLAGS RFC822.HEADER UID)
FETCH 1 RFC822
FETCH 2 BODY.PEEK[1]
UID FETCH 2 RFC822
UID FETCH 3 (UID BODY.PEEK[1])
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-ONLY] EXAMINE completed")
        assert.equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE 203)')
        assert.equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE 1545)')
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal('* 1 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE 203)')
        assert.equal('* 2 FETCH (FLAGS (\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE 1545)')
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal_lines("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@simple_mail.header.raw_source)} UID 2)")
        assert.equal_lines("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@mpart_mail.header.raw_source)} UID 3)")
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal_lines("* 1 FETCH (RFC822 #{literal(@simple_mail.raw_source)})")
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal(%Q'* 2 FETCH (BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")')
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal_lines("* 1 FETCH (UID 2 RFC822 #{literal(@simple_mail.raw_source)})")
        assert.equal("#{tag!} OK FETCH completed")
        assert.equal(%Q'* 2 FETCH (UID 3 BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")')
        assert.equal("#{tag!} OK FETCH completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      2, 3)
      assert_flag_enabled_msgs('answered',     )
      assert_flag_enabled_msgs('flagged' ,     )
      assert_flag_enabled_msgs('deleted' ,     )
      assert_flag_enabled_msgs('seen'    ,     )
      assert_flag_enabled_msgs('draft'   ,     )
      assert_flag_enabled_msgs('recent'  , 2, 3)
      assert_mbox_flag_num(recent: 2)
    end

    def test_command_loop_store
      msg_src = make_string_source('a')
      10.times do
        add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      cmd_txt = <<-'EOF'.b
STORE 1 +FLAGS (\Answered)
LOGIN foo open_sesame
STORE 1 +FLAGS (\Answered)
SELECT INBOX
STORE 1 +FLAGS (\Answered)
STORE 1:2 +FLAGS (\Flagged)
STORE 1:3 +FLAGS (\Deleted)
STORE 1:4 +FLAGS (\Seen)
STORE 1:5 +FLAGS (\Draft)
STORE 1:* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
STORE 1 -FLAGS (\Answered)
STORE 1:2 -FLAGS (\Flagged)
STORE 1:3 -FLAGS (\Deleted)
STORE 1:4 -FLAGS (\Seen)
STORE 1:5 -FLAGS (\Draft)
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Seen \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      1, 3, 5)
      assert_flag_enabled_msgs('answered',    3, 5)
      assert_flag_enabled_msgs('flagged' ,       5)
      assert_flag_enabled_msgs('deleted' ,        )
      assert_flag_enabled_msgs('seen'    ,        )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,        )
      assert_mbox_flag_num(answered: 2, flagged: 1)
    end

    def test_command_loop_store_silent
      msg_src = make_string_source('a')
      10.times do
        add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      cmd_txt = <<-'EOF'.b
STORE 1 +FLAGS.SILENT (\Answered)
LOGIN foo open_sesame
STORE 1 +FLAGS.SILENT (\Answered)
SELECT INBOX
STORE 1 +FLAGS.SILENT (\Answered)
STORE 1:2 +FLAGS.SILENT (\Flagged)
STORE 1:3 +FLAGS.SILENT (\Deleted)
STORE 1:4 +FLAGS.SILENT (\Seen)
STORE 1:5 +FLAGS.SILENT (\Draft)
STORE 1:* FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
STORE 1 -FLAGS.SILENT (\Answered)
STORE 1:2 -FLAGS.SILENT (\Flagged)
STORE 1:3 -FLAGS.SILENT (\Deleted)
STORE 1:4 -FLAGS.SILENT (\Seen)
STORE 1:5 -FLAGS.SILENT (\Draft)
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      1, 3, 5)
      assert_flag_enabled_msgs('answered',    3, 5)
      assert_flag_enabled_msgs('flagged' ,       5)
      assert_flag_enabled_msgs('deleted' ,        )
      assert_flag_enabled_msgs('seen'    ,        )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,        )
      assert_mbox_flag_num(answered: 2, flagged: 1)
    end

    def test_command_loop_uid_store
      msg_src = make_string_source('a')
      10.times do
        add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      cmd_txt = <<-'EOF'.b
UID STORE 1 +FLAGS (\Answered)
LOGIN foo open_sesame
UID STORE 1 +FLAGS (\Answered)
SELECT INBOX
UID STORE 1 +FLAGS (\Answered)
UID STORE 1,3 +FLAGS (\Flagged)
UID STORE 1,3,5 +FLAGS (\Deleted)
UID STORE 1,3,5,7 +FLAGS (\Seen)
UID STORE 1,3,5,7,9 +FLAGS (\Draft)
UID STORE 1:* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
UID STORE 1 -FLAGS (\Answered)
UID STORE 1,3 -FLAGS (\Flagged)
UID STORE 1,3,5 -FLAGS (\Deleted)
UID STORE 1,3,5,7 -FLAGS (\Seen)
UID STORE 1,3,5,7,9 -FLAGS (\Draft)
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Seen \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Seen \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Seen \Draft \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Flagged \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Deleted \Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Deleted \Seen \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Seen \Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Seen \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Seen \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Draft \Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Draft \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Draft \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Draft \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.equal('* 1 FETCH FLAGS (\Recent)')
        assert.equal('* 2 FETCH FLAGS (\Answered \Recent)')
        assert.equal('* 3 FETCH FLAGS (\Answered \Flagged \Recent)')
        assert.equal('* 4 FETCH FLAGS (\Answered \Flagged \Deleted \Recent)')
        assert.equal('* 5 FETCH FLAGS (\Answered \Flagged \Deleted \Seen \Recent)')
        assert.equal("#{tag!} OK STORE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      1, 3, 5)
      assert_flag_enabled_msgs('answered',    3, 5)
      assert_flag_enabled_msgs('flagged' ,       5)
      assert_flag_enabled_msgs('deleted' ,        )
      assert_flag_enabled_msgs('seen'    ,        )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,        )
      assert_mbox_flag_num(answered: 2, flagged: 1)
    end

    def test_command_loop_uid_store_silent
      msg_src = make_string_source('a')
      10.times do
        add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)

      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' ,              )
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(recent: 5)

      cmd_txt = <<-'EOF'.b
UID STORE 1 +FLAGS.SILENT (\Answered)
LOGIN foo open_sesame
UID STORE 1 +FLAGS.SILENT (\Answered)
SELECT INBOX
UID STORE 1 +FLAGS.SILENT (\Answered)
UID STORE 1,3 +FLAGS.SILENT (\Flagged)
UID STORE 1,3,5 +FLAGS.SILENT (\Deleted)
UID STORE 1,3,5,7 +FLAGS.SILENT (\Seen)
UID STORE 1,3,5,7,9 +FLAGS.SILENT (\Draft)
UID STORE 1:* FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
UID STORE 1 -FLAGS.SILENT (\Answered)
UID STORE 1,3 -FLAGS.SILENT (\Flagged)
UID STORE 1,3,5 -FLAGS.SILENT (\Deleted)
UID STORE 1,3,5,7 -FLAGS.SILENT (\Seen)
UID STORE 1,3,5,7,9 -FLAGS.SILENT (\Draft)
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.equal("#{tag!} OK STORE completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(                      1, 3, 5)
      assert_flag_enabled_msgs('answered',    3, 5)
      assert_flag_enabled_msgs('flagged' ,       5)
      assert_flag_enabled_msgs('deleted' ,        )
      assert_flag_enabled_msgs('seen'    ,        )
      assert_flag_enabled_msgs('draft'   ,        )
      assert_flag_enabled_msgs('recent'  ,        )
      assert_mbox_flag_num(answered: 2, flagged: 1)
    end

    def test_command_loop_store_read_only
      add_msg('')
      set_msg_flag(1, 'flagged', true)
      set_msg_flag(1, 'seen', true)

      assert_msg_uid(1)
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)

      cmd_txt = <<-'EOF'.b
STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
LOGIN foo open_sesame
STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
EXAMINE INBOX
STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
STORE 1 FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
STORE 1 -FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
STORE 1 +FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
STORE 1 FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
STORE 1 0FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
UID STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
UID STORE 1 FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
UID STORE 1 -FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
UID STORE 1 +FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
UID STORE 1 FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
UID STORE 1 -FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-ONLY] EXAMINE completed")
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^#{tag!} NO /)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(1)
      assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
    end

    def test_command_loop_copy
      msg_src = make_string_source('a')
      10.times do
        uid = add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)
      set_msg_flags('flagged', true, 1, 3, 5, 7, 9)
      work_id = @mail_store.add_mbox('WORK')

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       mbox_id: work_id)
      assert_flag_enabled_msgs('answered',  mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,  mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,  mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  mbox_id: work_id)
      assert_mbox_flag_num(                 mbox_id: work_id)
      assert_msg_text(                      mbox_id: work_id)

      cmd_txt = <<-'EOF'.b
COPY 2:4 WORK
LOGIN foo open_sesame
COPY 2:4 WORK
SELECT INBOX
COPY 2:4 WORK
COPY 2:4 WORK
COPY 100 WORK
COPY 1:* nobox
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal("#{tag!} OK COPY completed")
        assert.equal("#{tag!} OK COPY completed")
        assert.equal("#{tag!} OK COPY completed")
        assert.match(/^#{tag!} NO \[TRYCREATE\]/)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  ,              )
      assert_mbox_flag_num(flagged: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('answered',                    mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,                    mbox_id: work_id)
      assert_mbox_flag_num(flagged: 6,                        mbox_id: work_id)
      assert_msg_text('c', 'e', 'g', 'c', 'e', 'g',           mbox_id: work_id)
    end

    def test_command_loop_uid_copy
      msg_src = make_string_source('a')
      10.times do
        uid = add_msg(msg_src.next)
      end
      expunge(2, 4, 6, 8, 10)
      set_msg_flags('flagged', true, 1, 3, 5, 7, 9)
      work_id = @mail_store.add_mbox('WORK')

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
      assert_mbox_flag_num(flagged: 5, recent: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       mbox_id: work_id)
      assert_flag_enabled_msgs('answered',  mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,  mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,  mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,  mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,  mbox_id: work_id)
      assert_mbox_flag_num(                 mbox_id: work_id)
      assert_msg_text(                      mbox_id: work_id)

      cmd_txt = <<-'EOF'.b
UID COPY 3,5,7 WORK
LOGIN foo open_sesame
UID COPY 3,5,7 WORK
SELECT INBOX
UID COPY 3,5,7 WORK
UID COPY 3,5,7 WORK
UID COPY 100 WORK
UID COPY 1:* nobox
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^#{tag!} NO /, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^#{tag!} NO /)
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal("#{tag!} OK COPY completed")
        assert.equal("#{tag!} OK COPY completed")
        assert.equal("#{tag!} OK COPY completed")
        assert.match(/^#{tag!} NO \[TRYCREATE\]/)
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      # INBOX mailbox messages (copy source)
      assert_msg_uid(                      1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('answered',              )
      assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
      assert_flag_enabled_msgs('deleted' ,              )
      assert_flag_enabled_msgs('seen'    ,              )
      assert_flag_enabled_msgs('draft'   ,              )
      assert_flag_enabled_msgs('recent'  ,              )
      assert_mbox_flag_num(flagged: 5)
      assert_msg_text('a', 'c', 'e', 'g', 'i')

      # WORK mailbox messages (copy destination)
      assert_msg_uid(                       1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('answered',                    mbox_id: work_id)
      assert_flag_enabled_msgs('flagged' ,  1, 2, 3, 4, 5, 6, mbox_id: work_id)
      assert_flag_enabled_msgs('deleted' ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('seen'    ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('draft'   ,                    mbox_id: work_id)
      assert_flag_enabled_msgs('recent'  ,                    mbox_id: work_id)
      assert_mbox_flag_num(flagged: 6,                        mbox_id: work_id)
      assert_msg_text('c', 'e', 'g', 'c', 'e', 'g',           mbox_id: work_id)
    end

    def test_command_loop_copy_utf7_mbox_name
      add_msg('Hello world.')
      utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

      assert_msg_uid(1)
      assert_msg_uid(mbox_id: utf8_name_mbox_id)

      cmd_txt = <<-"EOF".b
LOGIN foo open_sesame
SELECT INBOX
COPY 1 "#{UTF7_MBOX_NAME}"
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.skip_while{|line| line =~ /^\* / }
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal("#{tag!} OK COPY completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }

      assert_msg_uid(1)
      assert_msg_uid(1, mbox_id: utf8_name_mbox_id)
      assert_equal('Hello world.', get_msg_text(1, mbox_id: utf8_name_mbox_id))
    end

    def test_command_loop_noop
      add_msg('')

      cmd_txt = <<-'EOF'.b
NOOP
LOGIN foo open_sesame
NOOP
SELECT INBOX
NOOP
CLOSE
NOOP
EXAMINE INBOX
NOOP
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal("#{tag!} OK NOOP completed")
        assert.equal("#{tag!} OK LOGIN completed")
        assert.equal("#{tag!} OK NOOP completed")
        assert.skip_while{|line| line =~ /^\* /}
        assert.equal("#{tag!} OK [READ-WRITE] SELECT completed")
        assert.equal('* 1 EXISTS')
        assert.equal('* 1 RECENTS')
        assert.equal("#{tag!} OK NOOP completed")
        assert.equal("#{tag!} OK CLOSE completed")
        assert.equal("#{tag!} OK NOOP completed")
        assert.skip_while{|line| line =~ /^\* /}
        assert.equal("#{tag!} OK [READ-ONLY] EXAMINE completed")
        assert.equal('* 1 EXISTS')
        assert.equal('* 0 RECENTS')
        assert.equal("#{tag!} OK NOOP completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end

    def test_command_loop_error_handling
      add_msg('')

      cmd_txt = <<-'EOF'.b
SYNTAX_ERROR
T001 NO_COMMAND
T002 UID NO_COMMAND
T003 UID
T004 NOOP DETARAME
      EOF

      assert_imap_command_loop(cmd_txt, autotag: false) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.equal('* BAD client command syntax error')
        assert.equal("#{tag!} BAD unknown command")
        assert.equal("#{tag!} BAD unknown uid command")
        assert.equal("#{tag!} BAD empty uid parameter")
        assert.equal("#{tag!} BAD invalid command parameter")
      }
    end

    def test_command_loop_db_recovery
      reload_mail_store{
        meta_db = RIMS::DB::Meta.new(RIMS::Hash_KeyValueStore.new(@kvs["#{RIMS::MAILBOX_DATA_STRUCTURE_VERSION}/#{@unique_user_id[0, 7]}/meta"]))
        meta_db.dirty = true
        meta_db.close
      }

      cmd_txt = <<-'EOF'.b
LOGIN foo open_sesame
LOGOUT
      EOF

      assert_imap_command_loop(cmd_txt) {|assert|
        assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        assert.match(/^\* OK \[ALERT\] recovery/)
        assert.equal("#{tag!} OK LOGIN completed")
        assert.match(/^\* BYE /)
        assert.equal("#{tag!} OK LOGOUT completed")
      }
    end
  end

  class ProtocolMailDeliveryDecoderTest < Test::Unit::TestCase
    def test_decode_user_mailbox
      base64_username = RIMS::Protocol.encode_base64('foo')

      assert_equal([ 'foo', 'INBOX' ],
                   RIMS::Protocol::MailDeliveryDecoder.decode_user_mailbox("b64user-mbox #{base64_username} INBOX"))
      assert_equal([ 'foo', 'a mailbox ' ],
                   RIMS::Protocol::MailDeliveryDecoder.decode_user_mailbox("b64user-mbox #{base64_username} a mailbox "))

      assert_raise(RIMS::SyntaxError) {
        RIMS::Protocol::MailDeliveryDecoder.decode_user_mailbox("unknown-encode-type #{base64_username} INBOX")
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
