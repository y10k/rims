# -*- coding: utf-8 -*-

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
      atom_list = line.scan(/[\[\]()]|".*?"|[^\[\]()\s]+/).map{|s|
        if (s.upcase == 'NIL') then
          :NIL
        else
          s.sub(/^"/, '').sub(/"$/, '')
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

  class ProtocolDecoder
    class SyntaxError < StandardError
    end

    def initialize(mail_store, passwd, logger)
      @mail_store = mail_store
      @logger = logger
      @passwd = passwd
      @is_auth = false
      @folder = nil
    end

    def auth?
      @is_auth
    end

    def selected?
      @folder != nil
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
          yield
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
        @folder.reload if @folder.updated?
        res << "* #{@mail_store.mbox_msgs(@folder.id)} EXISTS"
        res << "* #{@mail_store.mbox_flags(@folder.id, 'resent')} RECENTS"
      end
      res << "#{tag} OK NOOP completed"
    end

    def logout(tag)
      if (@folder) then
        @folder.reload if @folder.updated?
        @folder.close
        @folder = nil
      end
      @is_auth = false
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
        @is_auth = true
        res << "#{tag} OK LOGIN completed"
      else
        res << "#{tag} NO failed to login"
      end
    end

    def select(tag, mbox_name)
      protect_auth(tag) {
        res = []
        @folder = nil
        if (id = @mail_store.mbox_id(mbox_name)) then
          @folder = @mail_store.select_mbox(id)
          all_msgs = @mail_store.mbox_msgs(@folder.id)
          recent_msgs = @mail_store.mbox_flags(@folder.id, 'recent')
          unseen_msgs = all_msgs - @mail_store.mbox_flags(@folder.id, 'seen')
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
        if (@mail_store.mbox_id(mbox_name)) then
          res << "#{tag} NO duplicated mailbox"
        else
          @mail_store.add_mbox(mbox_name)
          res << "#{tag} OK CREATE completed"
        end
      }
    end

    def delete(tag, mbox_name)
      protect_auth(tag) {
        res = []
        if (id = @mail_store.mbox_id(mbox_name)) then
          if (id != @mail_store.mbox_id('INBOX')) then
            @mail_store.del_mbox(id)
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
          mbox_list = @mail_store.each_mbox_id.map{|id| [ id, @mail_store.mbox_name(id) ] }
          mbox_list.keep_if{|id, name| name.start_with? ref_name }
          mbox_list.keep_if{|id, name| name[(ref_name.length)..-1] =~ mbox_filter }
          for id, name in mbox_list
            attrs = '\Noinferiors'
            if (@mail_store.mbox_flags(id, 'recent') > 0) then
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
        if (id = @mail_store.mbox_id(mbox_name)) then
          unless ((data_item_group.is_a? Array) && (data_item_group[0] == :group)) then
            raise SyntaxError, 'second arugment is not a group list.'
          end

          values = []
          for item in data_item_group[1..-1]
            case (item.upcase)
            when 'MESSAGES'
              values << 'MESSAGES' << @mail_store.mbox_msgs(id)
            when 'RECENT'
              values << 'RECENT' << @mail_store.mbox_flags(id, 'recent')
            when 'UINDEX'
              values << 'UINDEX' << @mail_store.uid
            when 'UIDVALIDITY'
              values << 'UIDVALIDITY' << id
            when 'UNSEEN'
              unseen_flags = @mail_store.mbox_msgs(id) - @mail_store.mbox_flags(id, 'seen')
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
        if (mbox_id = @mail_store.mbox_id(mbox_name)) then
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

          msg_id = @mail_store.add_msg(mbox_id, msg_text, msg_date)
          for flag_name in msg_flags
            @mail_store.set_msg_flag(mbox_id, msg_id, flag_name, true)
          end

          res << "#{tag} OK APPEND completed"
        else
          res << "#{tag} NO [TRYCREATE] not found a mailbox"
        end
      }
    end

    def check(tag)
      protect_select(tag) {
        @mail_store.sync
        [ "#{tag} OK CHECK completed" ]
      }
    end

    def close(tag)
      protect_select(tag) {
        @mail_store.sync
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
        [ "#{tag} BAD not implemented" ]
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
          rest_flag_list = %w[ answered flagged deleted seen draft ] - flag_list
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
              @mail_store.set_msg_flag(@folder.id, msg.id, name, true)
            end
            for name in rest_flag_list
              @mail_store.set_msg_flag(@folder.id, msg.id, name, false)
            end
          when :flags_add
            for name in flag_list
              @mail_store.set_msg_flag(@folder.id, msg.id, name, true)
            end
          when :flags_del
            for name in flag_list
              @mail_store.set_msg_flag(@folder.id, msg.id, name, false)
            end
          else
            raise "internal error: unknown action: #{action}"
          end
        end

        unless (is_silent) then
          name_atom_pair_list = [
            %w[ answered \Answered ],
            %w[ flagged \Flagged ],
            %w[ deleted \Deleted ],
            %w[ seen \Seen ],
            %w[ draft \Draft ],
            %w[ recent \Recent ]
          ]

          for msg in msg_list
            flag_atom_list = []
            for name, atom in name_atom_pair_list
              if (@mail_store.msg_flag(@folder.id, msg.id, name)) then
                flag_atom_list << atom
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

        if (mbox_id = @mail_store.mbox_id(mbox_name)) then
          msg_list = @folder.msg_list.find_all{|msg|
            if (uid) then
              msg_set.include? msg.id
            else
              msg_set.include? msg.num
            end
          }

          for msg in msg_list
            @mail_store.copy_msg(msg.id, mbox_id)
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
          res = [ "#{tag} BAD internval server error" ]
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
