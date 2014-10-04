# -*- coding: utf-8 -*-

require 'net/imap'
require 'set'
require 'time'

module RIMS
  module Protocol
    def quote(s)
      qs = ''.encode(s.encoding)
      case (s)
      when /"/, /\n/
        qs << '{' << s.bytesize.to_s << "}\r\n" << s
      else
        qs << '"' << s << '"'
      end
    end
    module_function :quote

    def compile_wildcard(pattern)
      src = '\A'
      src << pattern.gsub(/.*?[*%]/) {|s| Regexp.quote(s[0..-2]) + '.*' }
      src << Regexp.quote($') if $'
      src << '\z'
      Regexp.compile(src)
    end
    module_function :compile_wildcard

    def io_data_log(str)
      s = '<'
      s << str.encoding.to_s
      if (str.ascii_only?) then
        s << ':ascii_only'
      end
      s << '> ' << str.inspect
    end
    module_function :io_data_log

    def encode_base64(plain_txt)
      [ plain_txt ].pack('m').each_line.map{|line| line.strip }.join('')
    end
    module_function :encode_base64

    def decode_base64(base64_txt)
      base64_txt.unpack('m')[0]
    end
    module_function :decode_base64

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

    def body(symbol: nil, option: nil, section: nil, section_list: nil, partial_origin: nil, partial_size: nil)
      body = FetchBody.new(symbol, option, section, section_list, partial_origin, partial_size)
    end
    module_function :body

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
      def initialize(auth, input, output, logger)
        @auth = auth
        @input = input
        @output = output
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
          @output.write("+ #{server_challenge_data_base64}\r\n")
        else
          @logger.debug("authenticate command: server challenge data is nil.") if @logger.debug?
          @output.write("+ \r\n")
        end

        if (client_response_data_base64 = @input.gets) then
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
          @logger.debug("authenticate command: inline client response data: #{inline_client_response_data_base64}") if @logger.debug?
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
          cond = factory.call(parse_cached(search_key))
        else
          cond = end_of_cond
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
          mpart_data << mail.media_sub_type
        elsif (mail.text?) then         # body_type_text
          text_data = []

          # media_text
          text_data << mail.media_main_type
          text_data << mail.media_sub_type

          # body_fields
          text_data << mail.content_type_parameters.flatten
          text_data << mail.header['Content-Id']
          text_data << mail.header['Content-Description']
          text_data << mail.header['Content-Transfer-Encoding']
          text_data << mail.raw_source.bytesize

          # body_fld_lines
          text_data << mail.raw_source.each_line.count
        elsif (mail.message?) then      # body_type_msg
          msg_data = []

          # message_media
          msg_data << mail.media_main_type
          msg_data << mail.media_sub_type

          # body_fields
          msg_data << mail.content_type_parameters.flatten
          msg_data << mail.header['Content-Id']
          msg_data << mail.header['Content-Description']
          msg_data << mail.header['Content-Transfer-Encoding']
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
          basic_data << mail.media_main_type
          basic_data << mail.media_sub_type

          # body_fields
          basic_data << mail.content_type_parameters.flatten
          basic_data << mail.header['Content-Id']
          basic_data << mail.header['Content-Description']
          basic_data << mail.header['Content-Transfer-Encoding']
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
          if (body.section_list[0] =~ /\A(?<index>\d+(?:\.\d+)*)(?:\.(?<text>.+))?\z/) then
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

      def parse_bodystructure(name)
        proc{|msg|
          ''.b << name << ' '.b << encode_list(get_bodystructure_data(get_mail(msg)))
        }
      end
      private :parse_bodystructure

      def parse_envelope(name)
        proc{|msg|
          ''.b << name << ' '.b << encode_list(get_envelope_data(get_mail(msg)))
        }
      end
      private :parse_envelope

      def parse_flags(name)
        proc{|msg|
          flag_list = MailStore::MSG_FLAG_NAMES.find_all{|name|
            @mail_store.msg_flag(@folder.mbox_id, msg.uid, name)
          }.map{|name|
            "\\".b << name.capitalize
          }.join(' ')
          ''.b << name << ' (' << flag_list << ')'
        }
      end
      private :parse_flags

      def parse_internaldate(name)
        proc{|msg|
          ''.b << name << @mail_store.msg_date(@folder.mbox_id, msg.uid).strftime(' "%d-%b-%Y %H:%M:%S %z"'.b)
        }
      end
      private :parse_internaldate

      def parse_rfc822_size(name)
        proc{|msg|
          ''.b << name << ' '.b << get_mail(msg).raw_source.bytesize.to_s
        }
      end
      private :parse_rfc822_size

      def parse_uid(name)
        proc{|msg|
          ''.b << name << ' '.b << msg.uid.to_s
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

    class Decoder
      def self.new_decoder(*args, **opts)
        InitialDecoder.new(*args, **opts)
      end

      def self.repl(decoder, input, output, logger)
        response_write = proc{|res|
          begin
            last_line = nil
            for data in res
              logger.debug("response data: #{Protocol.io_data_log(data)}") if logger.debug?
              output << data
              last_line = data
            end
            output.flush
            logger.info("server response: #{last_line.strip}")
          rescue
            logger.error('response write error.')
            logger.error($!)
            raise
          end
        }

        response_write.call(decoder.ok_greeting)

        request_reader = Protocol::RequestReader.new(input, output, logger)
        loop do
          begin
            atom_list = request_reader.read_command
          rescue
            logger.error('invalid client command.')
            logger.error($!)
            response_write.call([ "* BAD client command syntax error\r\n" ])
            next
          end

          break unless atom_list

          tag, command, *opt_args = atom_list
          logger.info("client command: #{tag} #{command}")
          logger.debug("client command parameter: #{opt_args.inspect}") if logger.debug?

          begin
            case (command.upcase)
            when 'CAPABILITY'
              res = decoder.capability(tag, *opt_args)
            when 'NOOP'
              res = decoder.noop(tag, *opt_args)
            when 'LOGOUT'
              res = decoder.logout(tag, *opt_args)
            when 'AUTHENTICATE'
              res, decoder = decoder.authenticate(input, output, tag, *opt_args)
            when 'LOGIN'
              res, decoder = decoder.login(tag, *opt_args)
            when 'SELECT'
              res = decoder.select(tag, *opt_args)
            when 'EXAMINE'
              res = decoder.examine(tag, *opt_args)
            when 'CREATE'
              res = decoder.create(tag, *opt_args)
            when 'DELETE'
              res = decoder.delete(tag, *opt_args)
            when 'RENAME'
              res = decoder.rename(tag, *opt_args)
            when 'SUBSCRIBE'
              res = decoder.subscribe(tag, *opt_args)
            when 'UNSUBSCRIBE'
              res = decoder.unsubscribe(tag, *opt_args)
            when 'LIST'
              res = decoder.list(tag, *opt_args)
            when 'LSUB'
              res = decoder.lsub(tag, *opt_args)
            when 'STATUS'
              res = decoder.status(tag, *opt_args)
            when 'APPEND'
              res = decoder.append(tag, *opt_args)
            when 'CHECK'
              res = decoder.check(tag, *opt_args)
            when 'CLOSE'
              res = decoder.close(tag, *opt_args)
            when 'EXPUNGE'
              res = decoder.expunge(tag, *opt_args)
            when 'SEARCH'
              res = decoder.search(tag, *opt_args)
            when 'FETCH'
              res = decoder.fetch(tag, *opt_args)
            when 'STORE'
              res = decoder.store(tag, *opt_args)
            when 'COPY'
              res = decoder.copy(tag, *opt_args)
            when 'UID'
              unless (opt_args.empty?) then
                uid_command, *uid_args = opt_args
                logger.info("uid command: #{uid_command}")
                logger.debug("uid parameter: #{uid_args}") if logger.debug?
                case (uid_command.upcase)
                when 'SEARCH'
                  res = decoder.search(tag, *uid_args, uid: true)
                when 'FETCH'
                  res = decoder.fetch(tag, *uid_args, uid: true)
                when 'STORE'
                  res = decoder.store(tag, *uid_args, uid: true)
                when 'COPY'
                  res = decoder.copy(tag, *uid_args, uid: true)
                else
                  logger.error("unknown uid command: #{uid_command}")
                  res = [ "#{tag} BAD unknown uid command\r\n" ]
                end
              else
                logger.error('empty uid parameter.')
                res = [ "#{tag} BAD empty uid parameter\r\n" ]
              end
            else
              logger.error("unknown command: #{command}")
              res = [ "#{tag} BAD unknown command\r\n" ]
            end
          rescue ArgumentError
            logger.error('invalid command parameter.')
            logger.error($!)
            res = [ "#{tag} BAD invalid command parameter\r\n" ]
          rescue
            logger.error('internal server error.')
            logger.error($!)
            res = [ "#{tag} BAD internal server error\r\n" ]
          end

          response_write.call(res)

          if (command.upcase == 'LOGOUT') then
            break
          end
        end

        nil
      end

      def initialize(auth, logger)
        @auth = auth
        @logger = logger
      end

      def protect_error(tag)
        begin
          yield
        rescue SyntaxError
          @logger.error('client command syntax error.')
          @logger.error($!)
          [ "#{tag} BAD client command syntax error\r\n" ]
        rescue
          @logger.error('internal server error.')
          @logger.error($!)
          [ "#{tag} BAD internal server error\r\n" ]
        end
      end
      private :protect_error

      def response_stream(tag)
        Enumerator.new{|res|
          begin
            yield(res)
          rescue SyntaxError
            @logger.error('client command syntax error.')
            @logger.error($!)
            res << "#{tag} BAD client command syntax error\r\n"
          rescue
            @logger.error('internal server error.')
            @logger.error($!)
            res << "#{tag} BAD internal server error\r\n"
          end
        }
      end
      private :response_stream

      def fetch_mail_store_holder_and_on_demand_recovery(username)
        unique_user_id = Authentication.unique_user_id(username)
        @logger.debug("unique user ID: #{username} -> #{unique_user_id}") if @logger.debug?
        mail_store_holder = @mail_store_pool.get(unique_user_id)
        if (mail_store_holder.mail_store.abort_transaction?) then
          @logger.warn("user data recovery start: #{username}")
          mail_store_holder.mail_store.recovery_data(logger: @logger).sync
          yield("* OK [ALERT] recovery user data.\r\n")
          @logger.warn("user data recovery end: #{username}")
        end
        mail_store_holder
      end
      private :fetch_mail_store_holder_and_on_demand_recovery

      def ok_greeting
        [ "* OK RIMS v#{VERSION} IMAP4rev1 service ready.\r\n" ]
      end

      def capability(tag)
        capability_list = %w[ IMAP4rev1 ] + @auth.capability.map{|auth_capability| "AUTH=#{auth_capability}" }

        res = []
        res << "* CAPABILITY #{capability_list.join(' ')}\r\n"
        res << "#{tag} OK CAPABILITY completed\r\n"
      end
    end

    class InitialDecoder < Decoder
      def initialize(mail_store_pool, auth, logger, mail_delivery_user: '#postman')
        super(auth, logger)
        @mail_store_pool = mail_store_pool
        @folder = nil
        @auth = auth
        @mail_delivery_user = mail_delivery_user
      end

      def auth?
        false
      end

      def selected?
        false
      end

      def cleanup
        nil
      end

      def not_authenticated_response(tag)
        [ "#{tag} NO not authenticated\r\n" ]
      end
      private :not_authenticated_response

      def noop(tag)
        protect_error(tag) {
          [ "#{tag} OK NOOP completed\r\n" ]
        }
      end

      def logout(tag)
        protect_error(tag) {
          cleanup
          res = []
          res << "* BYE server logout\r\n"
          res << "#{tag} OK LOGOUT completed\r\n"
        }
      end

      def accept_authentication(username)
        cleanup

        case (username)
        when @mail_delivery_user
          @logger.info("mail delivery user: #{username}")
          MailDeliveryDecoder.new(@mail_store_pool, @auth, @logger)
        else
          mail_store_holder = fetch_mail_store_holder_and_on_demand_recovery(username) {|msg| yield(msg) }
          UserMailboxDecoder.new(self, mail_store_holder, @auth, @logger)
        end
      end
      private :accept_authentication

      def authenticate(client_response_input_stream, server_challenge_output_stream,
                       tag, auth_type, inline_client_response_data_base64=nil)
        protect_error(tag) {
          res = []
          next_decoder = self

          auth_reader = AuthenticationReader.new(@auth, client_response_input_stream, server_challenge_output_stream, @logger)
          if (username = auth_reader.authenticate_client(auth_type, inline_client_response_data_base64)) then
            if (username != :*) then
              @logger.info("authentication OK: #{username}")
              next_decoder = accept_authentication(username) {|msg| res << msg }
              res << "#{tag} OK AUTHENTICATE #{auth_type} success\r\n"
            else
              @logger.info('bad authentication.')
              res << "#{tag} BAD AUTHENTICATE failed\r\n"
            end
          else
            res << "#{tag} NO authentication failed\r\n"
          end

          return res, next_decoder
        }
      end

      def login(tag, username, password)
        protect_error(tag) {
          res = []
          next_decoder = self

          if (@auth.authenticate_login(username, password)) then
            @logger.info("login authentication OK: #{username}")
            next_decoder = accept_authentication(username) {|msg| res << msg }
            res << "#{tag} OK LOGIN completed\r\n"
          else
            res << "#{tag} NO failed to login\r\n"
          end

          return res, next_decoder
        }
      end

      def select(tag, mbox_name)
        not_authenticated_response(tag)
      end

      def examine(tag, mbox_name)
        not_authenticated_response(tag)
      end

      def create(tag, mbox_name)
        not_authenticated_response(tag)
      end

      def delete(tag, mbox_name)
        not_authenticated_response(tag)
      end

      def rename(tag, src_name, dst_name)
        not_authenticated_response(tag)
      end

      def subscribe(tag, mbox_name)
        not_authenticated_response(tag)
      end

      def unsubscribe(tag, mbox_name)
        not_authenticated_response(tag)
      end

      def list(tag, ref_name, mbox_name)
        not_authenticated_response(tag)
      end

      def lsub(tag, ref_name, mbox_name)
        not_authenticated_response(tag)
      end

      def status(tag, mbox_name, data_item_group)
        not_authenticated_response(tag)
      end

      def append(tag, mbox_name, *opt_args, msg_text)
        not_authenticated_response(tag)
      end

      def check(tag)
        not_authenticated_response(tag)
      end

      def close(tag)
        not_authenticated_response(tag)
      end

      def expunge(tag)
        not_authenticated_response(tag)
      end

      def search(tag, *cond_args, uid: false)
        not_authenticated_response(tag)
      end

      def fetch(tag, msg_set, data_item_group, uid: false)
        not_authenticated_response(tag)
      end

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        not_authenticated_response(tag)
      end

      def copy(tag, msg_set, mbox_name, uid: false)
        not_authenticated_response(tag)
      end
    end

    class AuthenticatedDecoder < Decoder
      def authenticate(client_response_input_stream, server_challenge_output_stream,
                       tag, auth_type, inline_client_response_data_base64=nil)
        protect_error(tag) {
          return [ "#{tag} NO duplicated authentication\r\n" ], self
        }
      end

      def login(tag, username, password)
        protect_error(tag) {
          return [ "#{tag} NO duplicated login\r\n" ], self
        }
      end
    end

    class UserMailboxDecoder < AuthenticatedDecoder
      def initialize(parent_decoder, mail_store_holder, auth, logger)
        super(auth, logger)
        @parent_decoder = parent_decoder
        @mail_store_holder = mail_store_holder
        @folder = nil
      end

      def auth?
        @mail_store_holder != nil
      end

      def selected?
        @folder != nil
      end

      def cleanup
        unless (@mail_store_holder.nil?) then
          @mail_store_holder.return_pool
          @mail_store_holder = nil
        end

        unless (@parent_decoder.nil?) then
          @parent_decoder.cleanup
          @parent_decoder = nil
        end

        nil
      end

      def get_mail_store
        @mail_store_holder.mail_store
      end
      private :get_mail_store

      def protect_auth(tag, lock: true)
        protect_error(tag) {
          if (auth?) then
            if (lock) then
              @mail_store_holder.user_lock.synchronize{ yield }
            else
              yield
            end
          else
            [ "#{tag} NO not authenticated\r\n" ]
          end
        }
      end
      private :protect_auth

      def protect_select(tag, lock: true)
        protect_auth(tag, lock: lock) {
          if (selected?) then
            yield
          else
            [ "#{tag} NO not selected\r\n" ]
          end
        }
      end
      private :protect_select

      def lock_folder
        @mail_store_holder.user_lock.synchronize{
          unless (@folder) then
            raise 'no open folder.'
          end

          unless (get_mail_store.mbox_name(@folder.mbox_id)) then
            raise "deleted folder: #{id}"
          end

          yield
        }
      end
      private :lock_folder

      def noop(tag)
        protect_error(tag) {
          res = []
          if (auth? && selected?) then
            lock_folder{
              @folder.reload if @folder.updated?
              res << "* #{get_mail_store.mbox_msg_num(@folder.mbox_id)} EXISTS\r\n"
              res << "* #{get_mail_store.mbox_flag_num(@folder.mbox_id, 'recent')} RECENTS\r\n"
            }
          end
          res << "#{tag} OK NOOP completed\r\n"
        }
      end

      def logout(tag)
        protect_error(tag) {
          if (auth? && selected?) then
            lock_folder{
              @folder.reload if @folder.updated?
              @folder.close
              @folder = nil
            }
          end
          cleanup
          res = []
          res << "* BYE server logout\r\n"
          res << "#{tag} OK LOGOUT completed\r\n"
        }
      end

      def folder_open_msgs
        all_msgs = get_mail_store.mbox_msg_num(@folder.mbox_id)
        recent_msgs = get_mail_store.mbox_flag_num(@folder.mbox_id, 'recent')
        unseen_msgs = all_msgs - get_mail_store.mbox_flag_num(@folder.mbox_id, 'seen')
        yield("* #{all_msgs} EXISTS\r\n")
        yield("* #{recent_msgs} RECENT\r\n")
        yield("* OK [UNSEEN #{unseen_msgs}]\r\n")
        yield("* OK [UIDVALIDITY #{@folder.mbox_id}]\r\n")
        yield("* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n")
        nil
      end
      private :folder_open_msgs

      def select(tag, mbox_name)
        protect_auth(tag) {
          res = []
          @folder = nil
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (id = get_mail_store.mbox_id(mbox_name_utf8)) then
            @folder = get_mail_store.select_mbox(id)
            folder_open_msgs do |msg|
              res << msg
            end
            res << "#{tag} OK [READ-WRITE] SELECT completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
        }
      end

      def examine(tag, mbox_name)
        protect_auth(tag) {
          res = []
          @folder = nil
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (id = get_mail_store.mbox_id(mbox_name_utf8)) then
            @folder = get_mail_store.examine_mbox(id)
            folder_open_msgs do |msg|
              res << msg
            end
            res << "#{tag} OK [READ-ONLY] EXAMINE completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
        }
      end

      def create(tag, mbox_name)
        protect_auth(tag) {
          res = []
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (get_mail_store.mbox_id(mbox_name_utf8)) then
            res << "#{tag} NO duplicated mailbox\r\n"
          else
            get_mail_store.add_mbox(mbox_name_utf8)
            res << "#{tag} OK CREATE completed\r\n"
          end
        }
      end

      def delete(tag, mbox_name)
        protect_auth(tag) {
          res = []
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (id = get_mail_store.mbox_id(mbox_name_utf8)) then
            if (id != get_mail_store.mbox_id('INBOX')) then
              get_mail_store.del_mbox(id)
              res << "#{tag} OK DELETE completed\r\n"
            else
              res << "#{tag} NO not delete inbox\r\n"
            end
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
        }
      end

      def rename(tag, src_name, dst_name)
        protect_auth(tag) {
          src_name_utf8 = Net::IMAP.decode_utf7(src_name)
          dst_name_utf8 = Net::IMAP.decode_utf7(dst_name)
          unless (id = get_mail_store.mbox_id(src_name_utf8)) then
            return [ "#{tag} NO not found a mailbox\r\n" ]
          end
          if (id == get_mail_store.mbox_id('INBOX')) then
            return [ "#{tag} NO not rename inbox\r\n"]
          end
          if (get_mail_store.mbox_id(dst_name_utf8)) then
            return [ "#{tag} NO duplicated mailbox\r\n" ]
          end
          get_mail_store.rename_mbox(id, dst_name_utf8)
          [ "#{tag} OK RENAME completed\r\n" ]
        }
      end

      def subscribe(tag, mbox_name)
        protect_auth(tag) {
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (mbox_id = get_mail_store.mbox_id(mbox_name_utf8)) then
            [ "#{tag} OK SUBSCRIBE completed\r\n" ]
          else
            [ "#{tag} NO not found a mailbox\r\n" ]
          end
        }
      end

      def unsubscribe(tag, mbox_name)
        protect_auth(tag) {
          if (mbox_id = get_mail_store.mbox_id(mbox_name)) then
            [ "#{tag} NO not implemented subscribe/unsbscribe command\r\n" ]
          else
            [ "#{tag} NO not found a mailbox\r\n" ]
          end
        }
      end

      def list_mbox(ref_name, mbox_name)
        ref_name_utf8 = Net::IMAP.decode_utf7(ref_name)
        mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)

        mbox_filter = Protocol.compile_wildcard(mbox_name_utf8)
        mbox_list = get_mail_store.each_mbox_id.map{|id| [ id, get_mail_store.mbox_name(id) ] }
        mbox_list.keep_if{|id, name| name.start_with? ref_name_utf8 }
        mbox_list.keep_if{|id, name| name[(ref_name_utf8.length)..-1] =~ mbox_filter }

        for id, name_utf8 in mbox_list
          name = Net::IMAP.encode_utf7(name_utf8)
          attrs = '\Noinferiors'
          if (get_mail_store.mbox_flag_num(id, 'recent') > 0) then
            attrs << ' \Marked'
          else
            attrs << ' \Unmarked'
          end
          yield("(#{attrs}) NIL #{Protocol.quote(name)}")
        end

        nil
      end
      private :list_mbox

      def list(tag, ref_name, mbox_name)
        protect_auth(tag) {
          res = []
          if (mbox_name.empty?) then
            res << "* LIST (\\Noselect) NIL \"\"\r\n"
          else
            list_mbox(ref_name, mbox_name) do |mbox_entry|
              res << "* LIST #{mbox_entry}\r\n"
            end
          end
          res << "#{tag} OK LIST completed\r\n"
        }
      end

      def lsub(tag, ref_name, mbox_name)
        protect_auth(tag) {
          res = []
          if (mbox_name.empty?) then
            res << "* LSUB (\\Noselect) NIL \"\"\r\n"
          else
            list_mbox(ref_name, mbox_name) do |mbox_entry|
              res << "* LSUB #{mbox_entry}\r\n"
            end
          end
          res << "#{tag} OK LSUB completed\r\n"
        }
      end

      def status(tag, mbox_name, data_item_group)
        protect_auth(tag) {
          res = []
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (id = get_mail_store.mbox_id(mbox_name_utf8)) then
            unless ((data_item_group.is_a? Array) && (data_item_group[0] == :group)) then
              raise SyntaxError, 'second arugment is not a group list.'
            end

            values = []
            for item in data_item_group[1..-1]
              case (item.upcase)
              when 'MESSAGES'
                values << 'MESSAGES' << get_mail_store.mbox_msg_num(id)
              when 'RECENT'
                values << 'RECENT' << get_mail_store.mbox_flag_num(id, 'recent')
              when 'UIDNEXT'
                values << 'UIDNEXT' << get_mail_store.uid(id)
              when 'UIDVALIDITY'
                values << 'UIDVALIDITY' << id
              when 'UNSEEN'
                unseen_flags = get_mail_store.mbox_msg_num(id) - get_mail_store.mbox_flag_num(id, 'seen')
                values << 'UNSEEN' << unseen_flags
              else
                raise SyntaxError, "unknown status data: #{item}"
              end
            end

            res << "* STATUS #{Protocol.quote(mbox_name)} (#{values.join(' ')})\r\n"
            res << "#{tag} OK STATUS completed\r\n"
          else
            res << "#{tag} NO not found a mailbox\r\n"
          end
        }
      end

      def append(tag, mbox_name, *opt_args, msg_text)
        protect_auth(tag) {
          res = []
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          if (mbox_id = get_mail_store.mbox_id(mbox_name_utf8)) then
            msg_flags = []
            msg_date = Time.now

            if ((! opt_args.empty?) && (opt_args[0].is_a? Array)) then
              opt_flags = opt_args.shift
              if (opt_flags[0] != :group) then
                raise SyntaxError, 'bad flag list.'
              end
              for flag_atom in opt_flags[1..-1]
                case (flag_atom.upcase)
                when '\ANSWERED'
                  msg_flags << 'answered'
                when '\FLAGGED'
                  msg_flags << 'flagged'
                when '\DELETED'
                  msg_flags << 'deleted'
                when '\SEEN'
                  msg_flags << 'seen'
                when '\DRAFT'
                  msg_flags << 'draft'
                else
                  raise SyntaxError, "invalid flag: #{flag_atom}"
                end
              end
            end

            if ((! opt_args.empty?) && (opt_args[0].is_a? String)) then
              begin
                msg_date = Time.parse(opt_args.shift)
              rescue ArgumentError
                raise SyntaxError, $!.message
              end
            end

            unless (opt_args.empty?) then
              raise SyntaxError, 'unknown option.'
            end

            uid = get_mail_store.add_msg(mbox_id, msg_text, msg_date)
            for flag_name in msg_flags
              get_mail_store.set_msg_flag(mbox_id, uid, flag_name, true)
            end

            res << "#{tag} OK APPEND completed\r\n"
          else
            res << "#{tag} NO [TRYCREATE] not found a mailbox\r\n"
          end
        }
      end

      def check(tag)
        protect_select(tag) {
          get_mail_store.sync
          [ "#{tag} OK CHECK completed\r\n" ]
        }
      end

      def close(tag)
        protect_select(tag) {
          get_mail_store.sync
          if (@folder) then
            @folder.reload if @folder.updated?
            @folder.close
            @folder = nil
          end
          [ "#{tag} OK CLOSE completed\r\n" ]
        }
      end

      def expunge(tag)
        protect_select(tag) {
          unless (@folder.read_only?) then
            @folder.reload if @folder.updated?

            msg_num_list = []
            @folder.expunge_mbox do |msg_num|
              msg_num_list << msg_num
            end

            response_stream(tag) {|res|
              for msg_num in msg_num_list
                res << "* #{msg_num} EXPUNGE\r\n"
              end
              res << "#{tag} OK EXPUNGE completed\r\n"
            }
          else
            [ "#{tag} NO cannot expunge in read-only mode\r\n" ]
          end
        }
      end

      def search(tag, *cond_args, uid: false)
        protect_select(tag, lock: false) {
          cond = nil

          lock_folder{
            @folder.reload if @folder.updated?
            parser = Protocol::SearchParser.new(get_mail_store, @folder)
            if (cond_args[0].upcase == 'CHARSET') then
              cond_args.shift
              charset_string = cond_args.shift or raise SyntaxError, 'need for a charset string of CHARSET'
              charset_string.is_a? String or raise SyntaxError, "CHARSET charset string expected as <String> but was <#{charset_string.class}>."
              parser.charset = charset_string
            end
            cond = parser.parse(cond_args)
          }

          response_stream(tag) {|res|
            res << '* SEARCH'
            for msg in @folder.msg_list
              begin
                if (lock_folder{ cond.call(msg) }) then
                  if (uid) then
                    res << " #{msg.uid}"
                  else
                    res << " #{msg.num}"
                  end
                end
              rescue SystemCallError
                raise
              rescue
                @logger.warn("failed to search message: uidvalidity(#{@folder.mbox_id}) uid(#{msg.uid})")
                @logger.warn($!)
              end
            end
            res << "\r\n"
            res << "#{tag} OK SEARCH completed\r\n"
          }
        }
      end

      def fetch(tag, msg_set, data_item_group, uid: false)
        protect_select(tag, lock: false) {
          fetch = nil
          msg_list = nil

          lock_folder{
            @folder.reload if @folder.updated?

            msg_set = @folder.parse_msg_set(msg_set, uid: uid)
            msg_list = @folder.msg_list.find_all{|msg|
              if (uid) then
                msg_set.include? msg.uid
              else
                msg_set.include? msg.num
              end
            }

            unless ((data_item_group.is_a? Array) && data_item_group[0] == :group) then
              data_item_group = [ :group, data_item_group ]
            end
            if (uid) then
              unless (data_item_group.find{|i| (i.is_a? String) && (i.upcase == 'UID') }) then
                data_item_group = [ :group, 'UID' ] + data_item_group[1..-1]
              end
            end

            parser = Protocol::FetchParser.new(get_mail_store, @folder)
            fetch = parser.parse(data_item_group)
          }

          response_stream(tag) {|res|
            for msg in msg_list
              begin
                res << ('* '.b << msg.num.to_s.b << ' FETCH '.b << lock_folder{ fetch.call(msg) } << "\r\n".b)
              rescue SystemCallError
                raise
              rescue
                @logger.warn("failed to fetch message: uidvalidity(#{@folder.mbox_id}) uid(#{msg.uid})")
                @logger.warn($!)
              end
            end
            res << "#{tag} OK FETCH completed\r\n"
          }
        }
      end

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        protect_select(tag, lock: false) {
          is_silent = nil
          msg_list = nil

          lock_folder{
            return [ "#{tag} NO cannot store in read-only mode\r\n" ] if @folder.read_only?
            @folder.reload if @folder.updated?

            msg_set = @folder.parse_msg_set(msg_set, uid: uid)
            name, option = data_item_name.split(/\./, 2)

            case (name.upcase)
            when 'FLAGS'
              action = :flags_replace
            when '+FLAGS'
              action = :flags_add
            when '-FLAGS'
              action = :flags_del
            else
              raise SyntaxError, "unknown store action: #{name}"
            end

            case (option && option.upcase)
            when 'SILENT'
              is_silent = true
            when nil
              is_silent = false
            else
              raise SyntaxError, "unknown store option: #{option.inspect}"
            end

            if ((data_item_value.is_a? Array) && data_item_value[0] == :group) then
              flag_list = []
              for flag_atom in data_item_value[1..-1]
                case (flag_atom.upcase)
                when '\ANSWERED'
                  flag_list << 'answered'
                when '\FLAGGED'
                  flag_list << 'flagged'
                when '\DELETED'
                  flag_list << 'deleted'
                when '\SEEN'
                  flag_list << 'seen'
                when '\DRAFT'
                  flag_list << 'draft'
                else
                  raise SyntaxError, "invalid flag: #{flag_atom}"
                end
              end
              rest_flag_list = (MailStore::MSG_FLAG_NAMES - %w[ recent ]) - flag_list
            else
              raise SyntaxError, 'third arugment is not a group list.'
            end

            msg_list = @folder.msg_list.find_all{|msg|
              if (uid) then
                msg_set.include? msg.uid
              else
                msg_set.include? msg.num
              end
            }

            for msg in msg_list
              case (action)
              when :flags_replace
                for name in flag_list
                  get_mail_store.set_msg_flag(@folder.mbox_id, msg.uid, name, true)
                end
                for name in rest_flag_list
                  get_mail_store.set_msg_flag(@folder.mbox_id, msg.uid, name, false)
                end
              when :flags_add
                for name in flag_list
                  get_mail_store.set_msg_flag(@folder.mbox_id, msg.uid, name, true)
                end
              when :flags_del
                for name in flag_list
                  get_mail_store.set_msg_flag(@folder.mbox_id, msg.uid, name, false)
                end
              else
                raise "internal error: unknown action: #{action}"
              end
            end
          }

          if (is_silent) then
            [ "#{tag} OK STORE completed\r\n" ]
          else
            response_stream(tag) {|res|
              for msg in msg_list
                flag_atom_list = nil

                lock_folder{
                  if (get_mail_store.msg_exist? @folder.mbox_id, msg.uid) then
                    flag_atom_list = []
                    for name in MailStore::MSG_FLAG_NAMES
                      if (get_mail_store.msg_flag(@folder.mbox_id, msg.uid, name)) then
                        flag_atom_list << "\\#{name.capitalize}"
                      end
                    end
                  end
                }

                if (flag_atom_list) then
                  res << "* #{msg.num} FETCH FLAGS (#{flag_atom_list.join(' ')})\r\n"
                else
                  @logger.warn("not found a message and skipped: uidvalidity(#{@folder.mbox_id}) uid(#{msg.uid})")
                end
              end
              res << "#{tag} OK STORE completed\r\n"
            }
          end
        }
      end

      def copy(tag, msg_set, mbox_name, uid: false)
        protect_select(tag) {
          res = []
          mbox_name_utf8 = Net::IMAP.decode_utf7(mbox_name)
          msg_set = @folder.parse_msg_set(msg_set, uid: uid)

          if (mbox_id = get_mail_store.mbox_id(mbox_name_utf8)) then
            msg_list = @folder.msg_list.find_all{|msg|
              if (uid) then
                msg_set.include? msg.uid
              else
                msg_set.include? msg.num
              end
            }

            for msg in msg_list
              get_mail_store.copy_msg(msg.uid, @folder.mbox_id, mbox_id)
            end

            res << "#{tag} OK COPY completed\r\n"
          else
            res << "#{tag} NO [TRYCREATE] not found a mailbox\r\n"
          end
        }
      end
    end

    class MailDeliveryDecoder < AuthenticatedDecoder
      def initialize(mail_store_pool, auth, logger)
        super(auth, logger)
        @mail_store_pool = mail_store_pool
        @auth = auth
      end

      def auth?
        @mail_store_pool != nil
      end

      def selected?
        false
      end

      def cleanup
        @mail_store_pool = nil unless @mail_store_pool.nil?
        @auth = nil unless @auth.nil?
        nil
      end

      def self.decode_user_mailbox(encoded_mbox_name)
        encode_type, base64_username, mbox_name = encoded_mbox_name.split(' ', 3)
        if (encode_type != 'b64user-mbox') then
          raise SyntaxError, "unknown mailbox encode type: #{encode_type}"
        end
        return Protocol.decode_base64(base64_username), mbox_name
      end

      def logout(tag)
        protect_error(tag) {
          cleanup
          res = []
          res << "* BYE server logout\r\n"
          res << "#{tag} OK LOGOUT completed\r\n"
        }
      end

      def capability(tag)
        super.map{|line|
          if (line.start_with? '* CAPABILITY ') then
            line.strip + " X-RIMS-MAIL-DELIVERY-USER\r\n"
          else
            line
          end
        }
      end

      def not_allowed_command_response(tag)
        [ "#{tag} NO not allowed command on mail delivery user\r\n" ]
      end
      private :not_allowed_command_response

      def select(tag, mbox_name)
        not_allowed_command_response(tag)
      end

      def examine(tag, mbox_name)
        not_allowed_command_response(tag)
      end

      def create(tag, mbox_name)
        not_allowed_command_response(tag)
      end

      def delete(tag, mbox_name)
        not_allowed_command_response(tag)
      end

      def rename(tag, src_name, dst_name)
        not_allowed_command_response(tag)
      end

      def subscribe(tag, mbox_name)
        not_allowed_command_response(tag)
      end

      def unsubscribe(tag, mbox_name)
        not_allowed_command_response(tag)
      end

      def list(tag, ref_name, mbox_name)
        not_allowed_command_response(tag)
      end

      def lsub(tag, ref_name, mbox_name)
        not_allowed_command_response(tag)
      end

      def status(tag, mbox_name, data_item_group)
        not_allowed_command_response(tag)
      end

      def append(tag, mbox_name, *opt_args, msg_text)
      end

      def check(tag)
        not_allowed_command_response(tag)
      end

      def close(tag)
        not_allowed_command_response(tag)
      end

      def expunge(tag)
        not_allowed_command_response(tag)
      end

      def search(tag, *cond_args, uid: false)
        not_allowed_command_response(tag)
      end

      def fetch(tag, msg_set, data_item_group, uid: false)
        not_allowed_command_response(tag)
      end

      def store(tag, msg_set, data_item_name, data_item_value, uid: false)
        not_allowed_command_response(tag)
      end

      def copy(tag, msg_set, mbox_name, uid: false)
        not_allowed_command_response(tag)
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
