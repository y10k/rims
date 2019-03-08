# -*- coding: utf-8 -*-

require 'pathname'
require 'riser'
require 'yaml'

module RIMS
  class Service
    class Configuration
      class << self
        def stringify_symbol(collection)
          case (collection)
          when Hash
            Hash[collection.map{|key, value| [ stringify_symbol(key), stringify_symbol(value) ] }]
          when Array
            collection.map{|i| stringify_symbol(i) }
          else
            case (value = collection)
            when Symbol
              value.to_s
            else
              value
            end
          end
        end

        def update(dest, other)
          case (dest)
          when Hash
            unless (other.is_a? Hash) then
              raise ArgumentError, 'hash can only be updated with hash.'
            end
            for key, value in other
              dest[key] = update(dest[key], value)
            end
            dest
          when Array
            if (other.is_a? Array) then
              dest.concat(other)
            else
              other
            end
          else
            other
          end
        end

        def get_configuration(collection, base_dir)
          if ((collection.key? 'configuration') && (collection.key? 'configuration_file')) then
            raise KeyError, 'configuration conflict: configuration, configuraion_file'
          end

          if (collection.key? 'configuration') then
            collection['configuration']
          elsif (collection.key? 'configuration_file') then
            configuration_file_path = Pathname(collection['configuration_file'])
            if (configuration_file_path.relative?) then
              configuration_file_path = base_dir + configuration_file_path # expect base_dir to be Pathname
            end
            YAML.load_file(configuration_file_path.to_s)
          else
            {}
          end
        end
      end

      def initialize
        @config = {}
      end

      def load(config, load_path=nil)
        stringified_config = self.class.stringify_symbol(config)
        if (stringified_config.key? 'base_dir') then
          base_dir = Pathname(stringified_config['base_dir'])
          if (load_path && base_dir.relative?) then
            stringified_config['base_dir'] = Pathname(load_path) + base_dir
          else
            stringified_config['base_dir'] = base_dir
          end
        elsif (load_path) then
          stringified_config['base_dir'] = Pathname(load_path)
        end
        self.class.update(@config, stringified_config)

        self
      end

      # configuration example.
      #   required_features:
      #     - rims/qdbm
      #     - rims/passwd/ldap
      #   server:
      #     accept_polling_timeout_seconds: 0.1
      #     thread_num: 20
      #     thread_queue_size: 20
      #     thread_queue_polling_timeout_seconds: 0.1
      def load_yaml(path)
        load(YAML.load_file(path), File.dirname(path))
        self
      end

      def require_features
        if (feature_list = @config.dig('required_features')) then
          for feature in feature_list
            require(feature)
          end
        end

        nil
      end

      def get_required_features
        @config.dig('required_features') || []
      end

      def base_dir
        @config['base_dir'] or raise KeyError, 'not defined base_dir.'
      end

      def get_configuration(collection)
        self.class.get_configuration(collection, base_dir)
      end
      private :get_configuration

      def accept_polling_timeout_seconds
        @config.dig('server', 'accept_polling_timeout_seconds') || 0.1
      end

      def process_num
        0                       # not yet supported multi-process server configuration.
      end

      def process_queue_size
        20
      end

      def process_queue_polling_timeout_seconds
        0.1
      end

      def process_send_io_polling_timeout_seconds
        0.1
      end

      def thread_num
        @config.dig('server', 'thread_num') || 20
      end

      def thread_queue_size
        @config.dig('server', 'thread_queue_size') || 20
      end

      def thread_queue_polling_timeout_seconds
        @config.dig('server', 'thread_queue_polling_timeout_seconds') || 0.1
      end
    end

    def initialize(config)
      @config = config
    end

    def setup(server)
      server.accept_polling_timeout_seconds          = @config.accept_polling_timeout_seconds
      server.process_num                             = @config.process_num
      server.process_queue_size                      = @config.process_queue_size
      server.process_queue_polling_timeout_seconds   = @config.process_queue_polling_timeout_seconds
      server.process_send_io_polling_timeout_seconds = @config.process_send_io_polling_timeout_seconds
      server.thread_num                              = @config.thread_num
      server.thread_queue_size                       = @config.thread_queue_size
      server.thread_queue_polling_timeout_seconds    = @config.thread_queue_polling_timeout_seconds
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
