# -*- coding: utf-8 -*-

module RIMS
  module Password
    class Source
      def raw_password?
        false
      end

      def user?(username)
        raise NotImplementedError, 'not implemented.'
      end

      def fetch_password(username)
        nil
      end

      def compare_password(username, password)
        if (raw_password = fetch_password(username)) then
          password == raw_password
        end
      end

      def self.build_from_conf(config)
        raise NotImplementedError, 'not implemented.'
      end
    end

    class PlainSource < Source
      def initialize
        @passwd = {}
      end

      def raw_password?
        true
      end

      def entry(username, password)
        @passwd[username] = password
        self
      end

      def user?(username)
        @passwd.key? username
      end

      def fetch_password(username)
        @passwd[username]
      end

      def self.build_from_conf(config)
        plain_src = self.new
        for user_entry in config
          plain_src.entry(user_entry['user'], user_entry['pass'])
        end

        plain_src
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
