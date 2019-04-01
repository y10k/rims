# -*- coding: utf-8 -*-

require 'net/imap'
require 'open3'
require 'pathname'
require 'pp' if $DEBUG
require 'rims'
require 'test/unit'
require 'timeout'
require 'yaml'

module RIMS::Test
  class CmdTest < Test::Unit::TestCase
    include Timeout

    BASE_DIR = 'cmd_base_dir'

    def setup
      @base_dir = Pathname(BASE_DIR)
      @base_dir.mkpath
    end

    def teardown
      @base_dir.rmtree
    end

    def test_rims_no_args
      stdout, stderr, status = Open3.capture3('rims')
      pp [ stdout, stderr, status ] if $DEBUG

      assert_equal(1, status.exitstatus)
      assert(! stdout.empty?)
      assert_equal('', stderr)
    end

    def test_help
      stdout, stderr, status = Open3.capture3('rims', 'help')
      pp [ stdout, stderr, status ] if $DEBUG

      assert_equal(0, status.exitstatus)
      assert(! stdout.empty?)
      assert_not_match(/debug/, stdout)
      assert_equal('', stderr)

      stdout, stderr, status = Open3.capture3('rims', 'help', '--show-debug-command')
      pp [ stdout, stderr, status ] if $DEBUG

      assert_equal(0, status.exitstatus)
      assert(! stdout.empty?)
      assert_match(/debug/, stdout)
      assert_equal('', stderr)
    end

    def test_version
      stdout, stderr, status = Open3.capture3('rims', 'version')
      pp [ stdout, stderr, status ] if $DEBUG

      assert_equal(0, status.exitstatus)
      assert_include(stdout, RIMS::VERSION)
      assert_equal('', stderr)
    end

    data('-f'                               => [ %W[ -f #{BASE_DIR}/config.yml ] ],
         '--config-yaml'                    => [ %W[ --config-yaml #{BASE_DIR}/config.yml ] ],
         '-I'                               => [ %W[ -f #{BASE_DIR}/config.yml -I prime ] ],
         '--required-feature'               => [ %W[ -f #{BASE_DIR}/config.yml --required-feature=prime ] ],
         '-d,--passwd-file'                 => [ %W[ -d #{BASE_DIR} --passwd-file=plain:passwd.yml ] ],
         '--base-dir,--passwd-file'         => [ %W[ --base-dir=#{BASE_DIR} --passwd-file=plain:passwd.yml ] ],
         '--log-file'                       => [ %W[ -f #{BASE_DIR}/config.yml --log-file=server.log ] ],
         '-l'                               => [ %W[ -f #{BASE_DIR}/config.yml -l debug ] ],
         '--log-level'                      => [ %W[ -f #{BASE_DIR}/config.yml --log-level=debug ] ],
         '--log-shift-age'                  => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-age=10 ] ],
         '--log-shift-daily'                => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-age-daily ] ],
         '--log-shift-weekly'               => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-age-weekly ] ],
         '--log-shift-monthly'              => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-age-monthly ] ],
         '--log-shift-size'                 => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-size=1048576 ] ],
         '-v'                               => [ %W[ -f #{BASE_DIR}/config.yml -v debug ] ],
         '--log-stdout'                     => [ %W[ -f #{BASE_DIR}/config.yml --log-stdout=debug ] ],
         '--protocol-log-file'              => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-file=imap.log ] ],
         '-p'                               => [ %W[ -f #{BASE_DIR}/config.yml -p info ] ],
         '--protocol-log-level'             => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-level=info ] ],
         '--protocol-log-shift-age'         => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-age=10 ] ],
         '--protocol-log-shift-age-daily'   => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-age-daily ] ],
         '--protocol-log-shift-age-weekly'  => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-age-weekly ] ],
         '--protocol-log-shift-age-monthly' => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-age-monthly ] ],
         '--protocol-log-shift-size'        => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-size=1048576 ] ],
         '--daemonize'                      => [ %W[ -f #{BASE_DIR}/config.yml --daemonize ] ],
         '--no-daemonize'                   => [ %W[ -f #{BASE_DIR}/config.yml --no-daemonize ] ],
         '--daemon-debug'                   => [ %W[ -f #{BASE_DIR}/config.yml --daemon-debug ] ],
         '--no-daemon-debug'                => [ %W[ -f #{BASE_DIR}/config.yml --no-daemon-debug ] ],
         '--status-file'                    => [ %W[ -f #{BASE_DIR}/config.yml --status-file=status.yml ] ],
         '--privilege-user'                 => [ %W[ -f #{BASE_DIR}/config.yml --privilege-user=#{Process::UID.eid} ] ],
         '--privilege-group'                => [ %W[ -f #{BASE_DIR}/config.yml --privilege-group=#{Process::GID.eid} ] ],
         '-s'                               => [ %W[ -f #{BASE_DIR}/config.yml -s localhost:1430 ] ],
         '--listen'                         => [ %W[ -f #{BASE_DIR}/config.yml --listen=localhost:1430 ] ],
         '--accept-polling-timeout'         => [ %W[ -f #{BASE_DIR}/config.yml --accept-polling-timeout=0.1 ] ],
         '--thread-num'                     => [ %W[ -f #{BASE_DIR}/config.yml --thread-num=4 ] ],
         '--thread-queue-size'              => [ %W[ -f #{BASE_DIR}/config.yml --thread-queue-size=128 ] ],
         '--thread-queue-polling-timeout'   => [ %W[ -f #{BASE_DIR}/config.yml --thread-queue-polling-timeout=0.1 ] ],
         '--send-buffer-limit'              => [ %W[ -f #{BASE_DIR}/config.yml --send-buffer-limit=131072 ] ],
         '--read-lock-timeout'              => [ %W[ -f #{BASE_DIR}/config.yml --read-lock-timeout=10 ] ],
         '--write-lock-timeout'             => [ %W[ -f #{BASE_DIR}/config.yml --write-lock-timeout=10 ] ],
         '--clenup-write-lock-timeout'      => [ %W[ -f #{BASE_DIR}/config.yml --write-lock-timeout=5 ] ],
         '--meta-kvs-type'                  => [ %W[ -f #{BASE_DIR}/config.yml --meta-kvs-type=gdbm ] ],
         '--meta-kvs-config'                => [ %W[ -f #{BASE_DIR}/config.yml --meta-kvs-config={} ] ],
         '--use-meta-kvs-checksum'          => [ %W[ -f #{BASE_DIR}/config.yml --use-meta-kvs-checksum ] ],
         '--no-use-meta-kvs-checksum'       => [ %W[ -f #{BASE_DIR}/config.yml --no-use-meta-kvs-checksum ] ],
         '--text-kvs-type'                  => [ %W[ -f #{BASE_DIR}/config.yml --text-kvs-type=gdbm ] ],
         '--text-kvs-config'                => [ %W[ -f #{BASE_DIR}/config.yml --text-kvs-config={} ] ],
         '--use-text-kvs-checksum'          => [ %W[ -f #{BASE_DIR}/config.yml --use-text-kvs-checksum ] ],
         '--no-use-text-kvs-checksum'       => [ %W[ -f #{BASE_DIR}/config.yml --no-use-text-kvs-checksum ] ],
         '--auth-hostname'                  => [ %W[ -f #{BASE_DIR}/config.yml --auth-hostname=imap.example.com ] ],
         '--passwd-config'                  => [ %W[ -d #{BASE_DIR} --passwd-config=plain:[{"user":"foo","pass":"foo"}] ] ],
         '--mail-delivery-user'             => [ %W[ -f #{BASE_DIR}/config.yml --mail-delivery-user=postman ] ],

         # deplicated options
         'deplicated:--imap-host'           => [ %W[ -f #{BASE_DIR}/config.yml --imap-host=localhost ], true ],
         'deplicated:--imap-port'           => [ %W[ -f #{BASE_DIR}/config.yml --imap-port=1430      ], true ],
         'deplicated:--ip-addr'             => [ %W[ -f #{BASE_DIR}/config.yml --ip-addr=0.0.0.0     ], true ],
         'deplicated:--ip-port'             => [ %W[ -f #{BASE_DIR}/config.yml --ip-port=1430        ], true ],
         'deplicated:--kvs-type'            => [ %W[ -f #{BASE_DIR}/config.yml --kvs-type=gdbm       ], true ],
         'deplicated:--use-kvs-cksum'       => [ %W[ -f #{BASE_DIR}/config.yml --use-kvs-cksum       ], true ],
         'deplicated:--no-use-kvs-cksum'    => [ %W[ -f #{BASE_DIR}/config.yml --no-use-kvs-cksum    ], true ],
         'deplicated:-u,-w'                 => [ %W[ -d #{BASE_DIR} -u foo -w foo                    ], true ],
         'deplicated:--username,--password' => [ %W[ -d #{BASE_DIR} --username=foo --password=foo    ], true ])
    def test_server(data)
      options, deplicated = data

      (@base_dir + 'passwd.yml').write([ { 'user' => 'foo', 'pass' => 'foo' } ].to_yaml)
      (@base_dir + 'config.yml').write({ 'authentication' => {
                                           'password_sources' => [
                                             { 'type' => 'plain',
                                               'configuration_file' => 'passwd.yml'
                                             }
                                           ]
                                         }
                                       }.to_yaml)

      Open3.popen3('rims', 'server', *options) {|stdin, stdout, stderr, wait_thread|
        stdout_thread = Thread.new{
          result = stdout.read
          pp [ :stdout, result ] if $DEBUG
          result
        }
        stderr_thread = Thread.new{
          result = stderr.read
          pp [ :stderr, result ] if $DEBUG
          result
        }

        begin
          begin
            imap = timeout(10) {
              begin
                Net::IMAP.new('localhost', 1430)
              rescue SystemCallError
                sleep(0.1)
                retry
              end
            }

            imap.noop
            imap.login('foo', 'foo')
            imap.noop
            imap.append('INBOX', 'HALO')
            imap.select('INBOX')
            imap.noop
            assert_equal([ 1 ], imap.search([ '*' ]))
            fetch_data = imap.fetch(1, %w[ RFC822 ])
            assert_equal([ 'HALO' ], fetch_data.map{|f| f.attr['RFC822'] })
            imap.logout
          ensure
            imap.disconnect
          end
        ensure
          Process.kill(:TERM, wait_thread.pid)
          stdout_result = stdout_thread.value
          stderr_result = stderr_thread.value
        end

        server_status = wait_thread.value
        pp server_status if $DEBUG
        assert_equal(0, server_status.exitstatus)

        assert(! stdout_result.empty?)
        if (deplicated) then
          assert_match(/^warning:/, stderr_result)
        else
          assert_equal('', stderr_result)
        end
      }
    end

    def test_daemon_status_stopped
      stdout, stderr, status = Open3.capture3('rims', 'daemon', 'status', '-d', @base_dir.to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      assert_match(/stopped/, stdout)
      assert_equal('', stderr)
      assert_equal(1, status.exitstatus)

      %w[ -v --verbose ].each do |option|
        stdout, stderr, status = Open3.capture3('rims', 'daemon', option, 'status', '-d', @base_dir.to_s, "status verbose option: #{option}")
        pp [ stdout, stderr, status ] if $DEBUG
        assert_match(/stopped/, stdout)
        assert_equal('', stderr)
        assert_equal(1, status.exitstatus)
      end

      %w[ -q --quiet ].each do |option|
        stdout, stderr, status = Open3.capture3('rims', 'daemon', option, 'status', '-d', @base_dir.to_s, "status quiet option: #{option}")
        pp [ stdout, stderr, status ] if $DEBUG
        assert_equal('', stdout)
        assert_equal('', stderr)
        assert_equal(1, status.exitstatus)
      end

      stdout, stderr, status = Open3.capture3('rims', 'daemon', '--status-code', 'status', '-d', @base_dir.to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      assert_match(/stopped/, stdout)
      assert_equal('', stderr)
      assert_equal(1, status.exitstatus)

      stdout, stderr, status = Open3.capture3('rims', 'daemon', '--no-status-code', 'status', '-d', @base_dir.to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      assert_match(/stopped/, stdout)
      assert_equal('', stderr)
      assert_equal(0, status.exitstatus)
    end

    def test_daemon_run
      # need for riser 0.1.7 or later to close stdin/stdout/stderr of daemon process
      stdout, stderr, status = Open3.capture3('rims', 'daemon', 'start', '-d', @base_dir.to_s, '--passwd-config=plain:[{"user":"foo","pass":"foo"}]')
      pp [ stdout, stderr, status ] if $DEBUG
      assert_equal('', stdout)
      assert_equal('', stderr)
      assert_equal(0, status.exitstatus)

      begin
        begin
          imap = timeout(10) {
            begin
              Net::IMAP.new('localhost', 1430)
            rescue SystemCallError
              sleep(0.1)
              retry
            end
          }

          imap.noop
          imap.login('foo', 'foo')
          imap.noop
          imap.append('INBOX', 'HALO')
          imap.select('INBOX')
          imap.noop
          assert_equal([ 1 ], imap.search([ '*' ]))
          fetch_data = imap.fetch(1, %w[ RFC822 ])
          assert_equal([ 'HALO' ], fetch_data.map{|f| f.attr['RFC822'] })
          imap.logout
        ensure
          imap.disconnect
        end

        stdout, stderr, status = Open3.capture3('rims', 'daemon', 'status', '-d', @base_dir.to_s)
        pp [ stdout, stderr, status ] if $DEBUG
        assert_match(/running/, stdout)
        assert_equal('', stderr)
        assert_equal(0, status.exitstatus)

        %w[ -v --verbose ].each do |option|
          stdout, stderr, status = Open3.capture3('rims', 'daemon', option, 'status', '-d', @base_dir.to_s, "status verbose option: #{option}")
          pp [ stdout, stderr, status ] if $DEBUG
          assert_match(/running/, stdout)
          assert_equal('', stderr)
          assert_equal(0, status.exitstatus)
        end

        %w[ -q --quiet ].each do |option|
          stdout, stderr, status = Open3.capture3('rims', 'daemon', option, 'status', '-d', @base_dir.to_s, "status quiet option: #{option}")
          pp [ stdout, stderr, status ] if $DEBUG
          assert_equal('', stdout)
          assert_equal('', stderr)
          assert_equal(0, status.exitstatus)
        end

        stdout, stderr, status = Open3.capture3('rims', 'daemon', '--status-code', 'status', '-d', @base_dir.to_s)
        pp [ stdout, stderr, status ] if $DEBUG
        assert_match(/running/, stdout)
        assert_equal('', stderr)
        assert_equal(0, status.exitstatus)

        stdout, stderr, status = Open3.capture3('rims', 'daemon', '--no-status-code', 'status', '-d', @base_dir.to_s)
        pp [ stdout, stderr, status ] if $DEBUG
        assert_match(/running/, stdout)
        assert_equal('', stderr)
        assert_equal(0, status.exitstatus)
      ensure
        stdout, stderr, status = Open3.capture3('rims', 'daemon', 'stop', '-d', @base_dir.to_s)
        pp [ stdout, stderr, status ] if $DEBUG
      end
      assert_equal('', stdout)
      assert_equal('', stderr)
      assert_equal(0, status.exitstatus)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
