# -*- coding: utf-8 -*-

require 'set'
require 'time'

module RIMS
  module Protocol
    FetchBody = Struct.new(:symbol, :option, :section, :section_list, :partial_origin, :partial_size)

    class FetchBody
      def fetch_att_name
        s = ''
        s << symbol
        s << '.' << option if option
        s << '[' << section << ']'
        if (partial_origin) then
          s << '<' << partial_origin.to_s << '.' << partial_size.to_s << '>'
        end

        s
      end

      def msg_att_name
        s = ''
        s << symbol
        s << '[' << section << ']'
        if (partial_origin) then
          s << '<' << partial_origin.to_s << '>'
        end

        s
      end
    end

    class RequestReader
      def initialize(input, output, logger)
        @input = input
        @output = output
        @logger = logger
      end

      def read_line
        line = @input.gets or return
        @logger.debug("read line: #{Protocol.io_data_log(line)}") if @logger.debug?
        line.chomp!("\n")
        line.chomp!("\r")
        scan_line(line)
      end

      def scan_line(line)
        atom_list = line.scan(/BODY(?:\.\S+)?\[.*?\](?:<\d+\.\d+>)?|[\[\]()]|".*?"|[^\[\]()\s]+/i).map{|s|
          case (s)
          when '(', ')', '[', ']', /\ANIL\z/i
            s.upcase.intern
          when /\A"/
            s.sub(/\A"/, '').sub(/"\z/, '')
          when /\A(?<body_symbol>BODY)(?:\.(?<body_option>\S+))?\[(?<body_section>.*)\](?:<(?<partial_origin>\d+\.(?<partial_size>\d+)>))?\z/i
            body_symbol = $~[:body_symbol]
            body_option = $~[:body_option]
            body_section = $~[:body_section]
            partial_origin = $~[:partial_origin] && $~[:partial_origin].to_i
            partial_size = $~[:partial_size] && $~[:partial_size].to_i
            [ :body,
              Protocol.body(symbol: body_symbol,
                            option: body_option,
                            section: body_section,
                            partial_origin: partial_origin,
                            partial_size: partial_size)
            ]
          else
            s
          end
        }
        if ((atom_list[-1].is_a? String) && (atom_list[-1] =~ /\A{\d+}\z/)) then
          next_size = $&[1..-2].to_i
          @logger.debug("found literal: #{next_size} octets.") if @logger.debug?
          @output.write("+ continue\r\n")
          @output.flush
          @logger.debug('continue literal.') if @logger.debug?
          literal_string = @input.read(next_size) or raise 'unexpected client close.'
          @logger.debug("read literal: #{Protocol.io_data_log(literal_string)}") if @logger.debug?
          atom_list[-1] = literal_string
          next_atom_list = read_line or raise 'unexpected client close.'
          atom_list += next_atom_list
        end

        atom_list
      end

      def parse(atom_list, last_atom=nil)
        syntax_list = []
        while (atom = atom_list.shift)
          case (atom)
          when last_atom
            break
          when :'('
            syntax_list.push([ :group ] + parse(atom_list, :')'))
          when :'['
            syntax_list.push([ :block ] + parse(atom_list, :']'))
          else
            if ((atom.is_a? Array) && (atom[0] == :body)) then
              body = atom[1]
              body.section_list = parse(scan_line(body.section))
            end
            syntax_list.push(atom)
          end
        end

        if (atom == nil && last_atom != nil) then
          raise 'syntax error.'
        end

        syntax_list
      end

      def read_command
        while (atom_list = read_line)
          if (atom_list.empty?) then
            next
          end
          if (atom_list.length < 2) then
            raise 'need for tag and command.'
          end
          if (atom_list[0] =~ /\A[*+]/) then
            raise "invalid command tag: #{atom_list[0]}"
          end
          return parse(atom_list)
        end

        nil
      end
    end

    class AuthenticationReader
      def initialize(auth, input_gets, output_write, logger)
        @auth = auth
        @input_gets = input_gets
        @output_write = output_write
        @logger = logger
      end

      def authenticate_client(auth_type, inline_client_response_data_base64=nil)
        username = case (auth_type.downcase)
                   when 'plain'
                     @logger.debug("authentication mechanism: plain") if @logger.debug?
                     authenticate_client_plain(inline_client_response_data_base64)
                   when 'cram-md5'
                     @logger.debug("authentication mechanism: cram-md5") if @logger.debug?
                     authenticate_client_cram_md5
                   else
                     nil
                   end

        case (username)
        when String
          @logger.debug("authenticated #{username}.") if @logger.debug?
          username
        when Symbol
          @logger.debug('no authentication.') if @logger.debug?
          username
        else
          @logger.debug('unauthenticated.') if @logger.debug?
          nil
        end
      end

      def read_client_response_data(server_challenge_data=nil)
        if (server_challenge_data) then
          server_challenge_data_base64 = Protocol.encode_base64(server_challenge_data)
          @logger.debug("authenticate command: server challenge data: #{Protocol.io_data_log(server_challenge_data_base64)}") if @logger.debug?
          @output_write.call([ "+ #{server_challenge_data_base64}\r\n" ])
        else
          @logger.debug("authenticate command: server challenge data is nil.") if @logger.debug?
          @output_write.call([ "+ \r\n" ])
        end

        if (client_response_data_base64 = @input_gets.call) then
          client_response_data_base64.strip!
          @logger.debug("authenticate command: client response data: #{Protocol.io_data_log(client_response_data_base64)}") if @logger.debug?
          if (client_response_data_base64 == '*') then
            @logger.debug("authenticate command: no authentication from client.") if @logger.debug?
            return :*
          end
          Protocol.decode_base64(client_response_data_base64)
        end
      end
      private :read_client_response_data

      def read_client_response_data_plain(inline_client_response_data_base64)
        if (inline_client_response_data_base64) then
          @logger.debug("authenticate command: inline client response data: #{Protocol.io_data_log(inline_client_response_data_base64)}") if @logger.debug?
          Protocol.decode_base64(inline_client_response_data_base64)
        else
          read_client_response_data
        end
      end
      private :read_client_response_data_plain

      def authenticate_client_plain(inline_client_response_data_base64)
        case (client_response_data = read_client_response_data_plain(inline_client_response_data_base64))
        when String
          @auth.authenticate_plain(client_response_data)
        when Symbol
          client_response_data
        else
          nil
        end
      end
      private :authenticate_client_plain

      def authenticate_client_cram_md5
        server_challenge_data = @auth.cram_md5_server_challenge_data
        case (client_response_data = read_client_response_data(server_challenge_data))
        when String
          @auth.authenticate_cram_md5(server_challenge_data, client_response_data)
        when Symbol
          client_response_data
        else
          nil
        end
      end
      private :authenticate_client_cram_md5
    end

    class SearchParser
      def initialize(mail_store, folder)
        @mail_store = mail_store
        @folder = folder
        @charset = nil
        @mail_cache = Hash.new{|hash, uid|
          if (msg_txt = @mail_store.msg_text(@folder.mbox_id, uid)) then
            hash[uid] = RFC822::Message.new(msg_txt)
          end
        }
      end

      def get_mail(msg)
        @mail_cache[msg.uid] or raise "not found a mail: #{msg.uid}"
      end
      private :get_mail

      attr_accessor :charset

      def string_include?(search_string, text)
        if (search_string.ascii_only?) then
          unless (text.encoding.ascii_compatible?) then
            text = text.encode('utf-8')
          end
        else
          if (@charset) then
            search_string = search_string.dup.force_encoding(@charset)
            text = text.encode(@charset)
          end
        end

        text.include? search_string
      end
      private :string_include?

      def mail_body_text(mail)
        if (mail.text? || mail.message?) then
          body_txt = mail.body.raw_source
          if (charset = mail.charset) then
            if (body_txt.encoding != Encoding.find(charset)) then
              body_txt = body_txt.dup.force_encoding(charset)
            end
          end
          body_txt
        else
          nil
        end
      end
      private :mail_body_text

      def end_of_cond
        proc{|msg| true }
      end
      private :end_of_cond

      def parse_all
        proc{|next_cond|
          proc{|msg|
            next_cond.call(msg)
          }
        }
      end
      private :parse_all

      def parse_msg_flag_enabled(name)
        proc{|next_cond|
          proc{|msg|
            @mail_store.msg_flag(@folder.mbox_id, msg.uid, name) && next_cond.call(msg)
          }
        }
      end
      private :parse_msg_flag_enabled

      def parse_msg_flag_disabled(name)
        proc{|next_cond|
          proc{|msg|
            (! @mail_store.msg_flag(@folder.mbox_id, msg.uid, name)) && next_cond.call(msg)
          }
        }
      end
      private :parse_msg_flag_enabled

      def parse_search_header(field_name, search_string)
        proc{|next_cond|
          proc{|msg|
            mail = get_mail(msg)
            if (mail.header.key? field_name) then
              mail.header.field_value_list(field_name).any?{|field_value|
                string_include?(search_string, field_value)
              } && next_cond.call(msg)
            else
              false
            end
          }
        }
      end
      private :parse_search_header

      def parse_internal_date(search_time) # :yields: mail_date, boundary
        d = search_time.to_date
        proc{|next_cond|
          proc{|msg|
            yield(@mail_store.msg_date(@folder.mbox_id, msg.uid).to_date, d) && next_cond.call(msg)
          }
        }
      end
      private :parse_internal_date

      def parse_mail_date(search_time) # :yields: internal_date, boundary
        d = search_time.to_date
        proc{|next_cond|
          proc{|msg|
            if (mail_datetime = get_mail(msg).date) then
              yield(mail_datetime.to_date, d) && next_cond.call(msg)
            else
              false
            end
          }
        }
      end
      private :parse_mail_date

      def parse_mail_bytesize(octet_size) # :yields: mail_bytesize, boundary
        proc{|next_cond|
          proc{|msg|
            yield(@mail_store.msg_text(@folder.mbox_id, msg.uid).bytesize, octet_size) && next_cond.call(msg)
          }
        }
      end
      private :parse_mail_bytesize

      def parse_body(search_string)
        proc{|next_cond|
          proc{|msg|
            if (text = mail_body_text(get_mail(msg))) then
              string_include?(search_string, text) && next_cond.call(msg)
            else
              false
            end
          }
        }
      end
      private :parse_body

      def parse_keyword(search_string)
        proc{|next_cond|
          proc{|msg|
            false
          }
        }
      end
      private :parse_keyword

      def parse_new
        proc{|next_cond|
          proc{|msg|
            @mail_store.msg_flag(@folder.mbox_id, msg.uid, 'recent') && \
            (! @mail_store.msg_flag(@folder.mbox_id, msg.uid, 'seen')) && next_cond.call(msg)
          }
        }
      end
      private :parse_new

      def parse_not(next_node)
        operand = next_node.call(end_of_cond)
        proc{|next_cond|
          proc{|msg|
            (! operand.call(msg)) && next_cond.call(msg)
          }
        }
      end
      private :parse_not

      def parse_old
        proc{|next_cond|
          proc{|msg|
            (! @mail_store.msg_flag(@folder.mbox_id, msg.uid, 'recent')) && next_cond.call(msg)
          }
        }
      end
      private :parse_old

      def parse_or(next_node1, next_node2)
        operand1 = next_node1.call(end_of_cond)
        operand2 = next_node2.call(end_of_cond)
        proc{|next_cond|
          proc{|msg|
            (operand1.call(msg) || operand2.call(msg)) && next_cond.call(msg)
          }
        }
      end
      private :parse_or

      def parse_text(search_string)
        search = proc{|text| string_include?(search_string, text) }
        proc{|next_cond|
          proc{|msg|
            mail = get_mail(msg)
            body_txt = mail_body_text(mail)
            (search.call(mail.header.raw_source) || (body_txt && search.call(body_txt))) && next_cond.call(msg)
          }
        }
      end
      private :parse_text

      def parse_uid(msg_set)
        proc{|next_cond|
          proc{|msg|
            (msg_set.include? msg.uid) && next_cond.call(msg)
          }
        }
      end
      private :parse_uid

      def parse_unkeyword(search_string)
        parse_all
      end
      private :parse_unkeyword

      def parse_msg_set(msg_set)
        proc{|next_cond|
          proc{|msg|
            (msg_set.include? msg.num) && next_cond.call(msg)
          }
        }
      end
      private :parse_msg_set

      def parse_group(search_key)
        group_cond = parse_cached(search_key)
        proc{|next_cond|
          proc{|msg|
            group_cond.call(msg) && next_cond.call(msg)
          }
        }
      end
      private :parse_group

      def shift_string_value(operation_name, search_key)
        unless (search_string = search_key.shift) then
          raise SyntaxError, "need for a search string of #{operation_name}."
        end
        unless (search_string.is_a? String) then
          raise SyntaxError, "#{operation_name} search string expected as <String> but was <#{search_string.class}>."
        end

        search_string
      end
      private :shift_string_value

      def shift_date_value(operation_name, search_key)
        unless (search_date_string = search_key.shift) then
          raise SyntaxError, "need for a search date of #{operation_name}."
        end
        unless (search_date_string.is_a? String) then
          raise SyntaxError, "#{operation_name} search date string expected as <String> but was <#{search_date_string.class}>."
        end

        begin
          Time.parse(search_date_string)
        rescue ArgumentError
          raise SyntaxError, "#{operation_name} search date is invalid: #{search_date_string}"
        end
      end
      private :shift_date_value

      def shift_octet_size_value(operation_name, search_key)
        unless (octet_size_string = search_key.shift) then
          raise SyntaxError, "need for a octet size of #{operation_name}."
        end
        unless ((octet_size_string.is_a? String) && (octet_size_string =~ /\A\d+\z/)) then
          raise SyntaxError, "#{operation_name} octet size is expected as numeric string but was <#{octet_size_string}>."
        end

        octet_size_string.to_i
      end
      private :shift_octet_size_value

      def fetch_next_node(search_key)
        if (search_key.empty?) then
          raise SyntaxError, 'unexpected end of search key.'
        end

        op = search_key.shift
        op = op.upcase if (op.is_a? String)

        case (op)
        when 'ALL'
          factory = parse_all
        when 'ANSWERED'
          factory = parse_msg_flag_enabled('answered')
        when 'BCC'
          search_string = shift_string_value('BCC', search_key)
          factory = parse_search_header('bcc', search_string)
        when 'BEFORE'
          search_date = shift_date_value('BEFORE', search_key)
          factory = parse_internal_date(search_date) {|d, boundary| d < boundary }
        when 'BODY'
          search_string = shift_string_value('BODY', search_key)
          factory = parse_body(search_string)
        when 'CC'
          search_string = shift_string_value('CC', search_key)
          factory = parse_search_header('cc', search_string)
        when 'DELETED'
          factory = parse_msg_flag_enabled('deleted')
        when 'DRAFT'
          factory = parse_msg_flag_enabled('draft')
        when 'FLAGGED'
          factory = parse_msg_flag_enabled('flagged')
        when 'FROM'
          search_string = shift_string_value('FROM', search_key)
          factory = parse_search_header('from', search_string)
        when 'HEADER'
          header_name = shift_string_value('HEADER', search_key)
          search_string = shift_string_value('HEADER', search_key)
          factory = parse_search_header(header_name, search_string)
        when 'KEYWORD'
          search_string = shift_string_value('KEYWORD', search_key)
          factory = parse_keyword(search_string)
        when 'LARGER'
          octet_size = shift_octet_size_value('LARGER', search_key)
          factory = parse_mail_bytesize(octet_size) {|size, boundary| size > boundary }
        when 'NEW'
          factory = parse_new
        when 'NOT'
          next_node = fetch_next_node(search_key)
          factory = parse_not(next_node)
        when 'OLD'
          factory = parse_old
        when 'ON'
          search_date = shift_date_value('ON', search_key)
          factory = parse_internal_date(search_date) {|d, boundary| d == boundary }
        when 'OR'
          next_node1 = fetch_next_node(search_key)
          next_node2 = fetch_next_node(search_key)
          factory = parse_or(next_node1, next_node2)
        when 'RECENT'
          factory = parse_msg_flag_enabled('recent')
        when 'SEEN'
          factory = parse_msg_flag_enabled('seen')
        when 'SENTBEFORE'
          search_date = shift_date_value('SENTBEFORE', search_key)
          factory = parse_mail_date(search_date) {|d, boundary| d < boundary }
        when 'SENTON'
          search_date = shift_date_value('SENTON', search_key)
          factory = parse_mail_date(search_date) {|d, boundary| d == boundary }
        when 'SENTSINCE'
          search_date = shift_date_value('SENTSINCE', search_key)
          factory = parse_mail_date(search_date) {|d, boundary| d > boundary }
        when 'SINCE'
          search_date = shift_date_value('SINCE', search_key)
          factory = parse_internal_date(search_date) {|d, boundary| d > boundary }
        when 'SMALLER'
          octet_size = shift_octet_size_value('SMALLER', search_key)
          factory = parse_mail_bytesize(octet_size) {|size, boundary| size < boundary }
        when 'SUBJECT'
          search_string = shift_string_value('SUBJECT', search_key)
          factory = parse_search_header('subject', search_string)
        when 'TEXT'
          search_string = shift_string_value('TEXT', search_key)
          factory = parse_text(search_string)
        when 'TO'
          search_string = shift_string_value('TO', search_key)
          factory = parse_search_header('to', search_string)
        when 'UID'
          mset_string = shift_string_value('UID', search_key)
          msg_set = @folder.parse_msg_set(mset_string, uid: true)
          factory = parse_uid(msg_set)
        when 'UNANSWERED'
          factory = parse_msg_flag_disabled('answered')
        when 'UNDELETED'
          factory = parse_msg_flag_disabled('deleted')
        when 'UNDRAFT'
          factory = parse_msg_flag_disabled('draft')
        when 'UNFLAGGED'
          factory = parse_msg_flag_disabled('flagged')
        when 'UNKEYWORD'
          search_string = shift_string_value('UNKEYWORD', search_key)
          factory = parse_unkeyword(search_string)
        when 'UNSEEN'
          factory = parse_msg_flag_disabled('seen')
        when String
          begin
            msg_set = @folder.parse_msg_set(op, uid: false)
            factory = parse_msg_set(msg_set)
          rescue MessageSetSyntaxError
            raise SyntaxError, "unknown search key: #{op}"
          end
        when Array
          case (op[0])
          when :group
            factory = parse_group(op[1..-1])
          else
            raise SyntaxError, "unknown search key: #{op}"
          end
        else
          raise SyntaxError, "unknown search key: #{op}"
        end

        factory
      end
      private :fetch_next_node

      def parse_cached(search_key)
        unless (search_key.empty?) then
          search_key = search_key.dup
          factory = fetch_next_node(search_key)
          _cond = factory.call(parse_cached(search_key))
        else
          _cond = end_of_cond
        end
      end
      private :parse_cached

      def parse(search_key)
        cond = parse_cached(search_key)
        proc{|msg|
          found = cond.call(msg)
          @mail_cache.clear
          found
        }
      end
    end

    class FetchParser
      module Utils
        def encode_list(array)
          '('.b << array.map{|v|
            case (v)
            when Symbol
              v.to_s
            when String
              Protocol.quote(v)
            when Integer
              v.to_s
            when NilClass
              'NIL'
            when Array
              encode_list(v)
            else
              raise "unknown value: #{v}"
            end
          }.join(' '.b) << ')'.b
        end
        module_function :encode_list

        def encode_header(name_value_pair_list)
          name_value_pair_list.map{|n, v| ''.b << n << ': ' << v << "\r\n" }.join('') << "\r\n"
        end
        module_function :encode_header

        def get_body_section(mail, index_list)
          if (index_list.empty?) then
            mail
          else
            i, *next_index_list = index_list
            unless (i > 0) then
              raise SyntaxError, "not a none-zero body section number: #{i}"
            end
            if (mail.multipart?) then
              get_body_section(mail.parts[i - 1], next_index_list)
            elsif (mail.message?) then
              get_body_section(mail.message, index_list)
            else
              if (i == 1) then
                if (next_index_list.empty?) then
                  mail
                else
                  nil
                end
              else
                nil
              end
            end
          end
        end
        module_function :get_body_section

        def get_body_content(mail, name, nest_mail: false)
          if (nest_mail) then
            if (mail.message?) then
              mail.message.__send__(name)
            else
              nil
            end
          else
            mail.__send__(name)
          end
        end
        module_function :get_body_content
      end
      include Utils

      def initialize(mail_store, folder)
        @mail_store = mail_store
        @folder = folder
        @charset = nil
        @mail_cache = Hash.new{|hash, uid|
          if (msg_txt = @mail_store.msg_text(@folder.mbox_id, uid)) then
            hash[uid] = RFC822::Message.new(msg_txt)
          end
        }
      end

      def get_mail(msg)
        @mail_cache[msg.uid] or raise "not found a mail: #{msg.uid}"
      end
      private :get_mail

      def make_array(value)
        if (value) then
          if (value.is_a? Array) then
            list = value
          else
            list = [ value ]
          end

          if (block_given?) then
            yield(list)
          else
            list
          end
        end
      end
      private :make_array

      def make_address_list(email_address)
        mailbox, host = email_address.split(/@/, 2)
        [ nil, nil, mailbox, host ]
      end
      private :make_address_list

      def expand_macro(cmd_list)
        func_list = cmd_list.map{|name| parse_cached(name) }
        proc{|msg|
          func_list.map{|f| f.call(msg) }.join(' '.b)
        }
      end
      private :expand_macro

      def get_header_field(mail, name, default=nil)
        if (field = mail[name]) then
          if (block_given?) then
            yield(field)
          else
            field
          end
        else
          default
        end
      end
      private :get_header_field

      def get_bodystructure_data(mail)
        if (mail.multipart?) then       # body_type_mpart
          mpart_data = []
          mpart_data.concat(mail.parts.map{|part_msg| get_bodystructure_data(part_msg) })
          mpart_data << mail.media_sub_type_upcase
        elsif (mail.text?) then         # body_type_text
          text_data = []

          # media_text
          text_data << mail.media_main_type_upcase
          text_data << mail.media_sub_type_upcase

          # body_fields
          text_data << mail.content_type_parameters.flatten
          text_data << mail.header['Content-Id']
          text_data << mail.header['Content-Description']
          text_data << mail.header.fetch_upcase('Content-Transfer-Encoding')
          text_data << mail.raw_source.bytesize

          # body_fld_lines
          text_data << mail.raw_source.each_line.count
        elsif (mail.message?) then      # body_type_msg
          msg_data = []

          # message_media
          msg_data << mail.media_main_type_upcase
          msg_data << mail.media_sub_type_upcase

          # body_fields
          msg_data << mail.content_type_parameters.flatten
          msg_data << mail.header['Content-Id']
          msg_data << mail.header['Content-Description']
          msg_data << mail.header.fetch_upcase('Content-Transfer-Encoding')
          msg_data << mail.raw_source.bytesize

          # envelope
          msg_data << get_envelope_data(mail.message)

          # body
          msg_data << get_bodystructure_data(mail.message)

          # body_fld_lines
          msg_data << mail.raw_source.each_line.count
        else                            # body_type_basic
          basic_data = []

          # media_basic
          basic_data << mail.media_main_type_upcase
          basic_data << mail.media_sub_type_upcase

          # body_fields
          basic_data << mail.content_type_parameters.flatten
          basic_data << mail.header['Content-Id']
          basic_data << mail.header['Content-Description']
          basic_data << mail.header.fetch_upcase('Content-Transfer-Encoding')
          basic_data << mail.raw_source.bytesize
        end
      end
      private :get_bodystructure_data

      def get_envelope_data(mail)
        env_data = []
        env_data << mail.header['Date']
        env_data << mail.header['Subject']
        env_data << mail.from
        env_data << mail.sender
        env_data << mail.reply_to
        env_data << mail.to
        env_data << mail.cc
        env_data << mail.bcc
        env_data << mail.header['In-Reply-To']
        env_data << mail.header['Message-Id']
      end
      private :get_envelope_data

      def parse_body(body, msg_att_name)
        enable_seen = true
        if (body.option) then
          case (body.option.upcase)
          when 'PEEK'
            enable_seen = false
          else
            raise SyntaxError, "unknown fetch body option: #{option}"
          end
        end
        if (@folder.read_only?) then
          enable_seen = false
        end

        if (enable_seen) then
          fetch_flags = parse_flags('FLAGS')
          fetch_flags_changed = proc{|msg|
            unless (@mail_store.msg_flag(@folder.mbox_id, msg.uid, 'seen')) then
              @mail_store.set_msg_flag(@folder.mbox_id, msg.uid, 'seen', true)
              fetch_flags.call(msg) + ' '.b
            else
              ''.b
            end
          }
        else
          fetch_flags_changed = proc{|msg|
            ''.b
          }
        end

        if (body.section_list.empty?) then
          section_text = nil
          section_index_list = []
        else
          if (body.section_list[0] =~ /\A (?<index>\d+(?:\.\d+)*) (?:\.(?<text>.+))? \z/x) then
            section_text = $~[:text]
            section_index_list = $~[:index].split(/\./).map{|i| i.to_i }
          else
            section_text = body.section_list[0]
            section_index_list = []
          end
        end

        is_root = section_index_list.empty?
        unless (section_text) then
          if (is_root) then
            fetch_body_content = proc{|mail|
              mail.raw_source
            }
          else
            fetch_body_content = proc{|mail|
              mail.body.raw_source
            }
          end
        else
          section_text = section_text.upcase
          case (section_text)
          when 'MIME'
            if (section_index_list.empty?) then
              raise SyntaxError, "need for section index at #{section_text}."
            else
              fetch_body_content = proc{|mail|
                if (header = get_body_content(mail, :header)) then
                  header.raw_source
                end
              }
            end
          when 'HEADER'
            fetch_body_content = proc{|mail|
              if (header = get_body_content(mail, :header, nest_mail: ! is_root)) then
                header.raw_source
              end
            }
          when 'HEADER.FIELDS', 'HEADER.FIELDS.NOT'
            if (body.section_list.length != 2) then
              raise SyntaxError, "need for argument of #{section_text}."
            end
            field_name_list = body.section_list[1]
            unless ((field_name_list.is_a? Array) && (field_name_list[0] == :group)) then
              raise SyntaxError, "invalid argument of #{section_text}: #{field_name_list}"
            end
            field_name_list = field_name_list[1..-1]
            case (section_text)
            when 'HEADER.FIELDS'
              fetch_body_content = proc{|mail|
                if (header = get_body_content(mail, :header, nest_mail: ! is_root)) then
                  field_name_set = field_name_list.map{|n| n.downcase }.to_set
                  name_value_pair_list = header.select{|n, v| field_name_set.include? n.downcase }
                  encode_header(name_value_pair_list)
                end
              }
            when 'HEADER.FIELDS.NOT'
              fetch_body_content = proc{|mail|
                if (header = get_body_content(mail, :header, nest_mail: ! is_root)) then
                  field_name_set = field_name_list.map{|n| n.downcase }.to_set
                  name_value_pair_list = header.reject{|n, v| field_name_set.include? n.downcase }
                  encode_header(name_value_pair_list)
                end
              }
            else
              raise 'internal error.'
            end
          when 'TEXT'
            fetch_body_content = proc{|mail|
              if (mail_body = get_body_content(mail, :body, nest_mail: ! is_root)) then
                mail_body.raw_source
              end
            }
          else
            raise SyntaxError, "unknown fetch body section text: #{section_text}"
          end
        end

        proc{|msg|
          res = ''.b
          res << fetch_flags_changed.call(msg)
          res << msg_att_name
          res << ' '.b

          mail = get_body_section(get_mail(msg), section_index_list)
          content = fetch_body_content.call(mail) if mail
          if (content) then
            if (body.partial_origin) then
              if (content.bytesize > body.partial_origin) then
                partial_content = content.byteslice((body.partial_origin)..-1)
                if (partial_content.bytesize > body.partial_size) then # because bignum byteslice is failed.
                  partial_content = partial_content.byteslice(0, body.partial_size)
                end
                res << Protocol.quote(partial_content)
              else
                res << 'NIL'.b
              end
            else
              res << Protocol.quote(content)
            end
          else
            res << 'NIL'.b
          end
        }
      end
      private :parse_body

      def parse_bodystructure(msg_att_name)
        proc{|msg|
          ''.b << msg_att_name << ' '.b << encode_list(get_bodystructure_data(get_mail(msg)))
        }
      end
      private :parse_bodystructure

      def parse_envelope(msg_att_name)
        proc{|msg|
          ''.b << msg_att_name << ' '.b << encode_list(get_envelope_data(get_mail(msg)))
        }
      end
      private :parse_envelope

      def parse_flags(msg_att_name)
        proc{|msg|
          flag_list = MailStore::MSG_FLAG_NAMES.find_all{|flag_name|
            @mail_store.msg_flag(@folder.mbox_id, msg.uid, flag_name)
          }.map{|flag_name|
            "\\".b << flag_name.capitalize
          }.join(' ')
          ''.b << msg_att_name << ' (' << flag_list << ')'
        }
      end
      private :parse_flags

      def parse_internaldate(msg_att_name)
        proc{|msg|
          ''.b << msg_att_name << @mail_store.msg_date(@folder.mbox_id, msg.uid).strftime(' "%d-%b-%Y %H:%M:%S %z"'.b)
        }
      end
      private :parse_internaldate

      def parse_rfc822_size(msg_att_name)
        proc{|msg|
          ''.b << msg_att_name << ' '.b << get_mail(msg).raw_source.bytesize.to_s
        }
      end
      private :parse_rfc822_size

      def parse_uid(msg_att_name)
        proc{|msg|
          ''.b << msg_att_name << ' '.b << msg.uid.to_s
        }
      end
      private :parse_uid

      def parse_group(fetch_attrs)
        group_fetch_list = fetch_attrs.map{|fetch_att| parse_cached(fetch_att) }
        proc{|msg|
          '('.b << group_fetch_list.map{|fetch| fetch.call(msg) }.join(' '.b) << ')'.b
        }
      end
      private :parse_group

      def parse_cached(fetch_att)
        fetch_att = fetch_att.upcase if (fetch_att.is_a? String)
        case (fetch_att)
        when 'ALL'
          fetch = expand_macro(%w[ FLAGS INTERNALDATE RFC822.SIZE ENVELOPE ])
        when 'BODY'
          fetch = parse_bodystructure(fetch_att)
        when 'BODYSTRUCTURE'
          fetch = parse_bodystructure(fetch_att)
        when 'ENVELOPE'
          fetch = parse_envelope(fetch_att)
        when 'FAST'
          fetch = expand_macro(%w[ FLAGS INTERNALDATE RFC822.SIZE ])
        when 'FLAGS'
          fetch = parse_flags(fetch_att)
        when 'FULL'
          fetch = expand_macro(%w[ FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODY ])
        when 'INTERNALDATE'
          fetch = parse_internaldate(fetch_att)
        when 'RFC822'
          fetch = parse_body(Protocol.body(section_list: []), fetch_att)
        when 'RFC822.HEADER'
          fetch = parse_body(Protocol.body(option: 'PEEK', section_list: %w[ HEADER ]), fetch_att)
        when 'RFC822.SIZE'
          fetch = parse_rfc822_size(fetch_att)
        when 'RFC822.TEXT'
          fetch = parse_body(Protocol.body(section_list: %w[ TEXT ]), fetch_att)
        when 'UID'
          fetch = parse_uid(fetch_att)
        when Array
          case (fetch_att[0])
          when :group
            fetch = parse_group(fetch_att[1..-1])
          when :body
            body = fetch_att[1]
            fetch = parse_body(body, body.msg_att_name)
          else
            raise SyntaxError, "unknown fetch attribute: #{fetch_att[0]}"
          end
        else
          raise SyntaxError, "unknown fetch attribute: #{fetch_att}"
        end

        fetch
      end
      private :parse_cached

      def parse(fetch_att)
        fetch = parse_cached(fetch_att)
        proc{|msg|
          res = fetch.call(msg)
          @mail_cache.clear
          res
        }
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
