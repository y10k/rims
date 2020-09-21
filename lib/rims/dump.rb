# -*- coding: utf-8 -*-

require 'fileutils'

module RIMS
  module Dump
    PLUG_IN = {}                # :nodoc:

    class << self
      def add_plug_in(name, reader_class, writer_class)
        PLUG_IN[name] = {
          ReaderClass: reader_class,
          WriterClass: writer_class
        }
        self
      end

      def get_reader_plug_in(name)
        PLUG_IN.dig(name, :ReaderClass) or raise KeyError, "not found a dump plug-in: #{name}"
      end

      def get_writer_plug_in(name)
        PLUG_IN.dig(name, :WriterClass) or raise KeyError, "not found a dump plug-in: #{name}"
      end

      def plug_in_names
        PLUG_IN.keys
      end

      def dump_user(writer, config, meta_kvs_factory, text_kvs_factory, unique_user_id) # :yields: filename
        store_path = MailStore.key_value_store_path(config, unique_user_id)

        msg_kvs = text_kvs_factory.call((store_path + 'message').to_s)
        begin
          msg_kvs.each_pair do |name, value|
            filename = "#{unique_user_id}/message/#{name}"
            yield(filename) if block_given?
            writer.add(filename, value)
          end
        ensure
          msg_kvs.close
        end

        meta_kvs = meta_kvs_factory.call((store_path + 'meta').to_s)
        begin
          meta_kvs.each_pair do |name, value|
            filename = "#{unique_user_id}/meta/#{name}"
            yield(filename) if block_given?
            writer.add(filename, value)
          end

          meta_db = DB::Meta.new(meta_kvs)
          meta_db.each_mbox_id do |mbox_id|
            mbox_kvs = meta_kvs_factory.call((store_path + "mailbox_#{mbox_id}").to_s)
            begin
              mbox_kvs.each_pair do |name, value|
                filename = "#{unique_user_id}/mailbox_#{mbox_id}/#{name}"
                yield(filename) if block_given?
                writer.add(filename, value)
              end
            ensure
              mbox_kvs.close
            end
          end
        ensure
          meta_kvs.close
        end

        nil
      end

      def dump_all(writer, config, meta_kvs_factory, text_kvs_factory, &block) # :yields: filename
        MailStore.scan_unique_user_id(config) do |unique_user_id|
          dump_user(writer, config, meta_kvs_factory, text_kvs_factory, unique_user_id, &block)
        end

        nil
      end

      def restore(reader, config, meta_kvs_factory, text_kvs_factory, dry_run: false) # :yields: filename, valid
        kvs = nil
        kvs_open = lambda{
          saved_kvs_id = nil
          lambda{|unique_user_id, kvs_name|
            kvs_id = [ unique_user_id, kvs_name ]
            if (saved_kvs_id != kvs_id) then
              kvs&.close
              saved_kvs_id = kvs_id

              store_path = MailStore.key_value_store_path(config, unique_user_id)
              FileUtils.mkdir_p(store_path.to_s)

              kvs_factory = (kvs_name == 'message') ? text_kvs_factory : meta_kvs_factory
              kvs = kvs_factory.call((store_path + kvs_name).to_s)
            end
          }
        }.call

        begin
          for path, value, valid in reader
            yield(path, valid) if block_given?
            unique_user_id, kvs_name, entry_name = path.split('/', 3)
            unless (dry_run) then
              kvs_open.call(unique_user_id, kvs_name)
              kvs[entry_name] = value
            end
          end
        ensure
          kvs&.close
        end

        nil
      end
    end
  end

  class DumpReader
    def initialize(input)
      @input = input
    end

    def each                    # :yields: filename, content, valid
      raise NotImplementedError, 'abstract'
    end
  end

  class DumpWriter
    def initialize(output)
      @output = output
    end

    def add(filename, content)
      raise NotImplementedError, 'abstract'
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
