# -*- coding: utf-8 -*-

module RIMS
  module Protocol
    def read_line(input)
      line = input.gets or return
      line.chomp!("\n")
      line.chomp!("\r")
      scan_line(line, input)
    end
    module_function :read_line

    def scan_line(line, input)
      atom_list = line.scan(/[\[\]()]|".*?"|[^\[\]()\s]+/).map{|s| s.sub(/^"/, '').sub(/"$/, '') }
      if (atom_list[-1] =~ /^{\d+}$/) then
	next_size = $&[1..-2].to_i
	atom_list[-1] = input.read(next_size) or raise 'unexpected client close.'
        next_atom_list = read_line(input) or raise 'unexpected client close.'
	atom_list += next_atom_list
      end

      atom_list
    end
    module_function :scan_line
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
