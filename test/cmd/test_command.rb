# -*- coding: utf-8 -*-

require 'fileutils'
require 'net/imap'
require 'open3'
require 'pathname'
require 'pp' if $DEBUG
require 'rims'
require 'set'
require 'test/unit'
require 'time'
require 'timeout'
require 'yaml'

module RIMS::Test
  class CommandTest < Test::Unit::TestCase
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
         '-r'                               => [ %W[ -f #{BASE_DIR}/config.yml -r prime ] ],
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
        begin
          stdout_thread = Thread.new{
            result = stdout.read
            puts [ :stdout, result ].pretty_inspect if $DEBUG
            result
          }
          stderr_thread = Thread.new{
            result = stderr.read
            puts [ :stderr, result ].pretty_inspect if $DEBUG
            result
          }

          imap = timeout(10) {
            begin
              Net::IMAP.new('localhost', 1430)
            rescue SystemCallError
              sleep(0.1)
              retry
            end
          }
          begin
            imap.noop
            imap.login('foo', 'foo')
            imap.noop
            imap.append('INBOX', 'HALO')
            imap.select('INBOX')
            imap.noop
            assert_equal([ 1 ], imap.search([ '*' ]))
            fetch_list = imap.fetch(1, %w[ RFC822 ])
            assert_equal([ 'HALO' ], fetch_list.map{|f| f.attr['RFC822'] })
            imap.logout
          ensure
            imap.disconnect
          end
        ensure
          Process.kill(:TERM, wait_thread.pid)
          stdout_result = stdout_thread.value if stdout_thread
          stderr_result = stderr_thread.value if stderr_thread
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
      begin
        pp [ stdout, stderr, status ] if $DEBUG
        assert_equal('', stdout)
        assert_equal('', stderr)
        assert_equal(0, status.exitstatus)

        imap = timeout(10) {
          begin
            Net::IMAP.new('localhost', 1430)
          rescue SystemCallError
            sleep(0.1)
            retry
          end
        }
        begin
          imap.noop
          imap.login('foo', 'foo')
          imap.noop
          imap.append('INBOX', 'HALO')
          imap.select('INBOX')
          imap.noop
          assert_equal([ 1 ], imap.search([ '*' ]))
          fetch_list = imap.fetch(1, %w[ RFC822 ])
          assert_equal([ 'HALO' ], fetch_list.map{|f| f.attr['RFC822'] })
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

    tls_dir = Pathname(__FILE__).parent.parent / "tls"
    TLS_CA_CERT     = tls_dir / 'ca.cert'
    TLS_SERVER_CERT = tls_dir / 'server_localhost.cert'
    TLS_SERVER_PKEY = tls_dir / 'server.priv_key'

    unless ([ TLS_CA_CERT, TLS_SERVER_CERT, TLS_SERVER_PKEY ].all?(&:file?)) then
      warn("warning: do `rake test_cert:make' to create TLS private key file and TLS certificate file for test.")
    end

    def run_server(use_ssl: false)
      config = {
        logging: {
          file: { level: 'debug' },
          stdout: { level: 'debug' },
          protocol: { level: 'info' }
        },
        server: {
          listen: 'localhost:1430'
        },
        authentication: {
          password_sources: [
            { type: 'plain',
              configuration: [
                { user: 'foo', pass: 'foo' },
                { user: '#postman', pass: '#postman' }
              ]
            }
          ]
        },
        authorization: {
          mail_delivery_user: '#postman'
        }
      }

      if (use_ssl) then
        FileUtils.cp(TLS_SERVER_PKEY.to_s, @base_dir.to_s)
        FileUtils.cp(TLS_SERVER_CERT.to_s, @base_dir.to_s)
        config.update({ openssl: {
                          ssl_context: %Q{
                            _.cert = X509::Certificate.new((base_dir / #{TLS_SERVER_CERT.basename.to_s.dump}).read)
                            _.key = PKey.read((base_dir / #{TLS_SERVER_PKEY.basename.to_s.dump}).read)
                          }
                        }
                      })
      end

      config_path = @base_dir + 'config.yml'
      config_path.write(RIMS::Service::Configuration.stringify_symbol(config).to_yaml)

      Open3.popen3('rims', 'server', '-f', config_path.to_s) {|stdin, stdout, stderr, wait_thread|
        begin
          stdout_thread = Thread.new{
            result = stdout.read
            puts [ :stdout, result ].pretty_inspect if $DEBUG
            result
          }
          stderr_thread = Thread.new{
            result = stderr.read
            puts [ :stderr, result ].pretty_inspect if $DEBUG
            result
          }

          imap = timeout(10) {
            begin
              Net::IMAP.new('localhost', 1430, use_ssl, TLS_CA_CERT.to_s)
            rescue SystemCallError
              sleep(0.1)
              retry
            end
          }
          begin
            imap.noop
            ret_val = yield(imap)
            imap.logout
          ensure
            imap.disconnect
          end
        ensure
          Process.kill(:TERM, wait_thread.pid)
          stdout_thread.join if stdout_thread
          stderr_thread.join if stderr_thread
        end

        server_status = wait_thread.value
        pp server_status if $DEBUG
        assert_equal(0, server_status.exitstatus)

        ret_val
      }
    end
    private :run_server

    data('-f'                         => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml ] ],
         '--config-yaml'              => [ false, 10, %W[ --config-yaml=#{BASE_DIR}/postman.yml ] ],
         '-v'                         => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml -v ] ],
         '--verbose'                  => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --verbose ] ],
         '--no-verbose'               => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --no-verbose ] ],
         '-n'                         => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml -n localhost ] ],
         '--host'                     => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --host=localhost ] ],
         '-o'                         => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml -o 1430 ] ],
         '--port'                     => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --port=1430 ] ],
         '-s,--ca-cert'               => [ true,  10, %W[ -f #{BASE_DIR}/postman.yml -s --ca-cert=#{TLS_CA_CERT} ] ],
         '-s,--ssl-params'            => [ true,  10, %W[ -f #{BASE_DIR}/postman.yml -s --ssl-params={"ca_file":#{TLS_CA_CERT.to_s.dump}} ] ],
         '--use-ssl,--ca-cert'        => [ true,  10, %W[ -f #{BASE_DIR}/postman.yml --use-ssl --ca-cert=#{TLS_CA_CERT} ] ],
         '--use-ssl,--ssl-params'     => [ true,  10, %W[ -f #{BASE_DIR}/postman.yml --use-ssl --ssl-params={"ca_file":#{TLS_CA_CERT.to_s.dump}} ] ],
         '--no-use-ssl'               => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --no-use-ssl ] ],
         '-u'                         => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml -u #postman ] ],
         '--username'                 => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --username #postman ] ],
         '-w'                         => [ false, 10, %W[ -w #postman ] ],
         '--password'                 => [ false, 10, %W[ --password=#postman ] ],
         '--auth-type=login'          => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --auth-type=login ] ],
         '--auth-type=plain'          => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --auth-type=plain ] ],
         '--auth-type=cram-md5'       => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --auth-type=cram-md5 ] ],
         '-m'                         => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml -m INBOX ] ],
         '--mailbox'                  => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --mailbox=INBOX ] ],
         '--store-flag-answered'      => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --store-flag-answered ], [ :Answered ] ],
         '--store-flag-flagged'       => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --store-flag-flagged  ], [ :Flagged  ] ],
         '--store-flag-deleted'       => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --store-flag-deleted  ], [ :Deleted  ] ],
         '--store-flag-seen'          => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --store-flag-seen     ], [ :Seen     ] ],
         '--store-flag-draft'         => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --store-flag-draft    ], [ :Draft    ] ],
         '--store-flag-all'           => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --store-flag-answered
                                                                                     --store-flag-flagged
                                                                                     --store-flag-deleted
                                                                                     --store-flag-seen
                                                                                     --store-flag-draft ], [ :Answered, :Flagged, :Deleted, :Seen, :Draft ] ],
         '--no-store-flag-answered'   => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --no-store-flag-answered ], [] ],
         '--no-store-flag-flagged'    => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --no-store-flag-flagged  ], [] ],
         '--no-store-flag-deleted'    => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --no-store-flag-deleted  ], [] ],
         '--no-store-flag-seen'       => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --no-store-flag-seen     ], [] ],
         '--no-store-flag-draft'      => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --no-store-flag-draft    ], [] ],
         '--look-for-date=servertime' => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --look-for-date=servertime ] ],
         '--look-for-date=localtime'  => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --look-for-date=localtime ] ],
         '--look-for-date=filetime'   => [ false, Time.parse('Mon, 01 Apr 2019 12:00:00 +0900'), %W[ -f #{BASE_DIR}/postman.yml --look-for-date=filetime ] ],
         '--look-for-date=mailheader' => [ false, Time.parse('Mon, 01 Apr 2019 09:00:00 +0900'), %W[ -f #{BASE_DIR}/postman.yml --look-for-date=mailheader ] ],
         '--imap-debug'               => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --imap-debug ] ],
         '--no-imap-debug'            => [ false, 10, %W[ -f #{BASE_DIR}/postman.yml --no-imap-debug ] ])
    def test_post_mail(data)
      use_ssl, expected_date, options, expected_flags = data

      config = @base_dir + 'postman.yml'
      config.write({ 'password' => '#postman' }.to_yaml)

      message = <<-'EOF'
From: foo@mail.example.com
To: bar@mail.example.com
Subject: HALO
Date: Mon, 01 Apr 2019 09:00:00 +0900

Hello world.
      EOF

      message_path = @base_dir + 'message.txt'
      message_path.write(message)

      t = Time.parse('Mon, 01 Apr 2019 12:00:00 +0900')
      message_path.utime(t, t)

      run_server(use_ssl: use_ssl) {|imap|
        stdout, stderr, status = Open3.capture3('rims', 'post-mail', *options, 'foo', message_path.to_s)
        pp [ stdout, stderr, status ] if $DEBUG
        assert_equal(0, status.exitstatus)

        imap.login('foo', 'foo')
        imap.examine('INBOX')   # for read-only
        fetch_list = imap.fetch(1, %w[ RFC822 INTERNALDATE FLAGS ])
        assert_equal(1, fetch_list.length)
        assert_equal(message, fetch_list[0].attr['RFC822'])

        internal_date = Time.parse(fetch_list[0].attr['INTERNALDATE'])
        case (expected_date)
        when Time
          assert_equal(expected_date, internal_date)
        when Integer
          t = Time.now
          delta_t = expected_date
          assert(((t - delta_t)..t).cover? internal_date)
        else
          flunk
        end

        flags = [ :Recent ].to_set
        flags += expected_flags if expected_flags
        assert_equal(flags, fetch_list[0].attr['FLAGS'].to_set)
      }
    end

    data('-f'                           => [ false, 10, %W[ -f #{BASE_DIR}/append.yml ] ],
         '--config-yaml'                => [ false, 10, %W[ --config-yaml=#{BASE_DIR}/append.yml ] ],
         '-v'                           => [ false, 10, %W[ -f #{BASE_DIR}/append.yml -v ] ],
         '--verbose'                    => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --verbose ] ],
         '--no-verbose'                 => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --no-verbose ] ],
         '-n'                           => [ false, 10, %W[ -f #{BASE_DIR}/append.yml -n localhost ] ],
         '--host'                       => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --host=localhost ] ],
         '-o'                           => [ false, 10, %W[ -f #{BASE_DIR}/append.yml -o 1430 ] ],
         '--port'                       => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --port=1430 ] ],
         '-s,--ca-cert'                 => [ true,  10, %W[ -f #{BASE_DIR}/append.yml -s --ca-cert=#{TLS_CA_CERT} ] ],
         '-s,--ssl-params'              => [ true,  10, %W[ -f #{BASE_DIR}/append.yml -s --ssl-params={"ca_file":#{TLS_CA_CERT.to_s.dump}} ] ],
         '--use-ssl,--ca-cert'          => [ true,  10, %W[ -f #{BASE_DIR}/append.yml --use-ssl --ca-cert=#{TLS_CA_CERT} ] ],
         '--use-ssl,--ssl-params'       => [ true,  10, %W[ -f #{BASE_DIR}/append.yml --use-ssl --ssl-params={"ca_file":#{TLS_CA_CERT.to_s.dump}} ] ],
         '--no-use-ssl'                 => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --no-use-ssl ] ],
         '-u,-w,-o'                     => [ false, 10, %W[ -u foo -w foo -o 1430 ] ],
         '--username,--password,--port' => [ false, 10, %W[ --username=foo --password=foo --port=1430 ] ],
         '--auth-type=login'            => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --auth-type=login ] ],
         '--auth-type=plain'            => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --auth-type=plain ] ],
         '--auth-type=cram-md5'         => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --auth-type=cram-md5 ] ],
         '-m'                           => [ false, 10, %W[ -f #{BASE_DIR}/append.yml -m INBOX ] ],
         '--mailbox'                    => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --mailbox=INBOX ] ],
         '--store-flag-answered'        => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --store-flag-answered ], [ :Answered ] ],
         '--store-flag-flagged'         => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --store-flag-flagged  ], [ :Flagged  ] ],
         '--store-flag-deleted'         => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --store-flag-deleted  ], [ :Deleted  ] ],
         '--store-flag-seen'            => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --store-flag-seen     ], [ :Seen     ] ],
         '--store-flag-draft'           => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --store-flag-draft    ], [ :Draft    ] ],
         '--store-flag-all'             => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --store-flag-answered
                                                                                      --store-flag-flagged
                                                                                      --store-flag-deleted
                                                                                      --store-flag-seen
                                                                                      --store-flag-draft ], [ :Answered, :Flagged, :Deleted, :Seen, :Draft ] ],
         '--no-store-flag-answered'     => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --no-store-flag-answered ], [] ],
         '--no-store-flag-flagged'      => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --no-store-flag-flagged  ], [] ],
         '--no-store-flag-deleted'      => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --no-store-flag-deleted  ], [] ],
         '--no-store-flag-seen'         => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --no-store-flag-seen     ], [] ],
         '--no-store-flag-draft'        => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --no-store-flag-draft    ], [] ],
         '--look-for-date=servertime'   => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --look-for-date=servertime ] ],
         '--look-for-date=localtime'    => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --look-for-date=localtime ] ],
         '--look-for-date=filetime'     => [ false, Time.parse('Mon, 01 Apr 2019 12:00:00 +0900'), %W[ -f #{BASE_DIR}/append.yml --look-for-date=filetime ] ],
         '--look-for-date=mailheader'   => [ false, Time.parse('Mon, 01 Apr 2019 09:00:00 +0900'), %W[ -f #{BASE_DIR}/append.yml --look-for-date=mailheader ] ],
         '--imap-debug'                 => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --imap-debug ] ],
         '--no-imap-debug'              => [ false, 10, %W[ -f #{BASE_DIR}/append.yml --no-imap-debug ] ])
    def test_imap_append(data)
      use_ssl, expected_date, options, expected_flags = data

      config = @base_dir + 'append.yml'
      config.write({ 'imap_port' => 1430,
                     'username' => 'foo',
                     'password' => 'foo'
                   }.to_yaml)

      message = <<-'EOF'
From: foo@mail.example.com
To: bar@mail.example.com
Subject: HALO
Date: Mon, 01 Apr 2019 09:00:00 +0900

Hello world.
      EOF

      message_path = @base_dir + 'message.txt'
      message_path.write(message)

      t = Time.parse('Mon, 01 Apr 2019 12:00:00 +0900')
      message_path.utime(t, t)

      run_server(use_ssl: use_ssl) {|imap|
        stdout, stderr, status = Open3.capture3('rims', 'imap-append', *options, message_path.to_s)
        pp [ stdout, stderr, status ] if $DEBUG
        assert_equal(0, status.exitstatus)

        imap.login('foo', 'foo')
        imap.examine('INBOX')   # for read-only
        fetch_list = imap.fetch(1, %w[ RFC822 INTERNALDATE FLAGS ])
        assert_equal(1, fetch_list.length)
        assert_equal(message, fetch_list[0].attr['RFC822'])

        internal_date = Time.parse(fetch_list[0].attr['INTERNALDATE'])
        case (expected_date)
        when Time
          assert_equal(expected_date, internal_date)
        when Integer
          t = Time.now
          delta_t = expected_date
          assert(((t - delta_t)..t).cover? internal_date)
        else
          flunk
        end

        flags = [ :Recent ].to_set
        flags += expected_flags if expected_flags
        assert_equal(flags, fetch_list[0].attr['FLAGS'].to_set)
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
