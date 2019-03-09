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
      #   storage:
      #     meta_key_value_store:
      #       type: qdbm_depot
      #       configuration:
      #         bnum 1200000
      #       use_checksum: true
      #     text_key_value_store:
      #       type: qdbm_curia
      #       configuration_file: text_kvs_config.yml
      #       use_checksum: true
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

      KeyValueStoreFactoryBuilderParams = Struct.new(:origin_type, :origin_config, :middleware_list)
      class KeyValueStoreFactoryBuilderParams
        def build_factory
          builder = KeyValueStore::FactoryBuilder.new
          builder.open{|name| origin_type.open_with_conf(name, origin_config) }
          for middleware in middleware_list
            builder.use(middleware)
          end
          builder.factory
        end
      end

      def make_key_value_store_params(collection)
        kvs_params = KeyValueStoreFactoryBuilderParams.new
        kvs_params.origin_type = KeyValueStore::FactoryBuilder.get_plug_in(collection['type'] || 'gdbm')
        kvs_params.origin_config = get_configuration(collection)

        if (collection.key? 'use_checksum') then
          use_checksum = collection['use_checksum']
        else
          use_checksum = true   # default
        end

        kvs_params.middleware_list = []
        kvs_params.middleware_list << Checksum_KeyValueStore if use_checksum

        kvs_params
      end
      private :make_key_value_store_params

      def make_meta_key_value_store_params
        make_key_value_store_params(@config.dig('storage', 'meta_key_value_store') || {})
      end

      def make_text_key_value_store_params
        make_key_value_store_params(@config.dig('storage', 'text_key_value_store') || {})
      end

      def make_key_value_store_path(mailbox_data_structure_version, unique_user_id)
        if (mailbox_data_structure_version.empty?) then
          raise ArgumentError, 'too short mailbox data structure version.'
        end
        if (unique_user_id.length <= 2) then
          raise ArgumentError, 'too short unique user ID.'
        end

        bucket_dir_name = unique_user_id[0..1]
        store_dir_name = unique_user_id[2..-1]

        base_dir + mailbox_data_structure_version + bucket_dir_name + store_dir_name
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
