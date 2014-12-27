# -*- coding: utf-8 -*-

module RIMS
  class Daemon
    class ExclusiveStatusFile
      def initialize(filename)
        @filename = filename
        @file = nil
        @is_locked = false
      end

      def open
        if (block_given?) then
          open
          begin
            r = yield
          ensure
            close
          end
          return r
        end

        begin
          @file = File.open(@filename, File::WRONLY | File::CREAT, 0640)
        rescue SystemCallError
          @fiile = File.open(@filename, File::WRONLY)
        end

        self
      end

      def close
        @file.close
        self
      end

      def locked?
        @is_locked
      end

      def should_be_locked
        unless (locked?) then
          raise "not locked: #{@filename}"
        end
        self
      end

      def should_not_be_locked
        if (locked?) then
          raise "already locked: #{@filename}"
        end
        self
      end

      def lock
        should_not_be_locked
        unless (@file.flock(File::LOCK_EX | File::LOCK_NB)) then
          raise "locked by another process: #{@filename}"
        end
        @is_locked = true
        self
      end

      def unlock
        should_be_locked
        @file.flock(File::LOCK_UN)
        @is_locked = false
        self
      end

      def synchronize
        lock
        begin
          yield
        ensure
          unlock
        end
      end

      def write(text)
        should_be_locked

        @file.truncate(0)
        @file.syswrite(text)

        self
      end
    end

    class ReadableStatusFile
      def initialize(filename)
        @filename = filename
        @file = nil
      end

      def open
        if (block_given?) then
          open
          begin
            r = yield
          ensure
            close
          end
          return r
        end

        @file = File.open(@filename, File::RDONLY)

        self
      end

      def close
        @file.close
        self
      end

      def locked?
        if (@file.flock(File::LOCK_EX | File::LOCK_NB)) then
          @file.flock(File::LOCK_UN)
          false
        else
          true
        end
      end

      def should_be_locked
        unless (locked?) then
          raise "not locked: #{@filename}"
        end
        self
      end

      def read
        should_be_locked
        @file.seek(0)
        @file.read
      end
    end

    def self.new_status_file(filename, exclusive: false)
      if (exclusive) then
        ExclusiveStatusFile.new(filename)
      else
        ReadableStatusFile.new(filename)
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
