# -*- coding: utf-8 -*-

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

    def parse(atom_list, last_atom=nil)
      syntax_list = []
      while (atom = atom_list.shift)
        case (atom)
        when last_atom
          break
        when '('
          syntax_list.push([ :group ] + parse(atom_list, ')'))
        when '['
          syntax_list.push([ :block ] + parse(atom_list, ']'))
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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
