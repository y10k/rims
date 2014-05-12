# -*- coding: utf-8 -*-

require 'set'

module RIMS
  module Test
    module AssertUtility
      def literal(text_string)
        "{#{text_string.bytesize}}\r\n#{text_string}"
      end
      module_function :literal

      def make_header_text(name_value_pair_list, select_list: [], reject_list: [])
        name_value_pair_list = name_value_pair_list.to_a.dup
        select_set = select_list.map{|name| name.downcase }.to_set
        reject_set = reject_list.map{|name| name.downcase }.to_set

        name_value_pair_list.select!{|name, value| select_set.include? name.downcase } unless select_set.empty?
        name_value_pair_list.reject!{|name, value| reject_set.include? name.downcase } unless reject_set.empty?
        name_value_pair_list.map{|name, value| "#{name}: #{value}\r\n" }.join('') + "\r\n"
      end
      module_function :make_header_text

      def message_data_list(msg_data_array)
        msg_data_array.map{|msg_data|
          case (msg_data)
          when String
            msg_data
          when Array
            '(' << message_data_list(msg_data) << ')'
          else
            raise "unknown message data: #{msg_data}"
          end
        }.join(' ')
      end
      module_function :message_data_list

      def assert_strenc_equal(expected_enc, expected_str, expr_str)
        assert_equal(Encoding.find(expected_enc), expr_str.encoding)
        assert_equal(expected_str.dup.force_encoding(expected_enc), expr_str)
      end
      module_function :assert_strenc_equal
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
