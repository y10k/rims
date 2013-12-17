# -*- coding: utf-8 -*-

require 'mail'
require 'set'
require 'time'

module RIMS
  module Protocol
    def quote(s)
      case (s)
      when /"/, /\n/
        "{#{s.bytesize}}\r\n" + s
      else
        '"' + s + '"'
      end
    end
    module_function :quote

    def compile_wildcard(pattern)
      src = '^'
      src << pattern.gsub(/.*?[*%]/) {|s| Regexp.quote(s[0..-2]) + '.*' }
      src << Regexp.quote($') if $'
      src << '$'
      Regexp.compile(src)
    end
    module_function :compile_wildcard

    def read_line(input)
      line = input.gets or return
      line.chomp!("\n")
      line.chomp!("\r")
      scan_line(line, input)
    end
    module_function :read_line

    def scan_line(line, input)
      atom_list = line.scan(/BODY(?:\.\S+)?\[.*?\](?:<\d+\.\d+>)?|[\[\]()]|".*?"|[^\[\]()\s]+/i).map{|s|
        case (s)
        when '(', ')', '[', ']', /^NIL$/
          s.upcase.intern
        when /^"/
          s.sub(/^"/, '').sub(/"$/, '')
        else
          s
        end
      }
      if ((atom_list[-1].is_a? String) && (atom_list[-1] =~ /^{\d+}$/)) then
        next_size = $&[1..-2].to_i
        atom_list[-1] = input.read(next_size) or raise 'unexpected client close.'
        next_atom_list = read_line(input) or raise 'unexpected client close.'
        atom_list += next_atom_list
      end

      atom_list
    end
    module_function :scan_line

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
        when /^(?<body_source>BODY(?:\.(?<body_option>\S+))?\[(?<body_section>.*)\])(?:<(?<body_offset>\d+)\.(?<body_size>\d+)>)?/i
          body_source = $~[:body_source]
          body_option = $~[:body_option]
          body_section = $~[:body_section]
          if ($~[:body_offset] && $~[:body_size]) then
            body_partial = [ $~[:body_offset].to_i, $~[:body_size].to_i ]
          else
            body_partial = nil
          end
          syntax_list.push([ :body, body_source, body_option, parse(scan_line(body_section, nil)), body_partial ])
        else
          syntax_list.push(atom)
        end
      end

      if (atom == nil && last_atom != nil) then
        raise 'syntax error.'
      end

      syntax_list
    end
    module_function :parse

    def read_command(input)
      while (atom_list = read_line(input))
        if (atom_list.empty?) then
          next
        end
        if (atom_list.length < 2) then
          raise 'need for tag and command.'
        end
        if (atom_list[0] =~ /^[*+]/) then
          raise "invalid command tag: #{atom_list[0]}"
        end
        return parse(atom_list)
      end

      nil
    end
    module_function :read_command

    class SearchParser
      def initialize(mail_store, folder)
        @mail_store = mail_store
        @folder = folder
        @charset = nil
        @mail_cache = Hash.new{|hash, msg_id|
          if (text = @mail_store.msg_text(@folder.id, msg_id)) then
            hash[msg_id] = Mail.new(text)
          end
        }
      end

      attr_accessor :charset

      def str2time(time_string)
        if (time_string.is_a? String) then
          begin
            Time.parse(time_string)
          rescue ArgumentError
            nil
          end
        end
      end
      private :str2time

      def string_include?(search_string, text)
        unless (search_string.ascii_only?) then
          if (@charset) then
            search_string = search_string.dup.force_encoding(@charset)
            text = text.encode(@charset)
          end
        end

        text.include? search_string
      end
      private :string_include?

      def mail_body_text(mail)
        case (mail.content_type)
        when /^text/i, /^message/i
          text = mail.body.to_s
          if (charset = mail['content-type'].parameters['charset']) then
            if (text.encoding != Encoding.find(charset)) then
              text = text.dup.force_encoding(charset)
            end
          end
          text
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
            @mail_store.msg_flag(@folder.id, msg.id, name) && next_cond.call(msg)
          }
        }
      end
      private :parse_msg_flag_enabled

      def parse_msg_flag_disabled(name)
        proc{|next_cond|
          proc{|msg|
            (! @mail_store.msg_flag(@folder.id, msg.id, name)) && next_cond.call(msg)
          }
        }
      end
      private :parse_msg_flag_enabled

      def parse_search_header(name, search_string)
        proc{|next_cond|
          proc{|msg|
            mail = @mail_cache[msg.id]
            field_string = (mail[name]) ? mail[name].to_s : ''
            string_include?(search_string, field_string) && next_cond.call(msg)
          }
        }
      end
      private :parse_search_header

      def parse_internal_date(search_time) # :yields: mail_date, boundary
        d = search_time.to_date
        proc{|next_cond|
          proc{|msg|
            yield(@mail_store.msg_date(@folder.id, msg.id).to_date, d) && next_cond.call(msg)
          }
        }
      end
      private :parse_internal_date

      def parse_mail_date(search_time) # :yields: internal_date, boundary
        d = search_time.to_date
        proc{|next_cond|
          proc{|msg|
            if (mail_datetime = @mail_cache[msg.id].date) then
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
            yield(@mail_store.msg_text(@folder.id, msg.id).bytesize, octet_size) && next_cond.call(msg)
          }
        }
      end
      private :parse_mail_bytesize

      def parse_body(search_string)
        proc{|next_cond|
          proc{|msg|
            if (text = mail_body_text(@mail_cache[msg.id])) then
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
            @mail_store.msg_flag(@folder.id, msg.id, 'recent') && \
            (! @mail_store.msg_flag(@folder.id, msg.id, 'seen')) && next_cond.call(msg)
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
            (! @mail_store.msg_flag(@folder.id, msg.id, 'recent')) && next_cond.call(msg)
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
            mail = @mail_cache[msg.id]
            names = mail.header.map{|field| field.name.to_s }
            text = mail_body_text(mail)
            (names.any?{|n| search.call(n) || search.call(mail[n].to_s) } || (! text.nil? && search.call(text))) && next_cond.call(msg)
          }
        }
      end
      private :parse_text

      def parse_uid(msg_set)
        proc{|next_cond|
          proc{|msg|
            (msg_set.include? msg.id) && next_cond.call(msg)
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
        group_cond = parse(search_key)
        proc{|next_cond|
          proc{|msg|
            group_cond.call(msg) && next_cond.call(msg)
          }
        }
      end
      private :parse_group

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
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of BCC.'
          search_string.is_a? String or raise SyntaxError, "BCC search string expected as <String> but was <#{search_string.class}>."
          factory = parse_search_header('bcc', search_string)
        when 'BEFORE'
          search_date = search_key.shift or raise SyntaxError, 'need for a search date of BEFORE.'
          t = str2time(search_date) or raise SyntaxError, "BEFORE search date is invalid: #{search_date}"
          factory = parse_internal_date(t) {|d, boundary| d < boundary }
        when 'BODY'
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of BODY.'
          search_string.is_a? String or raise SyntaxError, "BODY search string expected as <String> but was <#{search_string.class}>."
          factory = parse_body(search_string)
        when 'CC'
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of CC.'
          search_string.is_a? String or raise SyntaxError, "CC search string expected as <String> but was <#{search_string.class}>."
          factory = parse_search_header('cc', search_string)
        when 'DELETED'
          factory = parse_msg_flag_enabled('deleted')
        when 'DRAFT'
          factory = parse_msg_flag_enabled('draft')
        when 'FLAGGED'
          factory = parse_msg_flag_enabled('flagged')
        when 'FROM'
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of FROM.'
          search_string.is_a? String or raise SyntaxError, "FROM search string expected as <String> but was <#{search_string.class}>."
          factory = parse_search_header('from', search_string)
        when 'HEADER'
          header_name = search_key.shift or raise SyntaxError, 'need for a header name of HEADER.'
          header_name.is_a? String or raise SyntaxError, "HEADER header name expected as <String> but was <#{header_name.class}>."
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of HEADER.'
          search_string.is_a? String or raise SyntaxError, "HEADER search string expected as <String> but was <#{search_string.class}>."
          factory = parse_search_header(header_name, search_string)
        when 'KEYWORD'
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of KEYWORD.'
          search_string.is_a? String or raise SyntaxError, "KEYWORD search string expected as <String> but was <#{search_string.class}>."
          factory = parse_keyword(search_string)
        when 'LARGER'
          octet_size = search_key.shift or raise SyntaxError, 'need for a octet size of LARGER.'
          (octet_size.is_a? String) && (octet_size =~ /^\d+$/) or
            raise SyntaxError, "LARGER octet size is expected as numeric string but was <#{octet_size}>."
          factory = parse_mail_bytesize(octet_size.to_i) {|size, boundary| size > boundary }
        when 'NEW'
          factory = parse_new
        when 'NOT'
          next_node = fetch_next_node(search_key)
          factory = parse_not(next_node)
        when 'OLD'
          factory = parse_old
        when 'ON'
          search_date = search_key.shift or raise SyntaxError, 'need for a search date of ON.'
          t = str2time(search_date) or raise SyntaxError, "ON search date is invalid: #{search_date}"
          factory = parse_internal_date(t) {|d, boundary| d == boundary }
        when 'OR'
          next_node1 = fetch_next_node(search_key)
          next_node2 = fetch_next_node(search_key)
          factory = parse_or(next_node1, next_node2)
        when 'RECENT'
          factory = parse_msg_flag_enabled('recent')
        when 'SEEN'
          factory = parse_msg_flag_enabled('seen')
        when 'SENTBEFORE'
          search_date = search_key.shift or raise SyntaxError, 'need for a search date of SENTBEFORE.'
          t = str2time(search_date) or raise SyntaxError, "SENTBEFORE search date is invalid: #{search_date}"
          factory = parse_mail_date(t) {|d, boundary| d < boundary }
        when 'SENTON'
          search_date = search_key.shift or raise SyntaxError, 'need for a search date of SENTON.'
          t = str2time(search_date) or raise SyntaxError, "SENTON search date is invalid: #{search_date}"
          factory = parse_mail_date(t) {|d, boundary| d == boundary }
        when 'SENTSINCE'
          search_date = search_key.shift or raise SyntaxError, 'need for a search date of SENTSINCE.'
          t = str2time(search_date) or raise SyntaxError, "SENTSINCE search date is invalid: #{search_date}"
          factory = parse_mail_date(t) {|d, boundary| d > boundary }
        when 'SINCE'
          search_date = search_key.shift or raise SyntaxError, 'need for a search date of SINCE.'
          t = str2time(search_date) or raise SyntaxError, "SINCE search date is invalid: #{search_date}"
          factory = parse_internal_date(t) {|d, boundary| d > boundary }
        when 'SMALLER'
          octet_size = search_key.shift or raise SyntaxError, 'need for a octet size of SMALLER.'
          (octet_size.is_a? String) && (octet_size =~ /^\d+$/) or
            raise SyntaxError, "SMALLER octet size is expected as numeric string but was <#{octet_size}>."
          factory = parse_mail_bytesize(octet_size.to_i) {|size, boundary| size < boundary }
        when 'SUBJECT'
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of SUBJECT.'
          search_string.is_a? String or raise SyntaxError, "SUBJECT search string expected as <String> but was <#{search_string.class}>."
          factory = parse_search_header('subject', search_string)
        when 'TEXT'
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of TEXT.'
          search_string.is_a? String or raise SyntaxError, "TEXT search string expected as <String> but was <#{search_string.class}>."
          factory = parse_text(search_string)
        when 'TO'
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of TO.'
          search_string.is_a? String or raise SyntaxError, "TO search string expected as <String> but was <#{search_string.class}>."
          factory = parse_search_header('to', search_string)
        when 'UID'
          mset_string = search_key.shift or raise SyntaxError, 'need for a message set of UID.'
          mset_string.is_a? String or raise SyntaxError, "UID message set expected as <String> but was <#{search_string.class}>."
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
          search_string = search_key.shift or raise SyntaxError, 'need for a search string of UNKEYWORD.'
          search_string.is_a? String or raise SyntaxError, "UNKEYWORD search string expected as <String> but was <#{search_string.class}>."
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

      def parse(search_key)
        unless (search_key.empty?) then
          search_key = search_key.dup
          factory = fetch_next_node(search_key)
          factory.call(parse(search_key))
        else
          return end_of_cond
        end
      end
    end

    class FetchParser
      module Utils
        def encode_list(array)
          '(' << array.map{|v|
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
          }.join(' ') << ')'
        end
        module_function :encode_list

        def encode_header(header)
          header.map{|field| "#{field.name}: #{field.value}" }.join("\r\n") + ("\r\n" * 2)
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
            elsif (mail.content_type == 'message/rfc822') then
              get_body_section(Mail.new(mail.body.raw_source), index_list)
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
            if (mail.content_type == 'message/rfc822') then
              Mail.new(mail.body.raw_source).send(name)
            else
              nil
            end
          else
            mail.send(name)
          end
        end
        module_function :get_body_content
      end
      include Utils

      def initialize(mail_store, folder)
        @mail_store = mail_store
        @folder = folder
        @charset = nil
        @mail_cache = Hash.new{|hash, msg_id|
          if (text = @mail_store.msg_text(@folder.id, msg_id)) then
            hash[msg_id] = Mail.new(text)
          end
        }
      end

      def make_array(value)
        if (value) then
          unless (value.is_a? Array) then
            [ value ]
          else
            value
          end
        end
      end
      private :make_array

      def expand_macro(cmd_list)
        func_list = cmd_list.map{|name| parse(name) }
        proc{|msg|
          func_list.map{|f| f.call(msg) }.join(' ')
        }
      end
      private :expand_macro

      def get_bodystructure_data(mail)
        if (mail.multipart?) then
          # body_type_mpart
          mpart_data = []
          mpart_data.concat(mail.parts.map{|part| get_bodystructure_data(part) })
          mpart_data << mail['Content-Type'].sub_type
        else
          case (mail.content_type)
          when /^text/i         # body_type_text
            text_data = []

            # media_text
            text_data << 'TEXT'
            text_data << mail['Content-Type'].sub_type

            # body_fields
            text_data << mail['Content-Type'].parameters.map{|n, v| [ n, v ] }.flatten
            text_data << mail.content_id
            text_data << mail.content_description
            text_data << mail.content_transfer_encoding
            text_data << mail.raw_source.bytesize

            # body_fld_lines
            text_data << mail.raw_source.each_line.count
          when /^message/i      # body_type_msg
            msg_data = []

            # message_media
            msg_data << 'MESSAGE'
            msg_data << 'RFC822'

            # body_fields
            msg_data << mail['Content-Type'].parameters.map{|n, v| [ n, v ] }.flatten
            msg_data << mail.content_id
            msg_data << mail.content_description
            msg_data << mail.content_transfer_encoding
            msg_data << mail.raw_source.bytesize

            body_mail = Mail.new(mail.body.raw_source)

            # envelope
            msg_data << get_envelope_data(body_mail)

            # body
            msg_data << get_bodystructure_data(body_mail)

            # body_fld_lines
            msg_data << mail.raw_source.each_line.count
          else                  # body_type_basic
            basic_data = []

            # media_basic
            basic_data << mail['Content-Type'].main_type
            basic_data << mail['Content-Type'].sub_type

            # body_fields
            basic_data << mail['Content-Type'].parameters.map{|n, v| [ n, v ] }.flatten
            basic_data << mail.content_id
            basic_data << mail.content_description
            basic_data << mail.content_transfer_encoding
            basic_data << mail.raw_source.bytesize
          end
        end
      end
      private :get_bodystructure_data

      def get_envelope_data(mail)
        env_data = []
        env_data << (mail['Date'] && mail['Date'].value)
        env_data << (mail['Subject'] && mail['Subject'].value)
        env_data << make_array(mail.from)
        env_data << make_array(mail.sender)
        env_data << make_array(mail.reply_to)
        env_data << make_array(mail.to)
        env_data << make_array(mail.cc)
        env_data << make_array(mail.bcc)
        env_data << mail.in_reply_to
        env_data << mail.message_id
      end
      private :get_envelope_data

      def parse_body(source, option, section, partial)
        enable_seen = true
        if (option) then
          case (option.upcase)
          when 'PEEK'
            enable_seen = false
          else
            raise SyntaxError, "unknown fetch body option: #{option}"
          end
        end

        if (enable_seen) then
          fetch_flags = parse_flags('FLAGS')
          fetch_flags_changed = proc{|msg|
            unless (@mail_store.msg_flag(@folder.id, msg.id, 'seen')) then
              @mail_store.set_msg_flag(@folder.id, msg.id, 'seen', true)
              fetch_flags.call(msg) + ' '
            else
              ''
            end
          }
        else
          fetch_flags_changed = proc{|msg|
            ''
          }
        end

        if (section.empty?) then
          section_text = nil
          section_index_list = []
        else
          if (section[0] =~ /^(?<index>\d+(?:\.\d+)*)(?:\.(?<text>.+))?$/) then
            section_text = $~[:text]
            section_index_list = $~[:index].split(/\./).map{|i| i.to_i }
          else
            section_text = section[0]
            section_index_list = []
          end
        end

        unless (section_text) then
          fetch_body_content = proc{|mail|
            mail.raw_source
          }
        else
          section_text = section_text.upcase
          is_root = section_index_list.empty?

          case (section_text)
          when 'MIME'
            if (section_index_list.empty?) then
              raise SyntaxError, "need for section index at #{section_text}."
            else
              fetch_body_content = proc{|mail|
                if (header = get_body_content(mail, :header)) then
                  header.raw_source.strip + ("\r\n" * 2)
                end
              }
            end
          when 'HEADER'
            fetch_body_content = proc{|mail|
              if (header = get_body_content(mail, :header, nest_mail: ! is_root)) then
                header.raw_source.strip + ("\r\n" * 2)
              end
            }
          when 'HEADER.FIELDS', 'HEADER.FIELDS.NOT'
            if (section.length != 2) then
              raise SyntaxError, "need for argument of #{section_text}."
            end
            field_name_list = section[1]
            unless ((field_name_list.is_a? Array) && (field_name_list[0] == :group)) then
              raise SyntaxError, "invalid argument of #{section_text}: #{field_name_list}"
            end
            field_name_list = field_name_list[1..-1]
            case (section_text)
            when 'HEADER.FIELDS'
              fetch_body_content = proc{|mail|
                if (header = get_body_content(mail, :header, nest_mail: ! is_root)) then
                  encode_header(field_name_list.map{|n| header[n] }.compact)
                end
              }
            when 'HEADER.FIELDS.NOT'
              fetch_body_content = proc{|mail|
                if (header = get_body_content(mail, :header, nest_mail: ! is_root)) then
                  field_name_set = field_name_list.map{|n| header[n] }.compact.map{|i| i.name }.to_set
                  encode_header(header.reject{|i| (field_name_set.include? i.name) })
                end
              }
            else
              raise 'internal error.'
            end
          when 'TEXT'
            fetch_body_content = proc{|mail|
              if (body = get_body_content(mail, :body, nest_mail: ! is_root)) then
                body.raw_source
              end
            }
          else
            raise SyntaxError, "unknown fetch body section text: #{section_text}"
          end
        end

        pos, size = partial if partial
        proc{|msg|
          res = ''
          res << fetch_flags_changed.call(msg)
          res << source
          res << "<#{pos}>" if pos
          res << ' '

          mail = get_body_section(@mail_cache[msg.id], section_index_list)
          content = fetch_body_content.call(mail) if mail
          if (content) then
            if (partial) then
              if (content.bytesize > pos) then
                res << Protocol.quote(content.byteslice(pos, size))
              else
                res << 'NIL'
              end
            else
              res << Protocol.quote(content)
            end
          else
            res << 'NIL'
          end
        }
      end
      private :parse_body

      def parse_bodystructure(name)
        proc{|msg|
          mail = @mail_cache[msg.id] or raise 'internal error.'
          "#{name} #{encode_list(get_bodystructure_data(mail))}"
        }
      end
      private :parse_bodystructure

      def parse_envelope(name)
        proc{|msg|
          mail = @mail_cache[msg.id] or raise 'internal error.'
          "#{name} #{encode_list(get_envelope_data(mail))}"
        }
      end
      private :parse_envelope

      def parse_flags(name)
        proc{|msg|
          flag_list = MailStore::MSG_FLAG_NAMES.find_all{|name|
            @mail_store.msg_flag(@folder.id, msg.id, name)
          }.map{|name|
            "\\#{name.capitalize}"
          }.join(' ')
          "#{name} (#{flag_list})"
        }
      end
      private :parse_flags

      def parse_internaldate(name)
        proc{|msg|
          name + @mail_store.msg_date(@folder.id, msg.id).strftime(' "%d-%m-%Y %H:%M:%S %z"')
        }
      end
      private :parse_internaldate

      def parse_rfc822_size(name)
        proc{|msg|
          mail = @mail_cache[msg.id] or raise 'internal error.'
          "#{name} #{mail.raw_source.bytesize}"
        }
      end
      private :parse_rfc822_size

      def parse_uid(name)
        proc{|msg|
          "#{name} #{msg.id}"
        }
      end
      private :parse_uid

      def parse_group(fetch_attrs)
        group_fetch_list = fetch_attrs.map{|fetch_att| parse(fetch_att) }
        proc{|msg|
          '(' << group_fetch_list.map{|fetch| fetch.call(msg) }.join(' ') << ')'
        }
      end
      private :parse_group

      def parse(fetch_att)
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
        when 'FLAGS'
          fetch = parse_flags(fetch_att)
        when 'INTERNALDATE'
          fetch = parse_internaldate(fetch_att)
        when 'RFC822'
          fetch = parse_body(fetch_att, nil, [], nil)
        when 'RFC822.HEADER'
          fetch = parse_body(fetch_att, 'PEEK', [ 'HEADER' ], nil)
        when 'RFC822.SIZE'
          fetch = parse_rfc822_size(fetch_att)
        when 'RFC822.TEXT'
          fetch = parse_body(fetch_att, nil, [ 'TEXT' ], nil)
        when 'UID'
          fetch = parse_uid(fetch_att)
        when Array
          case (fetch_att[0])
          when :group
            fetch = parse_group(fetch_att[1..-1])
          when :body
            fetch = parse_body(fetch_att[1], fetch_att[2], fetch_att[3], fetch_att[4])
          else
            raise SyntaxError, "unknown fetch attribute: #{fetch_att[0]}"
          end
        else
          raise SyntaxError, "unknown fetch attribute: #{fetch_att}"
        end

        fetch
      end
    end
  end

  class ProtocolDecoder
    def initialize(mail_store_pool, passwd, logger)
      @mail_store_pool = mail_store_pool
      @mail_store_holder = nil
      @folder = nil
      @logger = logger
      @passwd = passwd
    end

    def auth?
      @mail_store_holder != nil
    end

    def selected?
      auth? && (@folder != nil)
    end

    def cleanup
      if (auth?) then
        tmp_mail_store = @mail_store_holder
        @mail_store_holder = nil
        @mail_store_pool.put(tmp_mail_store)
      end

      nil
    end

    def protect_error(tag)
      begin
        yield
      rescue SyntaxError
        @logger.error('client command syntax error.')
        @logger.error($!)
        [ "#{tag} BAD client command syntax error." ]
      rescue
        @logger.error('internal server error.')
        @logger.error($!)
        [ "#{tag} BAD internal server error" ]
      end
    end
    private :protect_error

    def protect_auth(tag)
      protect_error(tag) {
        if (auth?) then
          @mail_store_holder.user_lock.synchronize{
            yield
          }
        else
          [ "#{tag} NO no authentication" ]
        end
      }
    end
    private :protect_auth

    def protect_select(tag)
      protect_auth(tag) {
        if (selected?) then
          yield
        else
          [ "#{tag} NO no selected" ]
        end
      }
    end
    private :protect_select

    def capability(tag)
      [ '* CAPABILITY IMAP4rev1',
        "#{tag} OK CAPABILITY completed"
      ]
    end

    def noop(tag)
      res = []
      if (auth? && selected?) then
        @mail_store_holder.user_lock.synchronize{
          @folder.reload if @folder.updated?
          res << "* #{@mail_store_holder.to_mst.mbox_msgs(@folder.id)} EXISTS"
          res << "* #{@mail_store_holder.to_mst.mbox_flags(@folder.id, 'resent')} RECENTS"
        }
      end
      res << "#{tag} OK NOOP completed"
    end

    def logout(tag)
      if (auth? && selected?) then
        @mail_store_holder.user_lock.synchronize{
          @folder.reload if @folder.updated?
          @folder.close
          @folder = nil
        }
      end
      cleanup
      res = []
      res << '* BYE server logout'
      res << "#{tag} OK LOGOUT completed"
    end

    def authenticate(tag, auth_name)
      [ "#{tag} NO no support mechanism" ]
    end

    def login(tag, username, password)
      res = []
      if (@passwd.call(username, password)) then
        cleanup
        @mail_store_holder = @mail_store_pool.get(username)
        res << "#{tag} OK LOGIN completed"
      else
        res << "#{tag} NO failed to login"
      end
    end

    def select(tag, mbox_name)
      protect_auth(tag) {
        res = []
        @folder = nil
        if (id = @mail_store_holder.to_mst.mbox_id(mbox_name)) then
          @folder = @mail_store_holder.to_mst.select_mbox(id)
          all_msgs = @mail_store_holder.to_mst.mbox_msgs(@folder.id)
          recent_msgs = @mail_store_holder.to_mst.mbox_flags(@folder.id, 'recent')
          unseen_msgs = all_msgs - @mail_store_holder.to_mst.mbox_flags(@folder.id, 'seen')
          res << "* #{all_msgs} EXISTS"
          res << "* #{recent_msgs} RECENT"
          res << "* [UNSEEN #{unseen_msgs}]"
          res << "* [UIDVALIDITY #{@folder.id}]"
          res << "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)"
          res << "#{tag} OK [READ-WRITE] SELECT completed"
        else
          res << "#{tag} NO not found a mailbox"
        end
      }
    end

    def examine(tag, mbox_name)
      protect_auth(tag) {
        [ "#{tag} BAD not implemented" ]
      }
    end

    def create(tag, mbox_name)
      protect_auth(tag) {
        res = []
        if (@mail_store_holder.to_mst.mbox_id(mbox_name)) then
          res << "#{tag} NO duplicated mailbox"
        else
          @mail_store_holder.to_mst.add_mbox(mbox_name)
          res << "#{tag} OK CREATE completed"
        end
      }
    end

    def delete(tag, mbox_name)
      protect_auth(tag) {
        res = []
        if (id = @mail_store_holder.to_mst.mbox_id(mbox_name)) then
          if (id != @mail_store_holder.to_mst.mbox_id('INBOX')) then
            @mail_store_holder.to_mst.del_mbox(id)
            res << "#{tag} OK DELETE completed"
          else
            res << "#{tag} NO not delete inbox"
          end
        else
          res << "#{tag} NO not found a mailbox"
        end
      }
    end

    def rename(tag, src_name, dst_name)
      protect_auth(tag) {
        [ "#{tag} BAD not implemented" ]
      }
    end

    def subscribe(tag, mbox_name)
      protect_auth(tag) {
        [ "#{tag} BAD not implemented" ]
      }
    end

    def unsubscribe(tag, mbox_name)
      protect_auth(tag) {
        [ "#{tag} BAD not implemented" ]
      }
    end

    def list(tag, ref_name, mbox_name)
      protect_auth(tag) {
        res = []
        if (mbox_name.empty?) then
          res << '* LIST (\Noselect) NIL ""'
        else
          mbox_filter = Protocol.compile_wildcard(mbox_name)
          mbox_list = @mail_store_holder.to_mst.each_mbox_id.map{|id| [ id, @mail_store_holder.to_mst.mbox_name(id) ] }
          mbox_list.keep_if{|id, name| name.start_with? ref_name }
          mbox_list.keep_if{|id, name| name[(ref_name.length)..-1] =~ mbox_filter }
          for id, name in mbox_list
            attrs = '\Noinferiors'
            if (@mail_store_holder.to_mst.mbox_flags(id, 'recent') > 0) then
              attrs << ' \Marked'
            else
              attrs << ' \Unmarked'
            end
            res << "* LIST (#{attrs}) NIL #{Protocol.quote(name)}"
          end
        end
        res << "#{tag} OK LIST completed"
      }
    end

    def lsub(tag, ref_name, mbox_name)
      protect_auth(tag) {
        [ "#{tag} BAD not implemented" ]
      }
    end

    def status(tag, mbox_name, data_item_group)
      protect_auth(tag) {
        res = []
        if (id = @mail_store_holder.to_mst.mbox_id(mbox_name)) then
          unless ((data_item_group.is_a? Array) && (data_item_group[0] == :group)) then
            raise SyntaxError, 'second arugment is not a group list.'
          end

          values = []
          for item in data_item_group[1..-1]
            case (item.upcase)
            when 'MESSAGES'
              values << 'MESSAGES' << @mail_store_holder.to_mst.mbox_msgs(id)
            when 'RECENT'
              values << 'RECENT' << @mail_store_holder.to_mst.mbox_flags(id, 'recent')
            when 'UINDEX'
              values << 'UINDEX' << @mail_store_holder.to_mst.uid
            when 'UIDVALIDITY'
              values << 'UIDVALIDITY' << id
            when 'UNSEEN'
              unseen_flags = @mail_store_holder.to_mst.mbox_msgs(id) - @mail_store_holder.to_mst.mbox_flags(id, 'seen')
              values << 'UNSEEN' << unseen_flags
            else
              raise SyntaxError, "unknown status data: #{item}"
            end
          end

          res << "* STATUS #{Protocol.quote(mbox_name)} (#{values.join(' ')})"
          res << "#{tag} OK STATUS completed"
        else
          res << "#{tag} NO not found a mailbox"
        end
      }
    end

    def append(tag, mbox_name, *opt_args, msg_text)
      protect_auth(tag) {
        res = []
        if (mbox_id = @mail_store_holder.to_mst.mbox_id(mbox_name)) then
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

          msg_id = @mail_store_holder.to_mst.add_msg(mbox_id, msg_text, msg_date)
          for flag_name in msg_flags
            @mail_store_holder.to_mst.set_msg_flag(mbox_id, msg_id, flag_name, true)
          end

          res << "#{tag} OK APPEND completed"
        else
          res << "#{tag} NO [TRYCREATE] not found a mailbox"
        end
      }
    end

    def check(tag)
      protect_select(tag) {
        @mail_store_holder.to_mst.sync
        [ "#{tag} OK CHECK completed" ]
      }
    end

    def close(tag)
      protect_select(tag) {
        @mail_store_holder.to_mst.sync
        if (@folder) then
          @folder.reload if @folder.updated?
          @folder.close
          @folder = nil
        end
        [ "#{tag} OK CLOSE completed" ]
      }
    end

    def expunge(tag)
      protect_select(tag) {
        res = []
        @folder.reload if @folder.updated?
        @folder.expunge_mbox do |msg_num|
          res << "* #{msg_num} EXPUNGE"
        end
        @folder.reload if @folder.updated?
        res << "#{tag} OK EXPUNGE completed"
      }
    end

    def search(tag, *cond_args, uid: false)
      protect_select(tag) {
        @folder.reload if @folder.updated?
        parser = Protocol::SearchParser.new(@mail_store_holder.to_mst, @folder)
        if (cond_args[0].upcase == 'CHARSET') then
          cond_args.shift
          charset_string = cond_args.shift or raise SyntaxError, 'need for a charset string of CHARSET'
          charset_string.is_a? String or raise SyntaxError, "CHARSET charset string expected as <String> but was <#{charset_string.class}>."
          parser.charset = charset_string
        end
        cond = parser.parse(cond_args)
        msg_list = @folder.msg_list.find_all{|msg| cond.call(msg) }

        search_resp = '* SEARCH'
        for msg in msg_list
          if (uid) then
            search_resp << " #{msg.id}"
          else
            search_resp << " #{msg.num}"
          end
        end

        [ search_resp,
          "#{tag} OK SEARCH completed"
        ]
      }
    end

    def fetch(tag, msg_set, data_item_group, uid: false)
      protect_select(tag) {
        [ "#{tag} BAD not implemented" ]
      }
    end

    def store(tag, msg_set, data_item_name, data_item_value, uid: false)
      protect_select(tag) {
        @folder.reload if @folder.updated?

        res = []
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
          raise "unknown store action: #{name}"
        end

        case (option && option.upcase)
        when 'SILENT'
          is_silent = true
        when nil
          is_silent = false
        else
          raise "unknown store option: #{option.inspect}"
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
            msg_set.include? msg.id
          else
            msg_set.include? msg.num
          end
        }

        for msg in msg_list
          case (action)
          when :flags_replace
            for name in flag_list
              @mail_store_holder.to_mst.set_msg_flag(@folder.id, msg.id, name, true)
            end
            for name in rest_flag_list
              @mail_store_holder.to_mst.set_msg_flag(@folder.id, msg.id, name, false)
            end
          when :flags_add
            for name in flag_list
              @mail_store_holder.to_mst.set_msg_flag(@folder.id, msg.id, name, true)
            end
          when :flags_del
            for name in flag_list
              @mail_store_holder.to_mst.set_msg_flag(@folder.id, msg.id, name, false)
            end
          else
            raise "internal error: unknown action: #{action}"
          end
        end

        unless (is_silent) then
          for msg in msg_list
            flag_atom_list = []
            for name in MailStore::MSG_FLAG_NAMES
              if (@mail_store_holder.to_mst.msg_flag(@folder.id, msg.id, name)) then
                flag_atom_list << "\\#{name.capitalize}"
              end
            end
            res << "* #{msg.num} FETCH FLAGS (#{flag_atom_list.join(' ')})"
          end
        end

        res << "#{tag} OK STORE completed"
      }
    end

    def copy(tag, msg_set, mbox_name, uid: false)
      protect_select(tag) {
        res = []
        msg_set = @folder.parse_msg_set(msg_set, uid: uid)

        if (mbox_id = @mail_store_holder.to_mst.mbox_id(mbox_name)) then
          msg_list = @folder.msg_list.find_all{|msg|
            if (uid) then
              msg_set.include? msg.id
            else
              msg_set.include? msg.num
            end
          }

          for msg in msg_list
            @mail_store_holder.to_mst.copy_msg(msg.id, mbox_id)
          end

          res << "#{tag} OK COPY completed"
        else
          res << "#{tag} NO [TRYCREATE] not found a mailbox"
        end
      }
    end

    def self.repl(decoder, input, output, logger)
      loop do
        begin
          atom_list = Protocol.read_command(input)
        rescue
          logger.error('invalid client command.')
          logger.error($!)
          next
        end

        break unless atom_list

        tag, command, *opt_args = atom_list
        logger.info("client command: #{command}")
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
            res = decoder.authenticate(tag, *opt_args)
          when 'LOGIN'
            res = decoder.login(tag, *opt_args)
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
              logger.debug("uid parameter: (#{uid_args.join(' ')})") if logger.debug?
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
                res = [ "#{tag} BAD unknown uid command" ]
              end
            else
              logger.error('empty uid parameter.')
              res = [ "#{tag} BAD empty uid parameter" ]
            end
          else
            logger.error("unknown command: #{command}")
            res = [ "#{tag} BAD unknown command" ]
          end
        rescue ArgumentError
          logger.error('invalid command parameter.')
          logger.error($!)
          res = [ "#{tag} BAD invalid command parameter" ]
        rescue
          logger.error('internal server error.')
          logger.error($!)
          res = [ "#{tag} BAD internal server error" ]
        end

        logger.info("server response: #{res[-1]}")
        for line in res
          logger.debug(line) if logger.debug?
          output << line << "\r\n"
        end
        output.flush

        if (command.upcase == 'LOGOUT') then
          break
        end
      end

      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
