# -*- coding: utf-8 -*-

require 'forwardable'
require 'logger'
require 'net/imap'
require 'pp' if $DEBUG
require 'rims'
require 'riser'
require 'socket'
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

      def initialize(response_lines)
        @lines = response_lines
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
        expected_string += "\r\n" if (expected_string !~ /\n\z/)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_equal(expected_string, line)
        self
      end

      def strenc_equal(expected_string, peek_next_line: false)
        expected_string += "\r\n" if (expected_string !~ /\n\z/)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_equal(expected_string.encoding, line.encoding)
        assert_equal(expected_string, line)
        self
      end

      def match(expected_regexp, peek_next_line: false)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_match(expected_regexp, line)
        assert_match(/\r\n\z/, line)
        self
      end

      def no_match(expected_regexp, peek_next_line: false)
        line = fetch_line(peek_next_line: peek_next_line)
        assert_not_nil(expected_regexp, line)
        assert_match(/\r\n\z/, line)
        self
      end

      def equal_lines(expected_multiline_string)
        expected_multiline_string.each_line do |line|
          self.equal(line)
        end
        self
      end
    end

    class IMAPCommandDecodeEngine
      include Test::Unit::Assertions

      def initialize(decoder, limits, logger)
        @decoder = decoder
        @limits = limits
        @logger = logger
      end

      def evaluate
        begin
          yield
        ensure
          @decoder.cleanup
        end
      end

      def stream_test?
        false
      end

      def fetch_untagged_response
        flunk('not a stream test.')
      end

      def parse_imap_command(tag, imap_command_message)
        cmd_client_output = StringIO.new('', 'w')
        reader = RIMS::Protocol::RequestReader.new(StringIO.new("#{tag} #{imap_command_message}\r\n", 'r'), cmd_client_output, @logger)
        _, cmd_name, *cmd_args = reader.read_command
        return cmd_name, cmd_args, cmd_client_output.string
      end
      private :parse_imap_command

      def execute_imap_command(tag, imap_command_message, client_input_text: nil, uid: nil)
        cmd_name, cmd_args, cmd_client_output = parse_imap_command(tag, imap_command_message)
        normalized_cmd_name = RIMS::Protocol::Decoder.imap_command_normalize(cmd_name)
        cmd_id = RIMS::Protocol::Decoder::IMAP_CMDs[normalized_cmd_name] or flunk("not a imap command: #{cmd_name}")
        cmd_kw_args = {}

        input = nil
        output = nil
        if (client_input_text) then
          input = StringIO.new(client_input_text, 'r')
          output = StringIO.new('', 'w')
          input_gets = input.method(:gets)
          output_write = lambda{|res|
            for data in res
              if (data != :flush) then
                output << data
              end
            end
          }
          inout_args = [ input_gets, output_write ]
          inout_args << RIMS::Protocol::ConnectionTimer.new(@limits, input) if (cmd_id == :idle)
          cmd_args = inout_args + cmd_args
        end
        unless (uid.nil?) then
          cmd_kw_args[:uid] = uid
        end

        block_call = 0
        ret_val = nil

        response_message = cmd_client_output.b
        pp [ :debug_imap_command, imap_command_message, cmd_id, cmd_args ] if $DEBUG
        @decoder.__send__(cmd_id, tag, *cmd_args, **cmd_kw_args) {|response|
          block_call += 1
          if (block_call == 1 && output) then
            response_message << output.string
          end
          if (response != :flush) then
            response_message << response
          end
        }
        response_lines = StringIO.new(response_message, 'r').each_line
        ret_val = yield(response_lines)
        assert_raise(StopIteration) { response_lines.next }
        if (client_input_text) then
          pp input.string, output.string if $DEBUG
        end

        @decoder = @decoder.next_decoder

        ret_val
      end
    end

    class IMAPStreamDecodeEngine
      include Test::Unit::Assertions

      def initialize(decoder, limits, logger)
        @decoder = decoder
        @limits = limits
        @logger = logger
      end

      def evaluate
        @server_io, @client_io = UNIXSocket.socketpair
        begin
          begin
            server_thread = Thread.start{
              stream = Riser::WriteBufferStream.new(@server_io)
              stream = Riser::LoggingStream.new(stream, @logger)
              begin
                RIMS::Protocol::Decoder.repl(@decoder, @limits, stream, stream, @logger)
              ensure
                @server_io.close
              end
            }
            ret_val = yield
          ensure
            @client_io.close_write
            server_thread.join if server_thread
          end
          assert(@client_io.eof?)
        ensure
          @client_io.close unless @client_io.closed?
        end

        ret_val
      end

      def stream_test?
        true
      end

      def client_input
        @client_io
      end
      private :client_input

      def server_output
        @client_io
      end
      private :server_output

      def fetch_untagged_response
        yield(server_output.each_line)
      end

      def execute_imap_command(tag, imap_command_message, client_input_text: nil, uid: nil)
        if (uid) then
          client_input << "#{tag} UID #{imap_command_message}\r\n"
        else
          client_input << "#{tag} #{imap_command_message}\r\n"
        end
        client_input << client_input_text if client_input_text
        yield(server_output.each_line)
      end
    end

    extend Forwardable

    def open_mail_store
      @drb_services.call_service(:engine, @unique_user_id) {|engine|
        begin
          @mail_store = engine.mail_store
          @mail_store.write_synchronize{
            yield
          }
        ensure
          @mail_store = nil
        end
      }
    end
    private :open_mail_store

    LINE_LENGTH_LIMIT  = 128
    LITERAL_SIZE_LIMIT = 1024**2
    COMMAND_SIZE_LIMIT = LITERAL_SIZE_LIMIT + LINE_LENGTH_LIMIT

    def make_decoder
      RIMS::Protocol::Decoder.new_decoder(@drb_services, @auth, @logger,
                                          line_length_limit: LINE_LENGTH_LIMIT,
                                          literal_size_limit: LITERAL_SIZE_LIMIT,
                                          command_size_limit: COMMAND_SIZE_LIMIT)
    end
    private :make_decoder

    def use_imap_command_decode_engine
      @engine = IMAPCommandDecodeEngine.new(@decoder, @limits, @logger)
    end
    private :use_imap_command_decode_engine

    def use_imap_stream_decode_engine
      @engine = IMAPStreamDecodeEngine.new(@decoder, @limits, @logger)
    end
    private :use_imap_stream_decode_engine

    def_delegator :@engine, :evaluate, :imap_decode_engine_evaluate
    def_delegator :@engine, :stream_test?

    def command_test?
      ! stream_test?
    end
    private :command_test?

    def setup
      @logger = Logger.new(STDOUT)
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL

      @kvs = Hash.new{|h, k| h[k] = {} }
      @kvs_open = proc{|mbox_version, unique_user_id, db_name|
        RIMS::Hash_KeyValueStore.new(@kvs["#{mbox_version}/#{unique_user_id[0, 7]}/#{db_name}"])
      }
      @unique_user_id = RIMS::Authentication.unique_user_id('foo')

      @bulk_response_count = 10
      @charset_aliases = RIMS::RFC822::CharsetAliases.new
      @charset_convert_options = {}
      @drb_services = Riser::DRbServices.new(0)
      @drb_services.add_sticky_process_service(:engine,
                                               Riser::ResourceSet.build{|builder|
                                                 builder.at_create{|unique_user_id|
                                                   mail_store = RIMS::MailStore.build(unique_user_id, @kvs_open, @kvs_open)
                                                   RIMS::Protocol::Decoder::Engine.new(unique_user_id, mail_store, @logger,
                                                                                       bulk_response_count: @bulk_response_count,
                                                                                       charset_aliases: @charset_aliases,
                                                                                       charset_convert_options: @charset_convert_options)
                                                 }
                                                 builder.at_destroy{|engine|
                                                   engine.destroy
                                                 }
                                                 builder.alias_unref(:destroy)
                                               })
      @drb_services.start_server
      @drb_services.start_client

      open_mail_store{
        @inbox_id = @mail_store.mbox_id('INBOX')
      }

      src_time = Time.at(1404369876)
      random_seed = 8091822677904057789202046265537518639

      @time_source = make_pseudo_time_source(src_time)
      @random_string_source = make_pseudo_random_string_source(random_seed)

      @auth = RIMS::Authentication.new(time_source: make_pseudo_time_source(src_time),
                                       random_string_source: make_pseudo_random_string_source(random_seed))
      @pw = RIMS::Password::PlainSource.new
      @pw.entry('foo', 'open_sesame')
      @pw.entry('#postman', 'password_of_mail_delivery_user')
      @auth.add_plug_in(@pw)

      @limits = RIMS::Protocol::ConnectionLimits.new(0.001, 60 * 30)
      @decoder = make_decoder
      @tag = 'T000'

      use_imap_command_decode_engine
    end

    def teardown
      assert_equal(0, @drb_services.get_service(:engine, @unique_user_id).proxy_count)
      @drb_services.stop_server
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

    def assert_imap_response(response_lines)
      dsl = IMAPResponseAssertionDSL.new(response_lines)
      yield(dsl)
    end
    private :assert_imap_response

    def assert_untagged_response
      @engine.fetch_untagged_response{|response_lines|
        assert_imap_response(response_lines) {|assert|
          yield(assert)
        }
      }
    end
    private :assert_untagged_response

    def assert_imap_command(imap_command_message, **kw_args)
      tag!

      ret_val = @engine.execute_imap_command(tag, imap_command_message, **kw_args) {|response_lines|
        assert_imap_response(response_lines) {|assert|
          yield(assert)
        }
      }
      @decoder = @decoder.next_decoder if command_test?

      ret_val
    end
    private :assert_imap_command

    def assert_imap_closed
      if (stream_test?) then
        assert_raise(Errno::EPIPE, Errno::ECONNRESET, StopIteration) {
          assert_imap_command('NOOP') {|assert|
            assert.equal("#{tag} OK NOOP completed")
          }
        }
      end
    end
    private :assert_imap_closed

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
      add_msg(@simple_mail.raw_source, Time.new(2013, 11, 8, 6, 47, 50, '+09:00'))
    end
    private :add_mail_simple

    def add_mail_multipart
      make_mail_multipart
      add_msg(@mpart_mail.raw_source, Time.new(2013, 11, 8, 19, 31, 3, '+09:00'))
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
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_imap_command('CAPABILITY') {|assert|
          assert.equal('* CAPABILITY IMAP4rev1 UIDPLUS IDLE AUTH=PLAIN AUTH=CRAM-MD5')
          assert.equal("#{tag} OK CAPABILITY completed")
        }
      }
    end

    def test_capability_stream
      use_imap_stream_decode_engine
      test_capability
    end

    def test_logout
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_logout_stream
      use_imap_stream_decode_engine
      test_logout
    end

    def test_authenticate_plain_inline
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command("AUTHENTICATE plain #{client_plain_response_base64('foo', 'detarame')}",
                            client_input_text: '') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/auth.* fail/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command("AUTHENTICATE plain #{client_plain_response_base64('foo', 'open_sesame')}",
                            client_input_text: '') {|assert|
          assert.equal("#{tag} OK AUTHENTICATE plain success")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command("AUTHENTICATE plain #{client_plain_response_base64('foo', 'open_sesame')}",
                            client_input_text: '') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/dup.* auth/)
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_closed
      }
    end

    def test_authenticate_plain_inline_stream
      use_imap_stream_decode_engine
      test_authenticate_plain_inline
    end

    def test_authenticate_plain
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('AUTHENTICATE plain', client_input_text: "*\r\n") {|assert|
          assert.equal('+ ')
          assert.match(/^#{tag} BAD AUTHENTICATE/, peek_next_line: true).match(/fail/)
        }

        assert_imap_command('AUTHENTICATE plain',
                            client_input_text: client_plain_response_base64('foo', 'detarame') + "\r\n") {|assert|
          assert.equal('+ ')
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/auth.* fail/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('AUTHENTICATE plain',
                            client_input_text: client_plain_response_base64('foo', 'open_sesame') + "\r\n") {|assert|
          assert.equal('+ ')
          assert.equal("#{tag} OK AUTHENTICATE plain success")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('AUTHENTICATE plain', client_input_text: '') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/dup.* auth/)
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_closed
      }
    end

    def test_authenticate_plain_stream
      use_imap_stream_decode_engine
      test_authenticate_plain
    end

    def test_authenticate_cram_md5
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        server_client_data_base64_pair_list = [
          make_cram_md5_server_client_data_base64('foo', 'open_sesame'),
          make_cram_md5_server_client_data_base64('foo', 'detarame'),
          make_cram_md5_server_client_data_base64('foo', 'open_sesame')
        ]

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('AUTHENTICATE cram-md5', client_input_text: "*\r\n") {|assert|
          assert.equal("+ #{server_client_data_base64_pair_list[0][0]}")
          assert.match(/^#{tag} BAD AUTHENTICATE/, peek_next_line: true).match(/fail/)
        }

        assert_imap_command('AUTHENTICATE cram-md5',
                            client_input_text: server_client_data_base64_pair_list[1][1] + "\r\n") {|assert|
          assert.equal("+ #{server_client_data_base64_pair_list[1][0]}")
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/auth.* fail/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('AUTHENTICATE cram-md5',
                            client_input_text: server_client_data_base64_pair_list[2][1] + "\r\n") {|assert|
          assert.equal("+ #{server_client_data_base64_pair_list[2][0]}")
          assert.equal("#{tag} OK AUTHENTICATE cram-md5 success")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('AUTHENTICATE cram-md5', client_input_text: '') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/dup.* auth/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_closed
      }
    end

    def test_authenticate_cram_md5_stream
      use_imap_stream_decode_engine
      test_authenticate_cram_md5
    end

    def test_login
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo detarame') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/fail.* login/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.match(/^#{tag} NO/, peek_next_line: true).match(/dup.* login/)
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_closed
      }
    end

    def test_login_stream
      use_imap_stream_decode_engine
      test_login
    end

    def test_select
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SELECT INBOX') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SELECT INBOX') {|assert|
          assert.equal('* 3 EXISTS')
          assert.equal('* 1 RECENT')
          assert.equal('* OK [UNSEEN 1]')
          assert.equal('* OK [UIDVALIDITY 1]')
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_closed

        open_mail_store{
          assert_msg_uid(                      2, 3)
          assert_flag_enabled_msgs('answered',     )
          assert_flag_enabled_msgs('flagged' ,     )
          assert_flag_enabled_msgs('deleted' ,     )
          assert_flag_enabled_msgs('seen'    , 2   )
          assert_flag_enabled_msgs('draft'   ,     )
          assert_flag_enabled_msgs('recent'  ,     )
          assert_mbox_flag_num(seen: 1)
        }
      }
    end

    def test_select_stream
      use_imap_stream_decode_engine
      test_select
    end

    def test_select_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        utf8_name_mbox_id = open_mail_store{ @mail_store.add_mbox(UTF8_MBOX_NAME) }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command("SELECT #{UTF7_MBOX_NAME}") {|assert|
          assert.equal('* 0 EXISTS')
          assert.equal('* 0 RECENT')
          assert.equal('* OK [UNSEEN 0]')
          assert.equal("* OK [UIDVALIDITY #{utf8_name_mbox_id}]")
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_select_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_select_utf7_mbox_name
    end

    def test_examine
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.equal('* 3 EXISTS')
          assert.equal('* 1 RECENT')
          assert.equal('* OK [UNSEEN 1]')
          assert.equal('* OK [UIDVALIDITY 1]')
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_closed

        open_mail_store{
          assert_msg_uid(                      1, 2, 3)
          assert_flag_enabled_msgs('answered',        )
          assert_flag_enabled_msgs('flagged' ,        )
          assert_flag_enabled_msgs('deleted' , 1      )
          assert_flag_enabled_msgs('seen'    , 1, 2   )
          assert_flag_enabled_msgs('draft'   ,        )
          assert_flag_enabled_msgs('recent'  ,       3)
          assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)
        }
      }
    end

    def test_examine_stream
      use_imap_stream_decode_engine
      test_examine
    end

    def test_examine_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        utf8_name_mbox_id = open_mail_store{ @mail_store.add_mbox(UTF8_MBOX_NAME) }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command("EXAMINE #{UTF7_MBOX_NAME}") {|assert|
          assert.equal('* 0 EXISTS')
          assert.equal('* 0 RECENT')
          assert.equal('* OK [UNSEEN 0]')
          assert.equal("* OK [UIDVALIDITY #{utf8_name_mbox_id}]")
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_examine_utf7_mbox_name_strem
      use_imap_stream_decode_engine
      test_examine_utf7_mbox_name
    end

    def test_create
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('CREATE foo') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?
        open_mail_store{
          assert_nil(@mail_store.mbox_id('foo'))
        }

        assert_imap_command('CREATE foo') {|assert|
          assert.equal("#{tag} OK CREATE completed")
        }

        open_mail_store{
          assert_not_nil(@mail_store.mbox_id('foo'))
        }

        assert_imap_command('CREATE inbox') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/dup.* mailbox/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_create_stream
      use_imap_stream_decode_engine
      test_create
    end

    def test_create_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        open_mail_store{
          assert_nil(@mail_store.mbox_id(UTF8_MBOX_NAME))
        }

        assert_imap_command("CREATE #{UTF7_MBOX_NAME}") {|assert|
          assert.equal("#{tag} OK CREATE completed")
        }

        open_mail_store{
          assert_not_nil(@mail_store.mbox_id(UTF8_MBOX_NAME))
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_create_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_create_utf7_mbox_name
    end

    def test_delete
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          @mail_store.add_mbox('foo')
          assert_mbox_exists('foo')
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('DELETE foo') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        open_mail_store{
          assert_mbox_exists('foo')
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        open_mail_store{
          assert_mbox_exists('foo')
        }
        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('DELETE foo') {|assert|
          assert.equal("#{tag} OK DELETE completed")
        }

        open_mail_store{
          assert_mbox_not_exists('foo')
          assert_mbox_not_exists('bar')
        }

        assert_imap_command('DELETE bar') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not found.* mailbox/)
        }

        open_mail_store{
          assert_mbox_not_exists('bar')
          assert_mbox_exists('INBOX')
        }

        assert_imap_command('DELETE inbox') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not delete.* [Ii][Nn][Bb][Oo][Xx]/)
        }

        if (command_test?) then
          open_mail_store{
            assert_mbox_exists('INBOX')
          }
        end

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_delete_stream
      use_imap_stream_decode_engine
      test_delete
    end

    def test_delete_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          @mail_store.add_mbox(UTF8_MBOX_NAME)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        open_mail_store{
          assert_mbox_exists(UTF8_MBOX_NAME)
        }

        assert_imap_command("DELETE #{UTF7_MBOX_NAME}") {|assert|
          assert.equal("#{tag} OK DELETE completed")
        }

        open_mail_store{
          assert_mbox_not_exists(UTF8_MBOX_NAME)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_delete_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_delete_utf7_mbox_name
    end

    def test_rename
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        mbox_id = nil
        open_mail_store{
          mbox_id = @mail_store.add_mbox('foo')
          assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('RENAME foo bar') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        open_mail_store{
          assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))
        }
        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        open_mail_store{
          assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', 'bar'))
        }
        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('RENAME foo bar') {|assert|
          assert.equal("#{tag} OK RENAME completed")
        }

        open_mail_store{
          assert_equal([ nil, mbox_id ], get_mbox_id_list('foo', 'bar'))
        }

        assert_imap_command('RENAME nobox baz') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not found.* mailbox/)
        }

        open_mail_store{
          assert_equal([ @inbox_id, nil ], get_mbox_id_list('INBOX', 'baz'))
        }

        assert_imap_command('RENAME INBOX baz') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not rename.* [Ii][Nn][Bb][Oo][Xx]/)
        }

        open_mail_store{
          assert_equal([ @inbox_id, nil ], get_mbox_id_list('INBOX', 'baz'))
          assert_equal([ mbox_id, @inbox_id ], get_mbox_id_list('bar', 'INBOX'))
        }

        assert_imap_command('RENAME bar inbox') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/dup.* mailbox/)
        }

        open_mail_store{
          assert_equal([ mbox_id, @inbox_id ], get_mbox_id_list('bar', 'INBOX'))
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_rename_stream
      use_imap_stream_decode_engine
      test_rename
    end

    def test_rename_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        mbox_id = open_mail_store{ @mail_store.add_mbox('foo') }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        open_mail_store{
          assert_equal([ mbox_id, nil ], get_mbox_id_list('foo', UTF8_MBOX_NAME))
        }

        assert_imap_command("RENAME foo #{UTF7_MBOX_NAME}") {|assert|
          assert.equal("#{tag} OK RENAME completed")
        }

        open_mail_store{
          assert_equal([ nil, mbox_id ], get_mbox_id_list('foo', UTF8_MBOX_NAME))
          assert_equal([ mbox_id, nil ], get_mbox_id_list(UTF8_MBOX_NAME, 'bar'))
        }

        assert_imap_command("RENAME #{UTF7_MBOX_NAME} bar") {|assert|
          assert.equal("#{tag} OK RENAME completed")
        }

        open_mail_store{
          assert_equal([ nil, mbox_id ], get_mbox_id_list(UTF8_MBOX_NAME, 'bar'))
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_rename_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_rename_utf7_mbox_name
    end

    def test_subscribe_dummy
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('SUBSCRIBE INBOX') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('SUBSCRIBE INBOX') {|assert|
          assert.equal("#{tag} OK SUBSCRIBE completed")
        }

        assert_imap_command('SUBSCRIBE NOBOX') {|assert|
          assert.equal("#{tag} NO not found a mailbox")
        }
      }
    end

    def test_subscribe_dummy_stream
      use_imap_stream_decode_engine
      test_subscribe_dummy
    end

    def test_subscribe_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          @mail_store.add_mbox(UTF8_MBOX_NAME)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command("SUBSCRIBE #{UTF7_MBOX_NAME}") {|assert|
          assert.equal("#{tag} OK SUBSCRIBE completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_subscribe_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_subscribe_utf7_mbox_name
    end

    def test_unsubscribe_dummy
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('UNSUBSCRIBE INBOX') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('UNSUBSCRIBE INBOX') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not implemented/)
        }
      }
    end

    def test_unsubscribe_dummy_stream
      use_imap_stream_decode_engine
      test_unsubscribe_dummy
    end

    def test_list
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LIST "" ""') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('LIST "" ""') {|assert|
          assert.equal('* LIST (\Noselect) NIL ""')
          assert.equal("#{tag} OK LIST completed")
        }

        assert_imap_command('LIST "" nobox') {|assert|
          assert.equal("#{tag} OK LIST completed")
        }

        assert_imap_command('LIST "" *') {|assert|
          assert.equal('* LIST (\Noinferiors \Unmarked) NIL "INBOX"')
          assert.equal("#{tag} OK LIST completed")
        }

        open_mail_store{
          add_msg('')
        }

        assert_imap_command('LIST "" *') {|assert|
          assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
          assert.equal("#{tag} OK LIST completed")
        }

        open_mail_store{
          @mail_store.add_mbox('foo')
        }

        assert_imap_command('LIST "" *') {|assert|
          assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
          assert.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
          assert.equal("#{tag} OK LIST completed")
        }

        assert_imap_command('LIST "" f*') {|assert|
          assert.equal('* LIST (\Noinferiors \Unmarked) NIL "foo"')
          assert.equal("#{tag} OK LIST completed")
        }

        assert_imap_command('LIST IN *') {|assert|
          assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
          assert.equal("#{tag} OK LIST completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_list_stream
      use_imap_stream_decode_engine
      test_list
    end

    def test_list_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          @mail_store.add_mbox(UTF8_MBOX_NAME)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command("LIST #{encode_utf7(UTF8_MBOX_NAME[0..6])} *#{encode_utf7(UTF8_MBOX_NAME[12..14])}*") {|assert|
          assert.equal(%Q'* LIST (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
          assert.equal("#{tag} OK LIST completed")
        }

        assert_imap_command("LIST #{encode_utf7(UTF8_MBOX_NAME[0..13])} *#{encode_utf7(UTF8_MBOX_NAME[16])}*") {|assert|
          assert.equal(%Q'* LIST (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
          assert.equal("#{tag} OK LIST completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_list_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_list_utf7_mbox_name
    end

    def test_status
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('STATUS nobox (MESSAGES)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('STATUS nobox (MESSAGES)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not found.* mailbox/)
        }

        assert_imap_command('STATUS INBOX (MESSAGES)') {|assert|
          assert.equal('* STATUS "INBOX" (MESSAGES 0)')
          assert.equal("#{tag} OK STATUS completed")
        }

        assert_imap_command('STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)') {|assert|
          assert.equal("* STATUS \"INBOX\" (MESSAGES 0 RECENT 0 UIDNEXT 1 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
          assert.equal("#{tag} OK STATUS completed")
        }

        open_mail_store{
          add_msg('')
        }

        assert_imap_command('STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)') {|assert|
          assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 1 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
          assert.equal("#{tag} OK STATUS completed")
        }

        open_mail_store{
          set_msg_flag(1, 'recent', false)
        }

        assert_imap_command('STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)') {|assert|
          assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
          assert.equal("#{tag} OK STATUS completed")
        }

        open_mail_store{
          set_msg_flag(1, 'seen', true)
        }

        assert_imap_command('STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)') {|assert|
          assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 2 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
          assert.equal("#{tag} OK STATUS completed")
        }

        open_mail_store{
          add_msg('')
        }

        assert_imap_command('STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)') {|assert|
          assert.equal("* STATUS \"INBOX\" (MESSAGES 2 RECENT 1 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 1)")
          assert.equal("#{tag} OK STATUS completed")
        }

        open_mail_store{
          expunge(2)
        }

        assert_imap_command('STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)') {|assert|
          assert.equal("* STATUS \"INBOX\" (MESSAGES 1 RECENT 0 UIDNEXT 3 UIDVALIDITY #{@inbox_id} UNSEEN 0)")
          assert.equal("#{tag} OK STATUS completed")
        }

        assert_imap_command('STATUS INBOX ()') {|assert|
          assert.equal('* STATUS "INBOX" ()')
          assert.equal("#{tag} OK STATUS completed")
        }

        assert_imap_command('STATUS INBOX MESSAGES') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STATUS INBOX (DETARAME)') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_status_stream
      use_imap_stream_decode_engine
      test_status
    end

    def test_status_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        mbox_id = open_mail_store{ @mail_store.add_mbox(UTF8_MBOX_NAME) }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command("STATUS #{UTF7_MBOX_NAME} (UIDVALIDITY MESSAGES RECENT UNSEEN)") {|assert|
          assert.equal(%Q'* STATUS "#{UTF7_MBOX_NAME}" (UIDVALIDITY #{mbox_id} MESSAGES 0 RECENT 0 UNSEEN 0)')
          assert.equal("#{tag} OK STATUS completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_status_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_status_utf7_mbox_name
    end

    def test_lsub_dummy
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LSUB "" *') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('LSUB "" *') {|assert|
          assert.equal('* LSUB (\Noinferiors \Unmarked) NIL "INBOX"')
          assert.equal("#{tag} OK LSUB completed")
        }
      }
    end

    def test_lsub_dummy_stream
      use_imap_stream_decode_engine
      test_lsub_dummy
    end

    def test_lsub_dummy_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          @mail_store.add_mbox(UTF8_MBOX_NAME)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command("LSUB #{encode_utf7(UTF8_MBOX_NAME[0..6])} *#{encode_utf7(UTF8_MBOX_NAME[12..14])}*") {|assert|
          assert.equal(%Q'* LSUB (\\Noinferiors \\Unmarked) NIL "#{UTF7_MBOX_NAME}"')
          assert.equal("#{tag} OK LSUB completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_lsub_dummy_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_lsub_dummy_utf7_mbox_name
    end

    def test_append
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('APPEND INBOX a') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        }

        open_mail_store{
          assert_msg_uid()
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('APPEND INBOX a') {|assert|
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1)
          assert_equal('a', get_msg_text(1))
          assert_msg_flags(1, recent: true)
        }

        assert_imap_command('APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) b') {|assert|
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1, 2)
          assert_equal('b', get_msg_text(2))
          assert_msg_flags(2, answered: true, flagged: true, deleted: true, seen: true, draft: true, recent: true)
        }

        assert_imap_command('APPEND INBOX "19-Nov-1975 12:34:56 +0900" c') {|assert|
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1, 2, 3)
          assert_equal('c', get_msg_text(3))
          assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(3))
          assert_msg_flags(3, recent: true)
        }

        assert_imap_command('APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) "19-Nov-1975 12:34:56 +0900" d') {|assert|
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1, 2, 3, 4)
          assert_equal('d', get_msg_text(4))
          assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(4))
          assert_msg_flags(4, answered: true, flagged: true, deleted: true, seen: true, draft: true, recent: true)
        }

        assert_imap_command('APPEND INBOX (\Answered \Flagged \Deleted \Seen \Draft) "19-Nov-1975 12:34:56 +0900" NIL x') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        open_mail_store{
          assert_msg_uid(1, 2, 3, 4)
        }

        assert_imap_command('APPEND INBOX "19-Nov-1975 12:34:56 +0900" (\Answered \Flagged \Deleted \Seen \Draft) x') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        open_mail_store{
          assert_msg_uid(1, 2, 3, 4)
        }

        assert_imap_command('APPEND INBOX (\Recent) x') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        open_mail_store{
          assert_msg_uid(1, 2, 3, 4)
        }

        assert_imap_command('APPEND INBOX "bad date-time" x') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        open_mail_store{
          assert_msg_uid(1, 2, 3, 4)
        }

        assert_imap_command('APPEND nobox x') {|assert|
          assert.match(/^#{tag} NO \[TRYCREATE\]/, peek_next_line: true).match(/not found.* mailbox/)
        }

        open_mail_store{
          assert_msg_uid(1, 2, 3, 4)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_append_stream
      use_imap_stream_decode_engine
      test_append
    end

    def test_append_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        utf8_name_mbox_id = open_mail_store{ @mail_store.add_mbox(UTF8_MBOX_NAME) }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        open_mail_store{
          assert_msg_uid(mbox_id: utf8_name_mbox_id)
        }

        assert_imap_command(%Q'APPEND #{UTF7_MBOX_NAME} "Hello world."') {|assert|
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1, mbox_id: utf8_name_mbox_id)
          assert_equal('Hello world.', get_msg_text(1, mbox_id: utf8_name_mbox_id))
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_append_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_append_utf7_mbox_name
    end

    def test_append_literal_stream
      make_mail_simple
      make_mail_multipart
      make_mail_mime_subject

      use_imap_stream_decode_engine # always run in stream
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        open_mail_store{
          assert_msg_uid()
        }

        assert_imap_command("APPEND INBOX #{literal(@simple_mail.raw_source)}") {|assert|
          assert.match(/^\+ /)
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1)
          assert_equal(@simple_mail.raw_source, get_msg_text(1))
          assert_msg_flags(1, recent: true)
        }

        assert_imap_command("APPEND INBOX #{literal(@mpart_mail.raw_source)}") {|assert|
          assert.match(/^\+ /)
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1, 2)
          assert_equal(@mpart_mail.raw_source, get_msg_text(2))
          assert_msg_flags(2, recent: true)
        }

        assert_imap_command("APPEND INBOX #{literal(@mime_subject_mail.raw_source)}") {|assert|
          assert.match(/^\+ /)
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1, 2, 3)
          assert_equal(@mime_subject_mail.raw_source, get_msg_text(3))
          assert_msg_flags(3, recent: true)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_check
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('CHECK') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('CHECK') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('CHECK') {|assert|
          assert.equal("#{tag} OK CHECK completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_check_stream
      use_imap_stream_decode_engine
      test_check
    end

    def test_close
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('CLOSE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('CLOSE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.equal('* 3 EXISTS')
          assert.equal('* 1 RECENT')
          assert.equal('* OK [UNSEEN 1]')
          assert.equal('* OK [UIDVALIDITY 1]')
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('CLOSE') {|assert|
          # see: RFC 3501 / 6.4.2.  CLOSE Command
          # <https://tools.ietf.org/html/rfc3501#section-6.4.2>
          #
          # The CLOSE command permanently removes all messages that have the
          # \Deleted flag set from the currently selected mailbox, and returns
          # to the authenticated state from the selected state.  No untagged
          # EXPUNGE responses are sent.
          assert.equal("#{tag} OK CLOSE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        open_mail_store{
          assert_msg_uid(                      2, 3)
          assert_flag_enabled_msgs('answered',     )
          assert_flag_enabled_msgs('flagged' ,     )
          assert_flag_enabled_msgs('deleted' ,     )
          assert_flag_enabled_msgs('seen'    , 2   )
          assert_flag_enabled_msgs('draft'   ,     )
          assert_flag_enabled_msgs('recent'  ,     )
          assert_mbox_flag_num(seen: 1)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_closed
      }
    end

    def test_close_stream
      use_imap_stream_decode_engine
      test_close
    end

    def test_close_read_only
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('CLOSE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('CLOSE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.equal('* 3 EXISTS')
          assert.equal('* 1 RECENT')
          assert.equal('* OK [UNSEEN 1]')
          assert.equal('* OK [UIDVALIDITY 1]')
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('CLOSE') {|assert|
          assert.equal("#{tag} OK CLOSE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        open_mail_store{
          assert_msg_uid(                      1, 2, 3)
          assert_flag_enabled_msgs('answered',        )
          assert_flag_enabled_msgs('flagged' ,        )
          assert_flag_enabled_msgs('deleted' , 1      )
          assert_flag_enabled_msgs('seen'    , 1, 2   )
          assert_flag_enabled_msgs('draft'   ,        )
          assert_flag_enabled_msgs('recent'  ,       3)
          assert_mbox_flag_num(deleted: 1, seen: 2, recent: 1)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_closed
      }
    end

    def test_close_read_onyl_stream
      use_imap_stream_decode_engine
      test_close_read_only
    end

    def test_expunge
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('EXPUNGE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('EXPUNGE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('EXPUNGE') {|assert|
          assert.equal("#{tag} OK EXPUNGE completed")
        }

        open_mail_store{
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
        }

        assert_imap_command('EXPUNGE') {|assert|
          assert.equal("#{tag} OK EXPUNGE completed")
        }

        open_mail_store{
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
        }

        assert_imap_command('EXPUNGE') {|assert|
          assert.equal('* 2 EXPUNGE')
          assert.equal("#{tag} OK EXPUNGE completed")
        }

        open_mail_store{
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
        }

        assert_imap_command('EXPUNGE') {|assert|
          assert.equal('* 2 EXPUNGE')
          assert.equal('* 1 EXPUNGE')
          assert.equal("#{tag} OK EXPUNGE completed")
        }

        open_mail_store{
          assert_msg_uid(                      )
          assert_flag_enabled_msgs('answered', )
          assert_flag_enabled_msgs('flagged' , )
          assert_flag_enabled_msgs('deleted' , )
          assert_flag_enabled_msgs('seen'    , )
          assert_flag_enabled_msgs('draft'   , )
          assert_flag_enabled_msgs('recent'  , )
          assert_mbox_flag_num(answered: 0, flagged: 0, deleted: 0, seen: 0, draft: 0, recent: 0)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_expunge_stream
      use_imap_stream_decode_engine
      test_expunge
    end

    def test_expunge_read_only
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          add_msg('')
          set_msg_flag(1, 'deleted', true)

          assert_msg_uid(1)
          assert_msg_flags(1, deleted: true, recent: true)
          assert_mbox_flag_num(deleted: 1, recent: 1)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('EXPUNGE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('EXPUNGE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('EXPUNGE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot expunge.* read-only/)
        }

        open_mail_store{
          assert_msg_uid(1)
          assert_msg_flags(1, deleted: true, recent: true)
          assert_mbox_flag_num(deleted: 1, recent: 1)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_expunge_read_only_stream
      use_imap_stream_decode_engine
      test_expunge_read_only
    end

    def test_search
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SEARCH ALL') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SEARCH ALL') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('SEARCH ALL') {|assert|
          assert.equal("* SEARCH\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        open_mail_store{
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
        }

        assert_imap_command('SEARCH ALL') {|assert|
          assert.equal("* SEARCH 1 2 3\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH ALL', uid: true) {|assert|
          assert.equal("* SEARCH 1 3 5\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH OR FROM alice FROM bob BODY apple') {|assert|
          assert.equal("* SEARCH 1 3\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH OR FROM alice FROM bob BODY apple', uid: true) {|assert|
          assert.equal("* SEARCH 1 5\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        # first message sequence set operation is shortcut for accessing folder message list.
        assert_imap_command('SEARCH 2') {|assert|
          assert.equal("* SEARCH 2\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        # first message sequence set operation is shortcut for accessing folder message list.
        assert_imap_command('SEARCH 2', uid: true) {|assert|
          assert.equal("* SEARCH 3\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        # first message sequence set operation is shortcut for accessing folder message list.
        assert_imap_command('SEARCH UID 3') {|assert|
          assert.equal("* SEARCH 2\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        # first message sequence set operation is shortcut for accessing folder message list.
        assert_imap_command('SEARCH UID 3', uid: true) {|assert|
          assert.equal("* SEARCH 3\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH bad-search-command') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('SEARCH') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_search_stream
      use_imap_stream_decode_engine
      test_search
    end

    def test_search_charset_body
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SEARCH CHARSET us-ascii ALL') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SEARCH CHARSET us-ascii ALL') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('SEARCH CHARSET us-ascii ALL') {|assert|
          assert.equal("* SEARCH 1 2 3 4 5\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH CHARSET us-ascii BODY foo') {|assert|
          assert.equal("* SEARCH 1 2 3\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH CHARSET us-ascii BODY bar') {|assert|
          assert.equal("* SEARCH\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        utf8_msg = "\u306F\u306B\u307B"
        assert_imap_command("SEARCH CHARSET utf-8 BODY #{literal(utf8_msg)}".b) {|assert|
          assert.match(/^\+ /)
          assert.equal("* SEARCH 4 5\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command("SEARCH CHARSET euc-jp BODY #{literal(utf8_msg)}".b) {|assert|
          assert.match(/^\+ /)
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('SEARCH CHARSET x-nothing BODY foo') {|assert|
          assert.match(/^#{tag} NO \[BADCHARSET \(\S+( \S+)*\)\] unknown charset/)
        }

        assert_imap_command('SEARCH CHARSET') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('SEARCH CHARSET NIL') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('SEARCH CHARSET utf-8') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_search_charset_body_stream
      use_imap_stream_decode_engine
      test_search_charset_body
    end

    def test_search_charset_text
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          add_msg("Content-Type: text/plain\r\n" +
                  "\r\n" +
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SEARCH CHARSET us-ascii ALL') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SEARCH CHARSET us-ascii ALL') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('SEARCH CHARSET us-ascii ALL') {|assert|
          assert.equal("* SEARCH 1 2 3 4 5\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH CHARSET us-ascii TEXT foo') {|assert|
          assert.equal("* SEARCH 1 2 3\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH CHARSET utf-8 TEXT bar') {|assert|
          assert.equal("* SEARCH 2 3\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('SEARCH CHARSET us-ascii TEXT baz') {|assert|
          assert.equal("* SEARCH\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        utf8_msg = "\u306F\u306B\u307B"
        assert_imap_command("SEARCH CHARSET utf-8 TEXT #{literal(utf8_msg)}".b) {|assert|
          assert.match(/^\+ /)
          assert.equal("* SEARCH 4 5\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command("SEARCH CHARSET euc-jp TEXT #{literal(utf8_msg)}".b) {|assert|
          assert.match(/^\+ /)
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('SEARCH CHARSET x-nothing TEXT foo') {|assert|
          assert.match(/^#{tag} NO \[BADCHARSET \(\S+( \S+)*\)\] unknown charset/)
        }

        assert_imap_command('SEARCH CHARSET') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('SEARCH CHARSET NIL') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('SEARCH CHARSET utf-8') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_search_charset_text_stream
      use_imap_stream_decode_engine
      test_search_charset_text
    end

    def test_search_charset_skip_encoding_error
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          add_msg("Content-Type: text/plain\r\n" +
                  "\r\n" +
                  "foo")
          add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                  "\r\n" +
                  # utf-8
                  "\u3053\u3093\u306B\u3061\u306F\r\n" +
                  "\u3044\u308D\u306F\u306B\u307B\u3078\u3068\r\n" +
                  "\u3042\u3044\u3046\u3048\u304A\r\n" +
                  "foo\r\n")

          assert_msg_uid(1, 2)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('SEARCH CHARSET us-ascii BODY foo') {|assert|
          assert.equal("* SEARCH 1\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        utf8_msg = "\u306F\u306B\u307B"
        assert_imap_command("SEARCH CHARSET utf-8 TEXT #{literal(utf8_msg)}".b) {|assert|
          assert.match(/^\+ /)
          assert.equal("* SEARCH\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_search_charset_skip_encoding_error_stream
      use_imap_stream_decode_engine
      test_search_charset_skip_encoding_error
    end

    # skip this test because `EncodingError' is ignored.
    def _test_search_interrupt_by_bad_response
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          @bulk_response_count.times do
            add_msg("Content-Type: text/plain\r\n" +
                    "\r\n" +
                    "foo")
          end

          add_msg("Content-Type: text/plain; charset=x-nothing\r\n" +
                  "\r\n" +
                  "foo")

          assert_msg_uid(*(1..(@bulk_response_count.succ)).to_a)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('SEARCH CHARSET utf-8 TEXT foo') {|assert|
          assert.match(/\A\* SEARCH( \d+)+\r\n\z/, peek_next_line: true).no_match(/ #{@bulk_response_count.succ}/)
          assert.equal("#{tag} BAD internal server error\r\n")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    # skip this test because `EncodingError' is ignored.
    def _test_search_interrupt_by_bad_response_stream
      use_imap_stream_decode_engine
      test_search_interrupt_by_bad_response
    end

    def test_fetch
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          add_msg('')
          expunge(1)
          add_mail_simple
          add_mail_multipart

          assert_msg_uid(2, 3)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('FETCH 1:* FAST') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('FETCH 1:* FAST') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('FETCH 1:* FAST') {|assert|
          assert.strenc_equal(%Q'* 1 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE #{@simple_mail.raw_source.bytesize})'.b)
          assert.strenc_equal(%Q'* 2 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})'.b)
          assert.equal("#{tag} OK FETCH completed")
        }

        assert_imap_command('FETCH 1:* (FAST)') {|assert|
          assert.strenc_equal(%Q'* 1 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE #{@simple_mail.raw_source.bytesize})'.b)
          assert.strenc_equal(%Q'* 2 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})'.b)
          assert.equal("#{tag} OK FETCH completed")
        }

        assert_imap_command('FETCH 1:* (FLAGS RFC822.HEADER UID)') {|assert|
          assert.equal_lines("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@simple_mail.header.raw_source)} UID 2)".b)
          assert.equal_lines("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@mpart_mail.header.raw_source)} UID 3)".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: false, recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 1 RFC822') {|assert|
          assert.equal_lines("* 1 FETCH (FLAGS (\\Seen \\Recent) RFC822 #{literal(@simple_mail.raw_source)})".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: true,  recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert(10 < @simple_mail.raw_source.bytesize)
        assert(10 + 10 < @simple_mail.raw_source.bytesize)
        assert_imap_command('FETCH 1 BODY[]<10.10>') {|assert|
          assert.equal_lines("* 1 FETCH (BODY[]<10> #{literal(@simple_mail.raw_source[10, 10])})".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: true,  recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 2 BODY.PEEK[1]') {|assert|
          assert.equal_lines(%Q'* 2 FETCH (BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")'.b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: true,  recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 2 RFC822', uid: true) {|assert|
          assert.equal_lines("* 1 FETCH (UID 2 RFC822 #{literal(@simple_mail.raw_source)})".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: true,  recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert(10 < @simple_mail.raw_source.bytesize)
        assert(10 + 10 < @simple_mail.raw_source.bytesize)
        assert_imap_command('FETCH 2 BODY[]<10.10>', uid: true) {|assert|
          assert.equal_lines("* 1 FETCH (UID 2 BODY[]<10> #{literal(@simple_mail.raw_source[10, 10])})".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: true,  recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 3 (UID BODY.PEEK[1])', uid: true) {|assert|
          assert.equal_lines(%Q'* 2 FETCH (UID 3 BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")'.b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: true,  recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 1 bad-fetch-attr') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_fetch_stream
      use_imap_stream_decode_engine
      test_fetch
    end

    def test_fetch_read_only
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          add_msg('')
          expunge(1)
          add_mail_simple
          add_mail_multipart

          assert_msg_uid(2, 3)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('FETCH 1:* FAST') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('FETCH 1:* FAST') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('FETCH 1:* FAST') {|assert|
          assert.strenc_equal(%Q'* 1 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE #{@simple_mail.raw_source.bytesize})'.b)
          assert.strenc_equal(%Q'* 2 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})'.b)
          assert.equal("#{tag} OK FETCH completed")
        }

        assert_imap_command('FETCH 1:* (FAST)') {|assert|
          assert.strenc_equal(%Q'* 1 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 06:47:50 +0900" RFC822.SIZE #{@simple_mail.raw_source.bytesize})'.b)
          assert.strenc_equal(%Q'* 2 FETCH (FLAGS (\\Recent) INTERNALDATE "08-Nov-2013 19:31:03 +0900" RFC822.SIZE #{@mpart_mail.raw_source.bytesize})'.b)
          assert.equal("#{tag} OK FETCH completed")
        }

        assert_imap_command('FETCH 1:* (FLAGS RFC822.HEADER UID)') {|assert|
          assert.equal_lines("* 1 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@simple_mail.header.raw_source)} UID 2)".b)
          assert.equal_lines("* 2 FETCH (FLAGS (\\Recent) RFC822.HEADER #{literal(@mpart_mail.header.raw_source)} UID 3)".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: false, recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 1 RFC822') {|assert|
          assert.equal_lines("* 1 FETCH (RFC822 #{literal(@simple_mail.raw_source)})".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: false, recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert(10 < @simple_mail.raw_source.bytesize)
        assert(10 + 10 < @simple_mail.raw_source.bytesize)
        assert_imap_command('FETCH 1 BODY[]<10.10>') {|assert|
          assert.equal_lines("* 1 FETCH (BODY[]<10> #{literal(@simple_mail.raw_source[10, 10])})".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: false, recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 2 BODY.PEEK[1]') {|assert|
          assert.equal_lines(%Q'* 2 FETCH (BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")'.b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: false, recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 2 RFC822', uid: true) {|assert|
          assert.equal_lines("* 1 FETCH (UID 2 RFC822 #{literal(@simple_mail.raw_source)})".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: false, recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert(10 < @simple_mail.raw_source.bytesize)
        assert(10 + 10 < @simple_mail.raw_source.bytesize)
        assert_imap_command('FETCH 2 BODY[]<10.10>', uid: true) {|assert|
          assert.equal_lines("* 1 FETCH (UID 2 BODY[]<10> #{literal(@simple_mail.raw_source[10, 10])})".b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: false, recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 3 (UID BODY.PEEK[1])', uid: true) {|assert|
          assert.equal_lines(%Q'* 2 FETCH (UID 3 BODY[1] "#{@mpart_mail.parts[0].body.raw_source}")'.b)
          assert.equal("#{tag} OK FETCH completed")
        }

        open_mail_store{
          assert_msg_flags(2, seen: false, recent: true)
          assert_msg_flags(3, seen: false, recent: true)
        }

        assert_imap_command('FETCH 1 bad-fetch-attr') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_fetch_read_only_stream
      use_imap_stream_decode_engine
      test_fetch_read_only
    end

    def test_store
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS (\Answered)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS (\Answered)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',              )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(recent: 5)
        }

        assert_imap_command('STORE 1 +FLAGS (\Answered)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Answered \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, recent: 5)
        }

        assert_imap_command('STORE 1:2 +FLAGS (\Flagged)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Answered \Flagged \Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Flagged \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, recent: 5)
        }

        assert_imap_command('STORE 1:3 +FLAGS (\Deleted)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Answered \Flagged \Deleted \Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Flagged \Deleted \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Deleted \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, recent: 5)
        }

        assert_imap_command('STORE 1:4 +FLAGS (\Seen)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Flagged \Deleted \Seen \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Deleted \Seen \Recent))')
          assert.equal('* 4 FETCH (FLAGS (\Seen \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, recent: 5)
        }

        assert_imap_command('STORE 1:5 +FLAGS (\Draft)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Deleted \Seen \Draft \Recent))')
          assert.equal('* 4 FETCH (FLAGS (\Seen \Draft \Recent))')
          assert.equal('* 5 FETCH (FLAGS (\Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 4 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 5 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 5, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1 -FLAGS (\Answered)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:2 -FLAGS (\Flagged)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Deleted \Seen \Draft \Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Answered \Deleted \Seen \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:3 -FLAGS (\Deleted)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Seen \Draft \Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Answered \Seen \Draft \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Answered \Flagged \Seen \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:4 -FLAGS (\Seen)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Draft \Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Answered \Draft \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Answered \Flagged \Draft \Recent))')
          assert.equal('* 4 FETCH (FLAGS (\Answered \Flagged \Deleted \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:5 -FLAGS (\Draft)') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Answered \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Answered \Flagged \Recent))')
          assert.equal('* 4 FETCH (FLAGS (\Answered \Flagged \Deleted \Recent))')
          assert.equal('* 5 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1:5 +FLAGS ()') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Answered \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Answered \Flagged \Recent))')
          assert.equal('* 4 FETCH (FLAGS (\Answered \Flagged \Deleted \Recent))')
          assert.equal('* 5 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1:5 -FLAGS ()') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Answered \Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Answered \Flagged \Recent))')
          assert.equal('* 4 FETCH (FLAGS (\Answered \Flagged \Deleted \Recent))')
          assert.equal('* 5 FETCH (FLAGS (\Answered \Flagged \Deleted \Seen \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1:5 FLAGS ()') {|assert|
          assert.equal('* 1 FETCH (FLAGS (\Recent))')
          assert.equal('* 2 FETCH (FLAGS (\Recent))')
          assert.equal('* 3 FETCH (FLAGS (\Recent))')
          assert.equal('* 4 FETCH (FLAGS (\Recent))')
          assert.equal('* 5 FETCH (FLAGS (\Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',              )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 0, flagged: 0, deleted: 0, seen: 0, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1 DETARAME (\Flagged)') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STORE 1 FLAGS (\Detarame)') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STORE 1 FLAGS NIL') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_store_stream
      use_imap_stream_decode_engine
      test_store
    end

    def test_store_silent
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS.SILENT (\Answered)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS.SILENT (\Answered)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',              )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(recent: 5)
        }

        assert_imap_command('STORE 1 +FLAGS.SILENT (\Answered)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, recent: 5)
        }

        assert_imap_command('STORE 1:2 +FLAGS.SILENT (\Flagged)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, recent: 5)
        }

        assert_imap_command('STORE 1:3 +FLAGS.SILENT (\Deleted)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, recent: 5)
        }

        assert_imap_command('STORE 1:4 +FLAGS.SILENT (\Seen)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, recent: 5)
        }

        assert_imap_command('STORE 1:5 +FLAGS.SILENT (\Draft)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:* FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 5, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1 -FLAGS.SILENT (\Answered)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:2 -FLAGS.SILENT (\Flagged)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:3 -FLAGS.SILENT (\Deleted)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:4 -FLAGS.SILENT (\Seen)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:5 -FLAGS.SILENT (\Draft)') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1:5 +FLAGS.SILENT ()') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1:5 -FLAGS.SILENT ()') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1:5 FLAGS.SILENT ()') {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',              )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 0, flagged: 0, deleted: 0, seen: 0, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1 FLAGS.DETARAME (\Flagged)') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STORE 1 FLAGS.SILENT (\Detarame)') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STORE 1 FLAGS.SILENT NIL') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_store_silent_stream
      use_imap_stream_decode_engine
      test_store_silent
    end

    def test_uid_store
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS (\Answered)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS (\Answered)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',              )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(recent: 5)
        }

        assert_imap_command('STORE 1 +FLAGS (\Answered)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Answered \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, recent: 5)
        }

        assert_imap_command('STORE 1,3 +FLAGS (\Flagged)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Answered \Flagged \Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Flagged \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, recent: 5)
        }

        assert_imap_command('STORE 1,3,5 +FLAGS (\Deleted)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Answered \Flagged \Deleted \Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Flagged \Deleted \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Deleted \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7 +FLAGS (\Seen)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Answered \Flagged \Deleted \Seen \Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Flagged \Deleted \Seen \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Deleted \Seen \Recent))')
          assert.equal('* 4 FETCH (UID 7 FLAGS (\Seen \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 +FLAGS (\Draft)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Deleted \Seen \Draft \Recent))')
          assert.equal('* 4 FETCH (UID 7 FLAGS (\Seen \Draft \Recent))')
          assert.equal('* 5 FETCH (UID 9 FLAGS (\Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 4 FETCH (UID 7 FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal('* 5 FETCH (UID 9 FLAGS (\Answered \Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 5, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1 -FLAGS (\Answered)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Flagged \Deleted \Seen \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1,3 -FLAGS (\Flagged)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Deleted \Seen \Draft \Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Answered \Deleted \Seen \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1,3,5 -FLAGS (\Deleted)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Seen \Draft \Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Answered \Seen \Draft \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Answered \Flagged \Seen \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7 -FLAGS (\Seen)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Draft \Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Answered \Draft \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Answered \Flagged \Draft \Recent))')
          assert.equal('* 4 FETCH (UID 7 FLAGS (\Answered \Flagged \Deleted \Draft \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 -FLAGS (\Draft)', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Answered \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Answered \Flagged \Recent))')
          assert.equal('* 4 FETCH (UID 7 FLAGS (\Answered \Flagged \Deleted \Recent))')
          assert.equal('* 5 FETCH (UID 9 FLAGS (\Answered \Flagged \Deleted \Seen \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 +FLAGS ()', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Answered \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Answered \Flagged \Recent))')
          assert.equal('* 4 FETCH (UID 7 FLAGS (\Answered \Flagged \Deleted \Recent))')
          assert.equal('* 5 FETCH (UID 9 FLAGS (\Answered \Flagged \Deleted \Seen \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 -FLAGS ()', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Answered \Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Answered \Flagged \Recent))')
          assert.equal('* 4 FETCH (UID 7 FLAGS (\Answered \Flagged \Deleted \Recent))')
          assert.equal('* 5 FETCH (UID 9 FLAGS (\Answered \Flagged \Deleted \Seen \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 FLAGS ()', uid: true) {|assert|
          assert.equal('* 1 FETCH (UID 1 FLAGS (\Recent))')
          assert.equal('* 2 FETCH (UID 3 FLAGS (\Recent))')
          assert.equal('* 3 FETCH (UID 5 FLAGS (\Recent))')
          assert.equal('* 4 FETCH (UID 7 FLAGS (\Recent))')
          assert.equal('* 5 FETCH (UID 9 FLAGS (\Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',              )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 0, flagged: 0, deleted: 0, seen: 0, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1 DETARAME (\Flagged)', uid: true) {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STORE 1 FLAGS (\Detarame)', uid: true) {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STORE 1 FLAGS NIL', uid: true) {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_uid_store_stream
      use_imap_stream_decode_engine
      test_uid_store
    end

    def test_uid_store_silent
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS.SILENT (\Answered)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS.SILENT (\Answered)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',              )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(recent: 5)
        }

        assert_imap_command('STORE 1 +FLAGS.SILENT (\Answered)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, recent: 5)
        }

        assert_imap_command('STORE 1,3 +FLAGS.SILENT (\Flagged)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, recent: 5)
        }

        assert_imap_command('STORE 1,3,5 +FLAGS.SILENT (\Deleted)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7 +FLAGS.SILENT (\Seen)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 +FLAGS.SILENT (\Draft)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1            )
          assert_flag_enabled_msgs('flagged' , 1, 3         )
          assert_flag_enabled_msgs('deleted' , 1, 3, 5      )
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7   )
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 1, flagged: 2, deleted: 3, seen: 4, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1:* FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered', 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 5, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1 -FLAGS.SILENT (\Answered)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 5, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1,3 -FLAGS.SILENT (\Flagged)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 5, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1,3,5 -FLAGS.SILENT (\Deleted)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 5, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7 -FLAGS.SILENT (\Seen)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   , 1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 5, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 -FLAGS.SILENT (\Draft)', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 +FLAGS.SILENT ()', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 -FLAGS.SILENT ()', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',    3, 5, 7, 9)
          assert_flag_enabled_msgs('flagged' ,       5, 7, 9)
          assert_flag_enabled_msgs('deleted' ,          7, 9)
          assert_flag_enabled_msgs('seen'    ,             9)
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 4, flagged: 3, deleted: 2, seen: 1, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1,3,5,7,9 FLAGS.SILENT ()', uid: true) {|assert|
          assert.equal("#{tag} OK STORE completed")
        }

        open_mail_store{
          assert_msg_uid(                      1, 3, 5, 7, 9)
          assert_flag_enabled_msgs('answered',              )
          assert_flag_enabled_msgs('flagged' ,              )
          assert_flag_enabled_msgs('deleted' ,              )
          assert_flag_enabled_msgs('seen'    ,              )
          assert_flag_enabled_msgs('draft'   ,              )
          assert_flag_enabled_msgs('recent'  , 1, 3, 5, 7, 9)
          assert_mbox_flag_num(answered: 0, flagged: 0, deleted: 0, seen: 0, draft: 0, recent: 5)
        }

        assert_imap_command('STORE 1 FLAGS.DETARAME (\Flagged)', uid: true) {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STORE 1 FLAGS.SILENT (\Detarame)', uid: true) {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('STORE 1 FLAGS.SILENT NIL', uid: true) {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_uid_store_silent_stream
      use_imap_stream_decode_engine
      test_uid_store_silent
    end

    def test_store_read_only
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          add_msg('')
          set_msg_flag(1, 'flagged', true)
          set_msg_flag(1, 'seen', true)

          assert_msg_uid(1)
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 FLAGS (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 -FLAGS (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 +FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 -FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 FLAGS (\Answered \Flagged \Deleted \Seen \Draft)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 -FLAGS (\Answered \Flagged \Deleted \Seen \Draft)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 +FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('STORE 1 -FLAGS.SILENT (\Answered \Flagged \Deleted \Seen \Draft)', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/cannot store.* read-only/)
        }

        open_mail_store{
          assert_msg_flags(1, answered: false, flagged: true, deleted: false, seen: true, draft: false, recent: true)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_store_read_only_stream
      use_imap_stream_decode_engine
      test_store_read_only
    end

    def test_copy
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        work_id = nil
        open_mail_store{
          msg_src = make_string_source('a')
          10.times do
            _uid = add_msg(msg_src.next)
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('COPY 2:4 WORK') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('COPY 2:4 WORK') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        open_mail_store{
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
        }

        assert_imap_command('COPY 2:4 WORK') {|assert|
          assert.match(/#{tag} OK \[COPYUID \d+ \d+,\d+,\d+ \d+,\d+,\d+\] COPY completed/)
        }

        open_mail_store{
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
        }

        # duplicted message copy
        assert_imap_command('COPY 2:4 WORK') {|assert|
          assert.match(/#{tag} OK \[COPYUID \d+ \d+,\d+,\d+ \d+,\d+,\d+\] COPY completed/)
        }

        open_mail_store{
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
        }

        # copy of empty message set
        assert_imap_command('COPY 100 WORK') {|assert|
          assert.match(/#{tag} OK COPY completed/)
        }

        open_mail_store{
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
        }

        assert_imap_command('COPY 1:* nobox') {|assert|
          assert.match(/^#{tag} NO \[TRYCREATE\]/, peek_next_line: true).match(/not found.* mailbox/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_copy_stream
      use_imap_stream_decode_engine
      test_copy
    end

    def test_uid_copy
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        work_id = nil
        open_mail_store{
          msg_src = make_string_source('a')
          10.times do
            _uid = add_msg(msg_src.next)
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
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('COPY 3,5,7 WORK', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not auth/, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('COPY 3,5,7 WORK', uid: true) {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not selected/, peek_next_line: true).no_match(/\[TRYCREATE\]/)
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        open_mail_store{
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
        }

        assert_imap_command('COPY 3,5,7 WORK', uid: true) {|assert|
          assert.match(/#{tag} OK \[COPYUID \d+ \d+,\d+,\d+ \d+,\d+,\d+\] COPY completed/)
        }

        open_mail_store{
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
        }

        # duplicted message copy
        assert_imap_command('COPY 3,5,7 WORK', uid: true) {|assert|
          assert.match(/#{tag} OK \[COPYUID \d+ \d+,\d+,\d+ \d+,\d+,\d+\] COPY completed/)
        }

        open_mail_store{
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
        }

        # copy of empty message set
        assert_imap_command('COPY 100 WORK', uid: true) {|assert|
          assert.match(/#{tag} OK COPY completed/)
        }

        open_mail_store{
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
        }

        assert_imap_command('COPY 1:* nobox', uid: true) {|assert|
          assert.match(/^#{tag} NO \[TRYCREATE\]/, peek_next_line: true).match(/not found.* mailbox/)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_uid_copy_stream
      use_imap_stream_decode_engine
      test_uid_copy
    end

    def test_copy_utf7_mbox_name
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        utf8_name_mbox_id = nil
        open_mail_store{
          add_msg('Hello world.')
          utf8_name_mbox_id = @mail_store.add_mbox(UTF8_MBOX_NAME)

          assert_msg_uid(1)
          assert_msg_uid(mbox_id: utf8_name_mbox_id)
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        open_mail_store{
          assert_msg_uid(1)
          assert_msg_uid(mbox_id: utf8_name_mbox_id)
        }

        assert_imap_command("COPY 1 #{UTF7_MBOX_NAME}") {|assert|
          assert.match(/#{tag} OK \[COPYUID \d+ \d+ \d+\] COPY completed/)
        }

        open_mail_store{
          assert_msg_uid(1)
          assert_msg_uid(1, mbox_id: utf8_name_mbox_id)
          assert_equal('Hello world.', get_msg_text(1, mbox_id: utf8_name_mbox_id))
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_imap_closed
      }
    end

    def test_copy_utf7_mbox_name_stream
      use_imap_stream_decode_engine
      test_copy_utf7_mbox_name
    end

    def test_noop
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        open_mail_store{
          add_msg('')
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('NOOP') {|assert|
          assert.equal("#{tag} OK NOOP completed")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('NOOP') {|assert|
          assert.equal("#{tag} OK NOOP completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('NOOP') {|assert|
          assert.equal("#{tag} OK NOOP completed")
        }

        assert_imap_command('CLOSE') {|assert|
          assert.equal("#{tag} OK CLOSE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('NOOP') {|assert|
          assert.equal("#{tag} OK NOOP completed")
        }

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('NOOP') {|assert|
          assert.equal("#{tag} OK NOOP completed")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_closed
      }
    end

    def test_noop_stream
      use_imap_stream_decode_engine
      test_noop
    end

    def test_idle
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('IDLE', client_input_text: '') {|assert|
          assert.equal("#{tag} NO not authenticated")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('IDLE', client_input_text: '') {|assert|
          assert.equal("#{tag} NO not selected")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('IDLE', client_input_text: "DONE\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal("#{tag} OK IDLE terminated")
        }

        assert_imap_command('IDLE', client_input_text: "done\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal("#{tag} OK IDLE terminated")
        }

        assert_imap_command('IDLE', client_input_text: "detarame\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal("#{tag} BAD unexpected client response")
        }

        if (command_test?) then
          # not be able to close client input in stream test
          assert_imap_command('IDLE', client_input_text: '') {|assert|
            assert.match(/^\+ /)
            assert.equal("#{tag} BAD unexpected client connection close")
          }
        end

        assert_imap_command('CLOSE') {|assert|
          assert.equal("#{tag} OK CLOSE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('IDLE', client_input_text: '') {|assert|
          assert.equal("#{tag} NO not selected")
        }

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command('IDLE', client_input_text: "DONE\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal("#{tag} OK IDLE terminated")
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_closed
      }
    end

    def test_idle_stream
      use_imap_stream_decode_engine
      test_idle
    end

    def test_error_handling_stream
      use_imap_stream_decode_engine # always run in stream
      imap_decode_engine_evaluate{
        assert_imap_command('') {|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          assert.equal("#{tag} BAD client command syntax error")
        }

        assert_imap_command('no_command') {|assert|
          assert.equal("#{tag} BAD unknown command")
        }

        assert_imap_command('no_command', uid: true) {|assert|
          assert.equal("#{tag} BAD unknown uid command")
        }

        assert_imap_command('', uid: true) {|assert|
          assert.equal("#{tag} BAD empty uid parameter")
        }

        assert_imap_command('noop detarame') {|assert|
          assert.equal("#{tag} BAD invalid command parameter")
        }

        assert_imap_command("APPEND INBOX {#{LITERAL_SIZE_LIMIT + 1}}") {|assert|
          assert.equal("#{tag} BAD literal size too large")
        }

        assert_imap_command("APPEND #{literal('x' * LITERAL_SIZE_LIMIT)} #{'y' * (LINE_LENGTH_LIMIT - 3)}") {|assert|
          assert.match(/^\+ /)
          assert.equal("#{tag} BAD command size too large") # by last line
        }

        assert_imap_command("APPEND #{literal('x' * LITERAL_SIZE_LIMIT)} {#{LITERAL_SIZE_LIMIT}}") {|assert|
          assert.match(/^\+ /)
          assert.equal("#{tag} BAD command size too large") # by last literal
        }

        @tag = '*T000'
        assert_imap_command('noop') {|assert|
          assert.equal('* BAD client command syntax error')
        }

        @tag = '+T000'
        assert_imap_command('noop') {|assert|
          assert.equal('* BAD client command syntax error')
        }
      }
    end

    def test_db_recovery
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        meta_db = RIMS::DB::Meta.new(RIMS::Hash_KeyValueStore.new(@kvs["#{RIMS::MAILBOX_DATA_STRUCTURE_VERSION}/#{@unique_user_id[0, 7]}/meta"]))
        meta_db.dirty = true
        meta_db.close

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.match(/^\* OK \[ALERT\] start user data recovery/)
          assert.match(/^\* OK completed user data recovery/)
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_closed
      }
    end

    def test_db_recovery_stream
      use_imap_stream_decode_engine
      test_db_recovery
    end

    def test_mail_delivery_user
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        assert_imap_command('CAPABILITY') {|assert|
          assert.match(/^\* CAPABILITY /, peek_next_line: true).no_match(/ X-RIMS-MAIL-DELIVERY-USER/)
          assert.equal("#{tag} OK CAPABILITY completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN #postman password_of_mail_delivery_user') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('CAPABILITY') {|assert|
          assert.match(/^\* CAPABILITY /, peek_next_line: true).match(/ X-RIMS-MAIL-DELIVERY-USER/)
          assert.equal("#{tag} OK CAPABILITY completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('CREATE foo') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('DELETE foo') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('RENAME foo bar') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('SUBSCRIBE foo') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('UNSUBSCRIBE foo') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('LIST "" *') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('LSUB "" *') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('CHECK') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('CLOSE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('EXPUNGE') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('SEARCH *') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('FETCH * RFC822') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('STORE 1 +FLAGS (\Answered \Flagged \Deleted \Seen \Draft)') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        assert_imap_command('COPY * foo') {|assert|
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not allowed/)
        }

        base64_foo = RIMS::Protocol.encode_base64('foo')
        base64_nouser = RIMS::Protocol.encode_base64('nouser')

        assert_imap_command(%Q'APPEND "b64user-mbox #{base64_foo} INBOX" a') {|assert|
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1)
          assert_equal('a', get_msg_text(1))
          assert_msg_flags(1, recent: true)
        }

        assert_imap_command(%Q'APPEND "b64user-mbox #{base64_foo} INBOX" (\\Answered \\Flagged \\Deleted \\Seen \\Draft) "19-Nov-1975 12:34:56 +0900" b') {|assert|
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1, 2)
          assert_equal('b', get_msg_text(2))
          assert_equal(Time.utc(1975, 11, 19, 3, 34, 56), get_msg_date(2))
          assert_msg_flags(2, answered: true, flagged: true, deleted: true, seen: true, draft: true, recent: true)
        }

        assert_imap_command(%Q'APPEND "b64user-mbox #{base64_foo} nobox" x') {|assert|
          assert.match(/^#{tag} NO \[TRYCREATE\]/, peek_next_line: true).match(/not found.* mailbox/)
        }

        open_mail_store{
          assert_msg_uid(1, 2)
        }

        assert_imap_command(%Q'APPEND "b64user-mbox #{base64_nouser} INBOX" x') {|assert|
          assert.match(/^#{tag} NO/, peek_next_line: true).match(/not found.* user/)
        }

        open_mail_store{
          assert_msg_uid(1, 2)
        }

        assert_imap_command(%Q'APPEND "unknown-encode-type #{base64_foo} INBOX" x') {|assert|
          assert.match(/^#{tag} BAD /, peek_next_line: true).match(/syntax error/)
        }

        open_mail_store{
          assert_msg_uid(1, 2)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_closed
      }
    end

    def test_mail_delivery_user_stream
      use_imap_stream_decode_engine
      test_mail_delivery_user
    end

    def test_mail_delivery_user_db_recovery
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        meta_db = RIMS::DB::Meta.new(RIMS::Hash_KeyValueStore.new(@kvs["#{RIMS::MAILBOX_DATA_STRUCTURE_VERSION}/#{@unique_user_id[0, 7]}/meta"]))
        meta_db.dirty = true
        meta_db.close

        assert_imap_command('CAPABILITY') {|assert|
          assert.match(/^\* CAPABILITY /, peek_next_line: true).no_match(/ X-RIMS-MAIL-DELIVERY-USER/)
          assert.equal("#{tag} OK CAPABILITY completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_command('LOGIN #postman password_of_mail_delivery_user') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_equal(true, @decoder.auth?) if command_test?

        assert_imap_command('CAPABILITY') {|assert|
          assert.match(/^\* CAPABILITY /, peek_next_line: true).match(/ X-RIMS-MAIL-DELIVERY-USER/)
          assert.equal("#{tag} OK CAPABILITY completed")
        }

        base64_foo = RIMS::Protocol.encode_base64('foo')

        assert_imap_command(%Q'APPEND "b64user-mbox #{base64_foo} INBOX" a') {|assert|
          assert.match(/^\* OK \[ALERT\] start user data recovery/)
          assert.match(/^\* OK completed user data recovery/)
          assert.match(/^#{tag} OK \[APPENDUID \d+ \d+\] APPEND completed/)
        }

        open_mail_store{
          assert_msg_uid(1)
          assert_equal('a', get_msg_text(1))
          assert_msg_flags(1, recent: true)
        }

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        assert_equal(false, @decoder.auth?) if command_test?

        assert_imap_closed
      }
    end

    def test_mail_delivery_user_db_recovery_stream
      use_imap_stream_decode_engine
      test_mail_delivery_user_db_recovery
    end

    def test_autologout_not_authenticated_idle_too_long_stream
      use_imap_stream_decode_engine
      imap_decode_engine_evaluate{
        @limits.command_wait_timeout_seconds = 0.1

        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          assert.equal("* BYE server autologout: idle for too long")
        }
      }
    end

    def test_autologout_not_authenticated_shutdown_stream
      use_imap_stream_decode_engine
      imap_decode_engine_evaluate{
        @limits.command_wait_timeout_seconds = 0

        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          assert.equal("* BYE server autologout: shutdown")
        }
      }
    end

    def test_autologout_authenticated_idle_too_long_stream
      use_imap_stream_decode_engine
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        @limits.command_wait_timeout_seconds = 0.1

        assert_untagged_response{|assert|
          assert.equal("* BYE server autologout: idle for too long")
        }
      }
    end

    def test_autologout_authenticated_shutdown_stream
      use_imap_stream_decode_engine
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        @limits.command_wait_timeout_seconds = 0

        assert_untagged_response{|assert|
          assert.equal("* BYE server autologout: shutdown")
        }
      }
    end

    def test_autologout_selected_idle_too_long_stream
      use_imap_stream_decode_engine
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        @limits.command_wait_timeout_seconds = 0.1

        assert_untagged_response{|assert|
          assert.equal("* BYE server autologout: idle for too long")
        }
      }
    end

    def test_autologout_selected_shutdown_stream
      use_imap_stream_decode_engine
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        @limits.command_wait_timeout_seconds = 0

        assert_untagged_response{|assert|
          assert.equal("* BYE server autologout: shutdown")
        }
      }
    end

    def test_autologout_idling_idle_too_long_stream
      use_imap_stream_decode_engine
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        assert_imap_command('IDLE', client_input_text: '') {|assert|
          assert.match(/^\+ /)
        }

        @limits.command_wait_timeout_seconds = 0.1

        assert_untagged_response{|assert|
          assert.equal("* BYE server autologout: idle for too long")
        }
      }
    end

    def test_autologout_idling_shutdown_stream
      use_imap_stream_decode_engine
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        assert_imap_command('IDLE', client_input_text: '') {|assert|
          assert.match(/^\+ /)
        }

        @limits.command_wait_timeout_seconds = 0

        assert_untagged_response{|assert|
          assert.equal("* BYE server autologout: shutdown")
        }
      }
    end

    def test_untagged_server_response
      imap_decode_engine_evaluate{
        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.") if stream_test?
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.equal('* 0 EXISTS')
          assert.equal('* 0 RECENT')
          assert.equal('* OK [UNSEEN 0]')
          assert.equal('* OK [UIDVALIDITY 1]')
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        another_decoder = make_decoder
        another_writer = proc{|response|
          p response if $DEBUG
        }

        another_decoder.login('tag', 'foo', 'open_sesame', &another_writer)
        another_decoder = another_decoder.next_decoder
        assert_equal(true, another_decoder.auth?)

        another_decoder.select('tag', 'INBOX', &another_writer)
        another_decoder = another_decoder.next_decoder
        assert_equal(true, another_decoder.selected?)

        n = 1
        another_decoder.append('tag', 'INBOX', [ :group, '\Deleted' ], 'test', &another_writer)
        assert_imap_command('NOOP') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK NOOP completed")
        }

        n += 1
        another_decoder.copy('tag', '1', 'INBOX', &another_writer)
        assert_imap_command('NOOP') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK NOOP completed")
        }

        n -= 1
        another_decoder.expunge('tag', &another_writer)
        assert_imap_command('NOOP') {|assert|
          assert.equal('* 1 EXPUNGE')
          assert.equal("#{tag} OK NOOP completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('CREATE foo') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK CREATE completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('RENAME foo bar') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK RENAME completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('DELETE bar') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK DELETE completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('SUBSCRIBE INBOX') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK SUBSCRIBE completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('UNSUBSCRIBE INBOX') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.match(/^#{tag} NO /, peek_next_line: true).match(/not implemented/)
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('LIST "" *') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal('* LIST (\Noinferiors \Marked) NIL "INBOX"')
          assert.equal("#{tag} OK LIST completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('LSUB "" *') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal('* LSUB (\Noinferiors \Marked) NIL "INBOX"')
          assert.equal("#{tag} OK LSUB completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('STATUS INBOX (MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN)') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("* STATUS \"INBOX\" (MESSAGES #{n} RECENT #{n} UIDNEXT #{(n+1).succ} UIDVALIDITY #{@inbox_id} UNSEEN #{n})")
          assert.equal("#{tag} OK STATUS completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        n += 1
        assert_imap_command('APPEND INBOX test') {|assert|
          assert.equal("* #{n-1} EXISTS")
          assert.equal("* #{n-1} RECENT")
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK [APPENDUID 1 #{n+1}] APPEND completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('CHECK') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK CHECK completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('EXPUNGE') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK EXPUNGE completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('SEARCH *') {|assert|
          assert.equal("* #{n} EXISTS\r\n")
          assert.equal("* #{n} RECENT\r\n")
          assert.equal("* SEARCH #{n}\r\n")
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('FETCH 1 BODY.PEEK[]') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal(%Q'* 1 FETCH (BODY[] "test")')
          assert.equal("#{tag} OK FETCH completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('STORE 1 +FLAGS (\Flagged)') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal('* 1 FETCH (FLAGS (\Flagged \Recent))')
          assert.equal("#{tag} OK STORE completed")
        }

        n += 2
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('COPY 1 INBOX') {|assert|
          assert.equal("* #{n-1} EXISTS")
          assert.equal("* #{n-1} RECENT")
          assert.equal("* #{n} EXISTS")
          assert.equal("* #{n} RECENT")
          assert.equal("#{tag} OK [COPYUID 1 2 #{n+1}] COPY completed")
        }

        open_mail_store{
          f = @mail_store.open_folder(@inbox_id, read_only: true)
          begin
            uid_list = @mail_store.each_msg_uid(@inbox_id).to_a
            last_uid = uid_list.min
            @mail_store.set_msg_flag(@inbox_id, last_uid, 'deleted', true)
          ensure
            f.close
          end
        }

        n -= 1
        another_decoder.close('tag', &another_writer)
        assert_imap_command('NOOP') {|assert|
          assert.equal("* 1 EXPUNGE")
          assert.equal("* 0 RECENT")
          assert.equal("#{tag} OK NOOP completed")
        }

        open_mail_store{
          f = @mail_store.open_folder(@inbox_id, read_only: true)
          begin
            uid_list = @mail_store.each_msg_uid(@inbox_id).to_a
            last_uid = uid_list.min
            @mail_store.set_msg_flag(@inbox_id, last_uid, 'deleted', true)
          ensure
            f.close
          end
        }

        another_decoder.create('tag', 'foo', &another_writer)
        another_decoder.examine('tag', 'INBOX', &another_writer)
        another_decoder.examine('tag', 'foo', &another_writer) # closed INBOX implicitly
        another_decoder.close('tag', 'foo', &another_writer)
        assert_imap_command('NOOP') {|assert|
          # no untagged responses on implicit INBOX close because
          # INBOX is opened as read-only.
          assert.equal("#{tag} OK NOOP completed")
        }

        n -= 1
        another_decoder.select('tag', 'INBOX', &another_writer)
        another_decoder.select('tag', 'foo', &another_writer) # closed INBOX implicitly
        another_decoder.close('tag', 'foo', &another_writer)
        assert_imap_command('NOOP') {|assert|
          assert.equal("* 1 EXPUNGE")
          assert.equal("#{tag} OK NOOP completed")
        }

        n += 1
        another_decoder.append('tag', 'INBOX', 'test', &another_writer)
        assert_imap_command('CLOSE') {|assert|
          # IMAP CLOSE command releases a mailbox that has a status to
          # be notified, and it will not send untagged responses
          # notified from other connections.
          assert.equal("#{tag} OK CLOSE completed")
        }

        assert_imap_command('EXAMINE INBOX') {|assert|
          assert.equal("* #{n} EXISTS")
          assert.equal('* 0 RECENT')
          assert.equal("* OK [UNSEEN #{n}]")
          assert.equal('* OK [UIDVALIDITY 1]')
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-ONLY] EXAMINE completed")
        }

        open_mail_store{
          f = @mail_store.open_folder(@inbox_id, read_only: true)
          begin
            uid_list = @mail_store.each_msg_uid(@inbox_id).to_a
            last_uid = uid_list.min
            @mail_store.set_msg_flag(@inbox_id, last_uid, 'deleted', true)
          ensure
            f.close
          end
        }

        n -= 1
        another_decoder.select('tag', 'INBOX', &another_writer)
        another_decoder.cleanup # closed INBOX implicitly
        assert_imap_command('NOOP') {|assert|
          assert.equal("* 1 EXPUNGE")
          assert.equal("#{tag} OK NOOP completed")
        }
      }
    end

    def test_untagged_server_response_stream
      use_imap_stream_decode_engine
      test_untagged_server_response
    end

    def test_idle_untagged_server_response
      imap_decode_engine_evaluate{
        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.") if stream_test?
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.equal('* 0 EXISTS')
          assert.equal('* 0 RECENT')
          assert.equal('* OK [UNSEEN 0]')
          assert.equal('* OK [UIDVALIDITY 1]')
          assert.equal('* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        another_decoder = make_decoder
        another_writer = proc{|response|
          p response if $DEBUG
        }

        another_decoder.login('tag', 'foo', 'open_sesame', &another_writer)
        another_decoder = another_decoder.next_decoder
        assert_equal(true, another_decoder.auth?)

        another_decoder.select('tag', 'INBOX', &another_writer)
        another_decoder = another_decoder.next_decoder
        assert_equal(true, another_decoder.selected?)

        another_decoder.append('tag', 'INBOX', [ :group, '\Deleted' ], 'test', &another_writer)
        assert_imap_command('IDLE', client_input_text: "DONE\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal('* 1 EXISTS')
          assert.equal('* 1 RECENT')
          assert.equal("#{tag} OK IDLE terminated")
        }

        another_decoder.copy('tag', '1', 'INBOX', &another_writer)
        assert_imap_command('IDLE', client_input_text: "DONE\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal('* 2 EXISTS')
          assert.equal('* 2 RECENT')
          assert.equal("#{tag} OK IDLE terminated")
        }

        another_decoder.expunge('tag', &another_writer)
        assert_imap_command('IDLE', client_input_text: "DONE\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal('* 1 EXPUNGE')
          assert.equal("#{tag} OK IDLE terminated")
        }

        open_mail_store{
          f = @mail_store.open_folder(@inbox_id, read_only: true)
          begin
            uid_list = @mail_store.each_msg_uid(@inbox_id).to_a
            last_uid = uid_list.min
            @mail_store.set_msg_flag(@inbox_id, last_uid, 'deleted', true)
          ensure
            f.close
          end
        }

        another_decoder.close('tag', &another_writer)
        assert_imap_command('IDLE', client_input_text: "DONE\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal('* 1 EXPUNGE')
          assert.equal('* 0 RECENT')
          assert.equal("#{tag} OK IDLE terminated")
        }

        another_decoder.cleanup
      }
    end

    def test_idle_untagged_server_response_stream
      use_imap_stream_decode_engine
      test_idle_untagged_server_response
    end

    def test_charset_aliases
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        platform_dependent_character = "\u2460"
        open_mail_store{
          add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                  "\r\n" +
                  "#{platform_dependent_character.encode(Encoding::CP50221).b}")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command("SEARCH CHARSET utf-8 TEXT #{literal(platform_dependent_character)}") {|assert|
          assert.match(/^\+ /)
          assert.equal("* SEARCH\r\n") # skip by `EncodingError'
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        # not recommend changing charset aliases after passing them to the decoder.
        # here, the charset aliases are reluctantly changed for testing.
        @charset_aliases.add_alias('iso-2022-jp', Encoding::CP50221)

        assert_imap_command("SEARCH CHARSET utf-8 TEXT #{literal(platform_dependent_character)}") {|assert|
          assert.match(/^\+ /)
          assert.equal("* SEARCH 1\r\n") # matched!
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('CLOSE') {|assert|
          assert.equal("#{tag} OK CLOSE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_closed
      }
    end

    def test_charset_aliases_stream
      use_imap_stream_decode_engine
      test_charset_aliases
    end

    def test_charset_convert_options
      imap_decode_engine_evaluate{
        if (stream_test?) then
          assert_untagged_response{|assert|
            assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
          }
        end

        platform_dependent_character = "\u2460"
        open_mail_store{
          add_msg("Content-Type: text/plain; charset=iso-2022-jp\r\n" +
                  "\r\n" +
                  "#{platform_dependent_character.encode(Encoding::CP50221).b}")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(true, @decoder.selected?)
        end

        assert_imap_command(%Q'SEARCH CHARSET utf-8 TEXT #{literal("\uFFFD")}') {|assert|
          assert.match(/^\+ /)
          assert.equal("* SEARCH\r\n") # skip by `EncodingError'
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        # not recommend changing charset convert options after passing them to the decoder.
        # here, the options are reluctantly changed for testing.
        @charset_convert_options[:undef] = :replace

        assert_imap_command("SEARCH CHARSET utf-8 TEXT #{literal("\uFFFD")}") {|assert|
          assert.match(/^\+ /)
          assert.equal("* SEARCH 1\r\n") # matched!
          assert.equal("#{tag} OK SEARCH completed\r\n")
        }

        assert_imap_command('CLOSE') {|assert|
          assert.equal("#{tag} OK CLOSE completed")
        }

        if (command_test?) then
          assert_equal(true, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_command('LOGOUT') {|assert|
          assert.match(/^\* BYE /)
          assert.equal("#{tag} OK LOGOUT completed")
        }

        if (command_test?) then
          assert_equal(false, @decoder.auth?)
          assert_equal(false, @decoder.selected?)
        end

        assert_imap_closed
      }
    end

    def test_charset_convert_options_stream
      use_imap_stream_decode_engine
      test_charset_convert_options
    end

    def test_command_line_too_long_error_stream
      use_imap_stream_decode_engine # always run in stream
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('APPEND INBOX ' + 'x' * LINE_LENGTH_LIMIT) {|assert|
          assert.equal('* BAD line too long')
          assert.equal('* BYE server autologout: connection terminated')
        }

        assert_imap_closed
      }
    end

    def test_authenticate_line_too_long_error_stream
      use_imap_stream_decode_engine # always run in stream
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('AUTHENTICATE plain',
                            client_input_text: 'x' * LINE_LENGTH_LIMIT + "\r\n") {|assert|
          assert.equal('+ ')
          assert.equal('* BAD line too long')
          assert.equal('* BYE server autologout: connection terminated')
        }

        assert_imap_closed
      }
    end

    def test_idle_line_too_long_error_stream
      use_imap_stream_decode_engine # always run in stream
      imap_decode_engine_evaluate{
        assert_untagged_response{|assert|
          assert.equal("* OK RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.")
        }

        assert_imap_command('LOGIN foo open_sesame') {|assert|
          assert.equal("#{tag} OK LOGIN completed")
        }

        assert_imap_command('SELECT INBOX') {|assert|
          assert.skip_while{|line| line =~ /^\* / }
          assert.equal("#{tag} OK [READ-WRITE] SELECT completed")
        }

        assert_imap_command('IDLE', client_input_text: 'DONE' + ' ' * LINE_LENGTH_LIMIT +  "\r\n") {|assert|
          assert.match(/^\+ /)
          assert.equal('* BAD line too long')
          assert.equal('* BYE server autologout: connection terminated')
        }

        assert_imap_closed
      }
    end
  end

  class ProtocolMailDeliveryDecoderTest < Test::Unit::TestCase
    def test_decode_delivery_target_mailbox
      base64_username = RIMS::Protocol.encode_base64('foo')

      assert_equal([ 'foo', 'INBOX' ],
                   RIMS::Protocol::Decoder.decode_delivery_target_mailbox("b64user-mbox #{base64_username} INBOX"))
      assert_equal([ 'foo', 'a mailbox ' ],
                   RIMS::Protocol::Decoder.decode_delivery_target_mailbox("b64user-mbox #{base64_username} a mailbox "))

      error = assert_raise(RIMS::SyntaxError) {
        RIMS::Protocol::Decoder.decode_delivery_target_mailbox("unknown-encode-type #{base64_username} INBOX")
      }
      assert_match(/unknown mailbox encode type/, error.message)
    end

    def test_encode_delivery_target_mailbox
      encoded_mbox_name = RIMS::Protocol::Decoder.encode_delivery_target_mailbox('foo', 'INBOX')
      assert_equal(%w[ foo INBOX ], RIMS::Protocol::Decoder.decode_delivery_target_mailbox(encoded_mbox_name))
    end
  end

  class ProtocolDecoderBulkResponseTest < Test::Unit::TestCase
    def setup
      limit_count = 10
      limit_size = 100
      @res = RIMS::Protocol::Decoder::BulkResponse.new(limit_count, limit_size)
    end

    data('empty' => [ 0, 0,  [] ],
         '1'     => [ 1, 3,  %w[ foo ] ],
         '2'     => [ 2, 6,  %w[ foo bar ] ],
         '3'     => [ 3, 11, %w[ foo bar baaaz ] ])
    def test_add(data)
      expected_count, expected_size, response_list = data

      assert_equal(0, @res.count)
      assert_equal(0, @res.size)

      for response in response_list
        @res << response
      end

      assert_equal(expected_count, @res.count)
      assert_equal(expected_size, @res.size)
    end

    def test_emtpy?
      assert_true(@res.empty?)
    end

    def test_not_empty?
      @res << 'foo'
      assert_false(@res.empty?)
    end

    data('count: boundary'      => %w[ 1 2 3 4 5 6 7 8 9 0 ],
         'count: over'          => %w[ 1 2 3 4 5 6 7 8 9 0 a ],
         'size: boundary'       => [ 'x' * 50, 'y' * 50 ],
         'size: over'           => [ 'x' * 50, 'y' * 50, 'z' ],
         'count,size: boundary' => %w[ 1 2 3 4 5 6 7 8 9 0 ].map{|s| s * 10 },
         'count,size: over'     => %w[ 1 2 3 4 5 6 7 8 9 0 ].map{|s| s * 10 } + %w[ a ])
    def test_full?(data)
      response_list = data
      for response in response_list
        @res << response
      end
      assert_true(@res.full?)
    end

    data('empty'           => [],
         'under'           => %w[ foo bar baz ],
         'count: boundary' => %w[ 1 2 3 4 5 6 7 8 9 ],
         'size: boundary'  => [ 'x' * 50, 'y' * 49 ])
    def test_not_full?(data)
      response_list = data
      for response in response_list
        @res << response
      end
      assert_false(@res.full?)
    end

    def test_flush
      @res << 'foo'
      @res << 'bar'
      r1 = @res.flush
      assert_equal('foo' + 'bar', r1.join(''), 'responses may be joined.')
      assert_true(@res.empty?)
      assert_false(@res.full?)

      @res << 'baz'
      r2 = @res.flush
      assert_equal('baz', r2.join(''), 'responses may be joined.')
      assert_true(@res.empty?)
      assert_false(@res.full?)

      assert_not_equal(r1, r2)
    end

    def test_flush_joined
      for c in ('a'..).first(10)
        @res << c
      end
      assert_equal([ ('a'..).first(10).join('') ], @res.flush)
      assert_true(@res.empty?)
      assert_false(@res.full?)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
