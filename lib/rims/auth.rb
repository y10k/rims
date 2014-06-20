# -*- coding: utf-8 -*-

module RIMS
  class Authentication
    def initialize
      @passwd = {}
    end

    def entry(username, password)
      @passwd[username] = password
      self
    end

    def authenticate_login(username, password)
      if (@passwd.key? username) then
        if (@passwd[username] == password) then
          username
        end
      end
    end

    def authenticate_plain(client_response_data)
      authz_id, authc_id, password = client_response_data.split("\0", 3)
      if (authz_id.empty? || (authz_id == authc_id)) then
        if (@passwd.key? authc_id) then
          if (@passwd[authc_id] == password) then
            authc_id
          end
        end
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
