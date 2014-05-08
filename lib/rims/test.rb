# -*- coding: utf-8 -*-

module RIMS
  module Test
    module AssertUtility
      def literal(text_string)
        "{#{text_string.bytesize}}\r\n#{text_string}"
      end
      module_function :literal

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
