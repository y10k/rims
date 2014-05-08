# -*- coding: utf-8 -*-

module RIMS
  module Test
    module AssertUtility
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
