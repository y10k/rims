# -*- coding: utf-8 -*-

require 'time'

module RIMS
  module RFC822
    def split_message(msg_txt)
      header_txt, body_txt = msg_txt.lstrip.split(/\r?\n\r?\n/, 2)
      header_txt << $& if $&
      [ header_txt, body_txt ]
    end
    module_function :split_message

    def parse_header(header_txt)
      field_pair_list = header_txt.scan(%r{
        ^((?#name) \S+ ) \s* : \s* ((?#value)
                                    .*? (?: \n|\z)
                                    (?: ^\s .*? (?: \n|\z) )*
                                   )
      }x)

      for name, value in field_pair_list
        value.strip!
      end

      field_pair_list
    end
    module_function :parse_header

    def parse_content_type(content_type_txt)
      src_txt = content_type_txt.dup
      if (src_txt.sub!(%r"\A \s* (?<main_type>\S+?) \s* / \s* (?<sub_type>\S+?) \s* (?:;|\Z)"x, '')) then
        main_type = $~[:main_type]
        sub_type = $~[:sub_type]

        params = {}
        src_txt.scan(%r'(?<name>\S+?) \s* = \s* (?: (?<quoted_string>".*?") | (?<token>\S+?) ) \s* (?:;|\Z)'x) do
          name = $~[:name]
          if ($~[:quoted_string]) then
            quoted_value = $~[:quoted_string]
            value = unquote_phrase(quoted_value)
          else
            value = $~[:token]
          end
          params[name.downcase] = [ name, value ]
        end

        [ main_type, sub_type, params ]
      else
        [ 'application', 'octet-stream', {} ]
      end
    end
    module_function :parse_content_type

    def parse_multipart_body(boundary, body_txt)
      delim = '--' + boundary
      term = delim + '--'
      body_txt2, body_epilogue_txt = body_txt.split(term, 2)
      if (body_txt2) then
        body_preamble_txt, body_parts_txt = body_txt2.split(delim, 2)
        if (body_parts_txt) then
          part_list = body_parts_txt.split(delim, -1)
          for part_txt in part_list
            part_txt.lstrip!
            part_txt.chomp!("\n")
            part_txt.chomp!("\r")
          end
          return part_list
        end
      end

      []
    end
    module_function :parse_multipart_body

    def unquote_phrase(phrase_txt)
      state = :raw
      src_txt = phrase_txt.dup
      dst_txt = ''.encode(phrase_txt.encoding)

      while (src_txt.sub!(/\A(:? " | \( | \) | \\ | [^"\(\)\\]+ )/x, ''))
        match_txt = $&
        case (state)
        when :raw
          case (match_txt)
          when '"'
            state = :quote
          when '('
            state = :comment
          when "\\"
            src_txt.sub!(/\A./, '') and dst_txt << $&
          else
            dst_txt << match_txt
          end
        when :quote
          case (match_txt)
          when '"'
            state = :raw
          when "\\"
            src_txt.sub!(/\A./, '') && dst_txt << $&
          else
            dst_txt << match_txt
          end
        when :comment
          case (match_txt)
          when ')'
            state = :raw
          when "\\"
            src_txt.sub!(/\A./, '')
          else
            # ignore comment text.
          end
        else
          raise "internal error: unknown state #{state}"
        end
      end

      dst_txt
    end
    module_function :unquote_phrase

    def parse_mail_address_list(address_list_txt)
      addr_list = []
      src_txt = address_list_txt.dup

      while (true)
        if (src_txt.sub!(%r{
              \A
              \s*
              (?<display_name>\S.*?) \s* : (?<group_list>.*?) ;
              \s*
              ,?
            }x, ''))
        then
          display_name = $~[:display_name]
          group_list = $~[:group_list]
          addr_list << [ nil, nil, unquote_phrase(display_name), nil ]
          addr_list.concat(parse_mail_address_list(group_list))
          addr_list << [ nil, nil, nil, nil ]
        elsif (src_txt.sub!(%r{
                 \A
                 \s*
                 (?<local_part>[^<>@,\s]+) \s* @ \s* (?<domain>[^<>@,\s]+)
                 \s*
                 ,?
               }x, ''))
        then
          addr_list << [ nil, nil, $~[:local_part], $~[:domain] ]
        elsif (src_txt.sub!(%r{
                 \A
                 \s*
                 (?<display_name>\S.*?)
                 \s*
                 <
                   \s*
                   (?:
                     (?<route>@[^<>@,]* (?:, \s* @[^<>@,]*)*)
                     \s*
                     :
                   )?
                   \s*
                   (?<local_part>[^<>@,\s]+) \s* @ \s* (?<domain>[^<>@,\s]+)
                   \s*
                 >
                 \s*
                 ,?
               }x, ''))
        then
          display_name = $~[:display_name]
          route = $~[:route]
          local_part = $~[:local_part]
          domain = $~[:domain]
          addr_list << [ unquote_phrase(display_name), route, local_part, domain ]
        else
          break
        end
      end

      addr_list
    end
    module_function :parse_mail_address_list

    class Header
      include Enumerable

      def initialize(header_txt)
        @raw_source = header_txt
        @field_list = nil
        @field_map = nil
      end

      attr_reader :raw_source

      def setup_header
        if (@field_list.nil? || @field_map.nil?) then
          @field_list = []
          @field_map = {}
          for name, value in RFC822.parse_header(@raw_source)
            @field_list << [ name, value ]
            key = name.downcase
            @field_map[key] = [] unless (@field_map.key? key)
            @field_map[key] << value
          end
          self
        end
      end
      private :setup_header

      def each
        setup_header
        return enum_for(:each) unless block_given?
        for name, value in @field_list
          yield(name, value)
        end
        self
      end

      def key?(name)
        setup_header
        @field_map.key? name.downcase
      end

      def [](name)
        setup_header
        if (value_list = @field_map[name.downcase]) then
          value_list[0]
        end
      end

      def field_value_list(name)
        setup_header
        @field_map[name.downcase]
      end
    end

    class Body
      def initialize(body_txt)
        @raw_source = body_txt
      end

      attr_reader :raw_source
    end

    class Message
      def initialize(msg_txt)
        @raw_source = msg_txt
        @header = nil
        @body = nil
        @content_type = nil
        @is_multipart = nil
        @parts = nil
        @is_message = nil
        @message = nil
        @date = nil
        @from = nil
        @sender = nil
        @reply_to = nil
        @to = nil
        @cc = nil
        @bcc = nil
      end

      attr_reader :raw_source

      def setup_message
        if (@header.nil? || @body.nil?) then
          header_txt, body_txt = RFC822.split_message(@raw_source)
          @header = Header.new(header_txt || '')
          @body = Body.new(body_txt || '')
          self
        end
      end
      private :setup_message

      def header
        setup_message
        @header
      end

      def body
        setup_message
        @body
      end

      def setup_content_type
        if (@content_type.nil?) then
          @content_type = RFC822.parse_content_type(header['content-type'] || '')
          self
        end
      end
      private :setup_content_type

      def media_main_type
        setup_content_type
        @content_type[0]
      end

      def media_sub_type
        setup_content_type
        @content_type[1]
      end

      def content_type
        "#{media_main_type}/#{media_sub_type}"
      end

      def content_type_parameters
        setup_content_type
        @content_type[2].each_value.map{|name, value| [ name, value ] }
      end

      def charset
        setup_content_type
        if (name_value_pair = @content_type[2]['charset']) then
          name_value_pair[1]
        end
      end

      def boundary
        setup_content_type
        if (name_value_pair = @content_type[2]['boundary']) then
          name_value_pair[1]
        end
      end

      def text?
        media_main_type.downcase == 'text'
      end

      def multipart?
        if (@is_multipart.nil?) then
          @is_multipart = (media_main_type.downcase == 'multipart')
        end
        @is_multipart
      end

      def parts
        if (multipart?) then
          if (@parts.nil?) then
            if (boundary = self.boundary) then
              part_list = RFC822.parse_multipart_body(boundary, body.raw_source)
              @parts = part_list.map{|msg_txt| Message.new(msg_txt) }
            else
              @parts = []
            end
          end
          @parts
        end
      end

      def message?
        if (@is_message.nil?) then
          @is_message = (media_main_type.downcase == 'message')
        end
        @is_message
      end

      def message
        if (message?) then
          if (@message.nil?) then
            @message = Message.new(body.raw_source)
          end
          @message
        end
      end

      def date
        if (header.key? 'Date') then
          if (@date.nil?) then
            begin
              @date = Time.parse(header['Date'])
            rescue ArgumentError
              @date = Time.at(0)
            end
          end

          @date
        end
      end

      def mail_address_header_field(field_name)
        if (header.key? field_name) then
          ivar_name = '@' + field_name.downcase.gsub('-', '_')
          addr_list = instance_variable_get(ivar_name)
          if (addr_list.nil?) then
            addr_list = header.field_value_list(field_name).map{|addr_list_str| RFC822.parse_mail_address_list(addr_list_str) }.inject(:+)
            instance_variable_set(ivar_name, addr_list)
          end
          addr_list
        end
      end
      private :mail_address_header_field

      def from
        mail_address_header_field('from')
      end

      def sender
        mail_address_header_field('sender')
      end

      def reply_to
        mail_address_header_field('reply-to')
      end

      def to
        mail_address_header_field('to')
      end

      def cc
        mail_address_header_field('cc')
      end

      def bcc
        mail_address_header_field('bcc')
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
