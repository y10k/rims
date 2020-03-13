# -*- coding: utf-8 -*-

require 'fileutils'
require 'logger'
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

    def imap_connect(use_ssl=false)
      imap = timeout(10) {
        begin
          Net::IMAP.new('localhost', 1430, use_ssl, TLS_CA_CERT.to_s)
        rescue SystemCallError
          sleep(0.1)
          retry
        end
      }
      begin
        yield(imap)
      ensure
        imap.disconnect
      end
    end
    private :imap_connect

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
      assert_equal(RIMS::VERSION, stdout.chomp)
      assert_equal('', stderr)
    end

    data(
      # base:
      '-f'                               => [ %W[ -f #{BASE_DIR}/config.yml ] ],
      '--config-yaml'                    => [ %W[ --config-yaml #{BASE_DIR}/config.yml ] ],
      '-r'                               => [ %W[ -f #{BASE_DIR}/config.yml -r prime ] ],
      '--required-feature'               => [ %W[ -f #{BASE_DIR}/config.yml --required-feature=prime ] ],
      '-d,--passwd-file'                 => [ %W[ -d #{BASE_DIR} --passwd-file=plain:passwd.yml ] ],
      '--base-dir,--passwd-file'         => [ %W[ --base-dir=#{BASE_DIR} --passwd-file=plain:passwd.yml ] ],

      # logging file:
      '--log-file'                       => [ %W[ -f #{BASE_DIR}/config.yml --log-file=server.log ] ],
      '-l'                               => [ %W[ -f #{BASE_DIR}/config.yml -l debug ] ],
      '--log-level'                      => [ %W[ -f #{BASE_DIR}/config.yml --log-level=debug ] ],
      '--log-shift-age'                  => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-age=10 ] ],
      '--log-shift-daily'                => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-age-daily ] ],
      '--log-shift-weekly'               => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-age-weekly ] ],
      '--log-shift-monthly'              => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-age-monthly ] ],
      '--log-shift-size'                 => [ %W[ -f #{BASE_DIR}/config.yml --log-shift-size=1048576 ] ],

      # logging stdout:
      '-v'                               => [ %W[ -f #{BASE_DIR}/config.yml -v debug ] ],
      '--log-stdout'                     => [ %W[ -f #{BASE_DIR}/config.yml --log-stdout=debug ] ],

      # logging protocol:
      '--protocol-log-file'              => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-file=imap.log ] ],
      '-p'                               => [ %W[ -f #{BASE_DIR}/config.yml -p info ] ],
      '--protocol-log-level'             => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-level=info ] ],
      '--protocol-log-shift-age'         => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-age=10 ] ],
      '--protocol-log-shift-age-daily'   => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-age-daily ] ],
      '--protocol-log-shift-age-weekly'  => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-age-weekly ] ],
      '--protocol-log-shift-age-monthly' => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-age-monthly ] ],
      '--protocol-log-shift-size'        => [ %W[ -f #{BASE_DIR}/config.yml --protocol-log-shift-size=1048576 ] ],

      # daemon:
      '--daemonize'                      => [ %W[ -f #{BASE_DIR}/config.yml --daemonize ] ],
      '--no-daemonize'                   => [ %W[ -f #{BASE_DIR}/config.yml --no-daemonize ] ],
      '--daemon-debug'                   => [ %W[ -f #{BASE_DIR}/config.yml --daemon-debug ] ],
      '--no-daemon-debug'                => [ %W[ -f #{BASE_DIR}/config.yml --no-daemon-debug ] ],
      '--daemon-umask'                   => [ %W[ -f #{BASE_DIR}/config.yml --daemon-umask=0022 ] ],
      '--status-file'                    => [ %W[ -f #{BASE_DIR}/config.yml --status-file=status.yml ] ],
      '--privilege-user'                 => [ %W[ -f #{BASE_DIR}/config.yml --privilege-user=#{Process::UID.eid} ] ],
      '--privilege-group'                => [ %W[ -f #{BASE_DIR}/config.yml --privilege-group=#{Process::GID.eid} ] ],

      # server:
      '-s'                                              => [ %W[ -f #{BASE_DIR}/config.yml -s localhost:1430 ] ],
      '--listen'                                        => [ %W[ -f #{BASE_DIR}/config.yml --listen=localhost:1430 ] ],
      '--accept-polling-timeout'                        => [ %W[ -f #{BASE_DIR}/config.yml --accept-polling-timeout=0.1 ] ],
      '--process-num'                                   => [ %W[ -f #{BASE_DIR}/config.yml --process-num=4 ] ],
      '--process-num,--process-queue-size'              => [ %W[ -f #{BASE_DIR}/config.yml --process-num=4 --process-queue-size=64 ] ],
      '--process-num,--process-queue-polling-timeout'   => [ %W[ -f #{BASE_DIR}/config.yml --process-num=4 --process-queue-polling-timeout=0.1 ] ],
      '--process-num,--process-send-io-polling-timeout' => [ %W[ -f #{BASE_DIR}/config.yml --process-num=4 --process-send-io-polling-timeout=0.1 ] ],
      '--thread-num'                                    => [ %W[ -f #{BASE_DIR}/config.yml --thread-num=4 ] ],
      '--thread-queue-size'                             => [ %W[ -f #{BASE_DIR}/config.yml --thread-queue-size=128 ] ],
      '--thread-queue-polling-timeout'                  => [ %W[ -f #{BASE_DIR}/config.yml --thread-queue-polling-timeout=0.1 ] ],

      # connection:
      '--send-buffer-limit'              => [ %W[ -f #{BASE_DIR}/config.yml --send-buffer-limit=131072 ] ],
      '--read-polling-interval'          => [ %W[ -f #{BASE_DIR}/config.yml --read-polling-interval=5 ] ],
      '--command-wait-timeout'           => [ %W[ -f #{BASE_DIR}/config.yml --command-wait-timeout=3600 ] ],

      # protocol:
      '--line-length-limit'              => [ %W[ -f #{BASE_DIR}/config.yml --line-length-limit=16384 ] ],
      '--literal-size-limit'             => [ %W[ -f #{BASE_DIR}/config.yml --literal-size-limit=16777216 ] ],

      # charset aliases:
      '--use-default-charset-aliases'    => [ %W[ -f #{BASE_DIR}/config.yml --use-default-charset-aliases ] ],
      '--no-use-default-charset-aliases' => [ %W[ -f #{BASE_DIR}/config.yml --no-use-default-charset-aliases ] ],
      '--add-charset-alias'              => [ %W[ -f #{BASE_DIR}/config.yml --no-use-default-charset-aliases --add-charset-alias=iso-2022-jp,CP50221 ] ],

      # charset convert_options:
      '--replace-charset-invalid'        => [ %W[ -f #{BASE_DIR}/config.yml --replace-charset-invalid ] ],
      '--no-replace-charset-invalid'     => [ %W[ -f #{BASE_DIR}/config.yml --no-replace-charset-invalid ] ],
      '--replace-charset-undef'          => [ %W[ -f #{BASE_DIR}/config.yml --replace-charset-undef ] ],
      '--no-replace-charset-undef'       => [ %W[ -f #{BASE_DIR}/config.yml --no-replace-charset-undef ] ],
      '--charset-replaced-mark'          => [ %W[ -f #{BASE_DIR}/config.yml --charset-replaced-mark=? ] ],

      # drb_services:
      '--drb-process-num'                => [ %W[ -f #{BASE_DIR}/config.yml --drb-process-num=4 ] ],
      '--drb-load-limit'                 => [ %W[ -f #{BASE_DIR}/config.yml --drb-load-limit=134217728 ] ],

      # drb_services engine:
      '--bulk-response-count'            => [ %W[ -f #{BASE_DIR}/config.yml --bulk-response-count=128 ] ],
      '--bulk-response-size'             => [ %W[ -f #{BASE_DIR}/config.yml --bulk-response-size=33554432 ] ],
      '--read-lock-timeout'              => [ %W[ -f #{BASE_DIR}/config.yml --read-lock-timeout=10 ] ],
      '--write-lock-timeout'             => [ %W[ -f #{BASE_DIR}/config.yml --write-lock-timeout=10 ] ],
      '--clenup-write-lock-timeout'      => [ %W[ -f #{BASE_DIR}/config.yml --write-lock-timeout=5 ] ],

      # storage meta_key_value_store:
      '--meta-kvs-type'                  => [ %W[ -f #{BASE_DIR}/config.yml --meta-kvs-type=gdbm ] ],
      '--meta-kvs-config'                => [ %W[ -f #{BASE_DIR}/config.yml --meta-kvs-config={} ] ],
      '--use-meta-kvs-checksum'          => [ %W[ -f #{BASE_DIR}/config.yml --use-meta-kvs-checksum ] ],
      '--no-use-meta-kvs-checksum'       => [ %W[ -f #{BASE_DIR}/config.yml --no-use-meta-kvs-checksum ] ],

      # storage text_key_value_store:
      '--text-kvs-type'                  => [ %W[ -f #{BASE_DIR}/config.yml --text-kvs-type=gdbm ] ],
      '--text-kvs-config'                => [ %W[ -f #{BASE_DIR}/config.yml --text-kvs-config={} ] ],
      '--use-text-kvs-checksum'          => [ %W[ -f #{BASE_DIR}/config.yml --use-text-kvs-checksum ] ],
      '--no-use-text-kvs-checksum'       => [ %W[ -f #{BASE_DIR}/config.yml --no-use-text-kvs-checksum ] ],

      # authentication:
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
      'deplicated:--username,--password' => [ %W[ -d #{BASE_DIR} --username=foo --password=foo    ], true ]
    )
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

          imap_connect{|imap|
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
          }
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

        imap_connect{|imap|
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
        }

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

    data('default'            => [ false, %w[] ],
         '-r'                 => [ false, %w[ -r prime ] ],
         '--required-feature' => [ false, %w[ --required-feature=prime ] ],
         '--format=yaml'      => [ false, %w[ --format=yaml ] ],
         '--format=json'      => [ false, %w[ --format=json ] ],

         # deplicated options
         'deplicated:--load-library' => [ true, %w[ --load-library=prime ] ])
    def test_environment(data)
      deplicated, options = data

      stdout, stderr, status = Open3.capture3('rims', 'environment', *options)
      pp [ stdout, stderr, status ] if $DEBUG

      assert_equal(0, status.exitstatus)
      if (deplicated) then
        assert_match(/^warning:/, stderr)
      else
        assert_equal('', stderr)
      end

      assert_match(/RIMS Environment/, stdout)
      assert_match(/RUBY VERSION.*#{Regexp.quote(RUBY_DESCRIPTION)}/, stdout)
      assert_match(/RIMS VERSION.*#{Regexp.quote(RIMS::VERSION)}/, stdout)
      assert_match(/AUTHENTICATION PLUG-IN.*plain/m, stdout)
      assert_match(/AUTHENTICATION PLUG-IN.*hash/m, stdout)
      assert_match(/KEY-VALUE STORE PLUG-IN.*gdbm/m, stdout)
    end

    tls_dir = Pathname(__FILE__).parent.parent / "tls"
    TLS_CA_CERT     = tls_dir / 'ca.cert'
    TLS_SERVER_CERT = tls_dir / 'server_localhost.cert'
    TLS_SERVER_PKEY = tls_dir / 'server.priv_key'

    unless ([ TLS_CA_CERT, TLS_SERVER_CERT, TLS_SERVER_PKEY ].all?(&:file?)) then
      warn("warning: do `rake test_cert:make' to create TLS private key file and TLS certificate file for test.")
    end

    def run_server(use_ssl: false, optional: {})
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

      config.update(optional)

      config_path = @base_dir + 'config.yml'
      config_path.write(RIMS::Service::Configuration.stringify_symbol(config).to_yaml)

      Open3.popen3('rims', 'server', '-f', config_path.to_s) {|stdin, stdout, stderr, wait_thread|
        begin
          stdout_thread = Thread.new{
            for line in stdout
              puts "stdout: #{line}" if $DEBUG
            end
          }
          stderr_thread = Thread.new{
            for line in stderr
              puts "stderr: #{line}" if $DEBUG
            end
          }

          ret_val = nil
          imap_connect(use_ssl) {|imap|
            imap.noop
            ret_val = yield(imap)
            imap.logout unless imap.disconnected?
          }
        ensure
          Process.kill(:TERM, wait_thread.pid)
          stdout_thread.join if stdout_thread
          stderr_thread.join if stderr_thread
          if ($DEBUG) then
            p :rims_log
            puts((@base_dir + 'rims.log').read)
            p :protocol_log
            puts((@base_dir + 'protocol.log').read)
          end
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

    data('default'                    => [ true,  true,  false, %w[] ],
         '-r'                         => [ true,  true,  false, %w[ -r prime ] ],
         '--required-feature'         => [ true,  true,  false, %w[ --required-feature=prime ] ],
         '--kvs-type'                 => [ true,  true,  false, %w[ --kvs-type=gdbm ] ],
         '--use-kvs-checksum'         => [ true,  true,  false, %w[ --use-kvs-checksum ] ],
         '--no-use-kvs-checksum'      => [ true,  true,  false, %w[ --no-use-kvs-checksum ],
                                           { storage:
                                               { meta_key_value_store:
                                                   { use_checksum:
                                                       false
                                                   }
                                               }
                                           }
                                         ],
         '-v'                         => [ true,  true,  false, %w[ -v ] ],
         '--verbose'                  => [ true,  true,  false, %w[ --verbose ] ],
         '--no-verbose'               => [ false, true,  false, %w[ --no-verbose ] ],
         '--quiet'                    => [ false, true,  false, %w[ --quiet ] ],
         '--no-quiet'                 => [ true,  true,  false, %w[ --no-quiet ] ],
         '--return-flag-exit-code'    => [ true,  true,  false, %w[ --return-flag-exit-code ] ],
         '--no-return-flag-exit-code' => [ true,  false, false, %w[ --no-return-flag-exit-code ] ],

         # deplicated options
         'deplicated:--load-library'     => [ true, true, true, %w[ --load-library=prime ] ],
         'deplicated:--use-kvs-cksum'    => [ true, true, true, %w[ --use-kvs-cksum ] ],
         'deplicated:--no-use-kvs-cksum' => [ true, true, true, %w[ --no-use-kvs-cksum ],
                                              { storage:
                                                  { meta_key_value_store:
                                                      { use_checksum:
                                                          false
                                                      }
                                                  }
                                              }
                                            ])
    def test_mbox_dirty_flag_true(data)
      expected_stdout, expected_status, deplicated, options, config = data

      run_server(optional: config || {}) {|imap|
        imap.login('foo', 'foo')
        imap.select('INBOX')
      }

      svc_conf = RIMS::Service::Configuration.new
      svc_conf.load(base_dir: @base_dir.to_s)
      foo_mbox_path = svc_conf.make_key_value_store_path(RIMS::MAILBOX_DATA_STRUCTURE_VERSION,
                                                         RIMS::Authentication.unique_user_id('foo'))

      stdout, stderr, status = Open3.capture3('rims', 'mbox-dirty-flag', '--quiet', '--enable-dirty-flag', foo_mbox_path.to_s)
      assert_equal('', stdout)
      assert_equal('', stderr)
      assert_equal(1, status.exitstatus)

      stdout, stderr, status = Open3.capture3('rims', 'mbox-dirty-flag', *options, foo_mbox_path.to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      if (expected_stdout) then
        assert_match(/dirty flag is true/, stdout)
      else
        assert_equal('', stdout)
      end
      if (deplicated) then
        assert_match(/warning/, stderr)
      else
        assert_equal('', stderr)
      end
      if (expected_status) then
        assert_equal(1, status.exitstatus)
      else
        assert_equal(0, status.exitstatus)
      end
    end

    data('default'                    => [ true,  true,  false, %w[] ],
         '-r'                         => [ true,  true,  false, %w[ -r prime ] ],
         '--required-feature'         => [ true,  true,  false, %w[ --required-feature=prime ] ],
         '--kvs-type'                 => [ true,  true,  false, %w[ --kvs-type=gdbm ] ],
         '--use-kvs-checksum'         => [ true,  true,  false, %w[ --use-kvs-checksum ] ],
         '--no-use-kvs-checksum'      => [ true,  true,  false, %w[ --no-use-kvs-checksum ],
                                           { storage:
                                               { meta_key_value_store:
                                                   { use_checksum:
                                                       false
                                                   }
                                               }
                                           }
                                         ],
         '-v'                         => [ true,  true,  false, %w[ -v ] ],
         '--verbose'                  => [ true,  true,  false, %w[ --verbose ] ],
         '--no-verbose'               => [ false, true,  false, %w[ --no-verbose ] ],
         '--quiet'                    => [ false, true,  false, %w[ --quiet ] ],
         '--no-quiet'                 => [ true,  true,  false, %w[ --no-quiet ] ],
         '--return-flag-exit-code'    => [ true,  true,  false, %w[ --return-flag-exit-code ] ],
         '--no-return-flag-exit-code' => [ true,  false, false, %w[ --no-return-flag-exit-code ] ],

         # deplicated options
         'deplicated:--load-library'     => [ true, true, true, %w[ --load-library=prime ] ],
         'deplicated:--use-kvs-cksum'    => [ true, true, true, %w[ --use-kvs-cksum ] ],
         'deplicated:--no-use-kvs-cksum' => [ true, true, true, %w[ --no-use-kvs-cksum ],
                                              { storage:
                                                  { meta_key_value_store:
                                                      { use_checksum:
                                                          false
                                                      }
                                                  }
                                              }
                                            ])
    def test_mbox_dirty_flag_false(data)
      expected_stdout, expected_status, deplicated, options, config = data

      run_server(optional: config || {}) {|imap|
        imap.login('foo', 'foo')
        imap.select('INBOX')
      }

      svc_conf = RIMS::Service::Configuration.new
      svc_conf.load(base_dir: @base_dir.to_s)
      foo_mbox_path = svc_conf.make_key_value_store_path(RIMS::MAILBOX_DATA_STRUCTURE_VERSION,
                                                         RIMS::Authentication.unique_user_id('foo'))

      stdout, stderr, status = Open3.capture3('rims', 'mbox-dirty-flag', *options, foo_mbox_path.to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      if (expected_stdout) then
        assert_match(/dirty flag is false/, stdout)
      else
        assert_equal('', stdout)
      end
      if (deplicated) then
        assert_match(/warning/, stderr)
      else
        assert_equal('', stderr)
      end
      if (expected_status) then
        assert_equal(0, status.exitstatus)
      else
        assert_equal(0, status.exitstatus)
      end
    end

    data('default'                    => [ true,  true,  false, %w[] ],
         '-r'                         => [ true,  true,  false, %w[ -r prime ] ],
         '--required-feature'         => [ true,  true,  false, %w[ --required-feature=prime ] ],
         '--kvs-type'                 => [ true,  true,  false, %w[ --kvs-type=gdbm ] ],
         '--use-kvs-checksum'         => [ true,  true,  false, %w[ --use-kvs-checksum ] ],
         '--no-use-kvs-checksum'      => [ true,  true,  false, %w[ --no-use-kvs-checksum ],
                                           { storage:
                                               { meta_key_value_store:
                                                   { use_checksum:
                                                       false
                                                   }
                                               }
                                           }
                                         ],
         '-v'                         => [ true,  true,  false, %w[ -v ] ],
         '--verbose'                  => [ true,  true,  false, %w[ --verbose ] ],
         '--no-verbose'               => [ false, true,  false, %w[ --no-verbose ] ],
         '--quiet'                    => [ false, true,  false, %w[ --quiet ] ],
         '--no-quiet'                 => [ true,  true,  false, %w[ --no-quiet ] ],
         '--return-flag-exit-code'    => [ true,  true,  false, %w[ --return-flag-exit-code ] ],
         '--no-return-flag-exit-code' => [ true,  false, false, %w[ --no-return-flag-exit-code ] ],

         # deplicated options
         'deplicated:--load-library'     => [ true, true, true, %w[ --load-library=prime ] ],
         'deplicated:--use-kvs-cksum'    => [ true, true, true, %w[ --use-kvs-cksum ] ],
         'deplicated:--no-use-kvs-cksum' => [ true, true, true, %w[ --no-use-kvs-cksum ],
                                              { storage:
                                                  { meta_key_value_store:
                                                      { use_checksum:
                                                          false
                                                      }
                                                  }
                                              }
                                            ])
    def test_mbox_dirty_flag_enable(data)
      expected_stdout, expected_status, deplicated, options, config = data

      run_server(optional: config || {}) {|imap|
        imap.login('foo', 'foo')
        imap.select('INBOX')
      }

      svc_conf = RIMS::Service::Configuration.new
      svc_conf.load(base_dir: @base_dir.to_s)
      foo_mbox_path = svc_conf.make_key_value_store_path(RIMS::MAILBOX_DATA_STRUCTURE_VERSION,
                                                         RIMS::Authentication.unique_user_id('foo'))

      stdout, stderr, status = Open3.capture3('rims', 'mbox-dirty-flag', '--enable-dirty-flag', *options, foo_mbox_path.to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      if (expected_stdout) then
        assert_match(/dirty flag is true/, stdout)
      else
        assert_equal('', stdout)
      end
      if (deplicated) then
        assert_match(/warning/, stderr)
      else
        assert_equal('', stderr)
      end
      if (expected_status) then
        assert_equal(1, status.exitstatus)
      else
        assert_equal(0, status.exitstatus)
      end

      stdout, stderr, status = Open3.capture3('rims', 'mbox-dirty-flag', '--quiet', '--return-flag-exit-code', foo_mbox_path.to_s)
      assert_equal('', stdout)
      assert_equal('', stderr)
      assert_equal(1, status.exitstatus)
    end

    data('default'                    => [ true,  true,  false, %w[] ],
         '-r'                         => [ true,  true,  false, %w[ -r prime ] ],
         '--required-feature'         => [ true,  true,  false, %w[ --required-feature=prime ] ],
         '--kvs-type'                 => [ true,  true,  false, %w[ --kvs-type=gdbm ] ],
         '--use-kvs-checksum'         => [ true,  true,  false, %w[ --use-kvs-checksum ] ],
         '--no-use-kvs-checksum'      => [ true,  true,  false, %w[ --no-use-kvs-checksum ],
                                           { storage:
                                               { meta_key_value_store:
                                                   { use_checksum:
                                                       false
                                                   }
                                               }
                                           }
                                         ],
         '-v'                         => [ true,  true,  false, %w[ -v ] ],
         '--verbose'                  => [ true,  true,  false, %w[ --verbose ] ],
         '--no-verbose'               => [ false, true,  false, %w[ --no-verbose ] ],
         '--quiet'                    => [ false, true,  false, %w[ --quiet ] ],
         '--no-quiet'                 => [ true,  true,  false, %w[ --no-quiet ] ],
         '--return-flag-exit-code'    => [ true,  true,  false, %w[ --return-flag-exit-code ] ],
         '--no-return-flag-exit-code' => [ true,  false, false, %w[ --no-return-flag-exit-code ] ],

         # deplicated options
         'deplicated:--load-library'     => [ true, true, true, %w[ --load-library=prime ] ],
         'deplicated:--use-kvs-cksum'    => [ true, true, true, %w[ --use-kvs-cksum ] ],
         'deplicated:--no-use-kvs-cksum' => [ true, true, true, %w[ --no-use-kvs-cksum ],
                                              { storage:
                                                  { meta_key_value_store:
                                                      { use_checksum:
                                                          false
                                                      }
                                                  }
                                              }
                                            ])
    def test_mbox_dirty_flag_disable(data)
      expected_stdout, expected_status, deplicated, options, config = data

      run_server(optional: config || {}) {|imap|
        imap.login('foo', 'foo')
        imap.select('INBOX')
      }

      svc_conf = RIMS::Service::Configuration.new
      svc_conf.load(base_dir: @base_dir.to_s)
      foo_mbox_path = svc_conf.make_key_value_store_path(RIMS::MAILBOX_DATA_STRUCTURE_VERSION,
                                                         RIMS::Authentication.unique_user_id('foo'))

      stdout, stderr, status = Open3.capture3('rims', 'mbox-dirty-flag', '--quiet', '--return-flag-exit-code', '--enable-dirty-flag', foo_mbox_path.to_s)
      assert_equal('', stdout)
      assert_equal('', stderr)
      assert_equal(1, status.exitstatus)

      stdout, stderr, status = Open3.capture3('rims', 'mbox-dirty-flag', '--disable-dirty-flag', *options, foo_mbox_path.to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      if (expected_stdout) then
        assert_match(/dirty flag is false/, stdout)
      else
        assert_equal('', stdout)
      end
      if (deplicated) then
        assert_match(/warning/, stderr)
      else
        assert_equal('', stderr)
      end
      if (expected_status) then
        assert_equal(0, status.exitstatus)
      else
        assert_equal(0, status.exitstatus)
      end

      stdout, stderr, status = Open3.capture3('rims', 'mbox-dirty-flag', '--quiet', '--return-flag-exit-code', foo_mbox_path.to_s)
      assert_equal('', stdout)
      assert_equal('', stderr)
      assert_equal(0, status.exitstatus)
    end

    data('alice' => %w[ 2bd806c97f0e00af1a1fc3328fa763a9269723c8db8fac4f93af71db186d6e90 alice ],
         'bob'   => %w[ 81b637d8fcd2c6da6359e6963113a1170de795e4b725b84d1e0b4cfd9ec58ce9 bob ])
    def test_unique_user_id(data)
      expected_id, username = data
      stdout, stderr, status = Open3.capture3('rims', 'unique-user-id', username)
      assert_equal(expected_id, stdout.chomp)
      assert_equal('', stderr)
      assert_equal(0, status.exitstatus)
    end

    data('-f'            => %W[ -f #{BASE_DIR}/config.yml ],
         '--config-yaml' => %W[ --config-yaml=#{BASE_DIR}/config.yml ],
         'base_dir'      => [ BASE_DIR ])
    def test_show_user_mbox(args)
      config_path = @base_dir + 'config.yml'
      config_path.write({}.to_yaml)

      svc_conf = RIMS::Service::Configuration.new
      svc_conf.load(base_dir: @base_dir.to_s)
      foo_mbox_path = svc_conf.make_key_value_store_path(RIMS::MAILBOX_DATA_STRUCTURE_VERSION,
                                                         RIMS::Authentication.unique_user_id('foo'))

      stdout, stderr, status = Open3.capture3('rims', 'show-user-mbox', *args, 'foo')
      pp [ stdout, stderr, status ] if $DEBUG
      assert_equal(foo_mbox_path.to_s, stdout.chomp)
      assert_equal('', stderr)
      assert_equal(0, status.exitstatus)
    end

    data('default' => %w[],
         'MD5'     => %w[ --hash-type=MD5 ],
         'RMD160'  => %w[ --hash-type=RMD160 ],
         'SHA256'  => %w[ --hash-type=SHA256 ],
         'SHA512'  => %w[ --hash-type=SHA512 ],
         'strech'  => %w[ --stretch-count=100000 ],
         'salt'    => %w[ --salt-size=1024 ])
    def test_pass_hash(options)
      passwd_path = @base_dir + 'passwd_plain.yml'
      passwd_path.write([ { 'user' => 'foo', 'pass' => 'open sesame' } ].to_yaml)

      stdout, stderr, status = Open3.capture3('rims', 'pass-hash', *options, passwd_path.to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      assert_equal('', stderr)
      assert_equal(0, status.exitstatus)

      passwd_hash = YAML.load(stdout)
      hash_src = RIMS::Password::HashSource.build_from_conf(passwd_hash)
      auth = RIMS::Authentication.new
      auth.add_plug_in(hash_src)

      logger = Logger.new(STDOUT)
      logger.level = ($DEBUG) ? :debug : :unknown

      auth.start_plug_in(logger)
      assert_equal(true, (auth.user? 'foo'))
      assert(auth.authenticate_login('foo', 'open sesame'))
      auth.stop_plug_in(logger)
    end

    data('default'               => [ true,  false, %w[] ],
         '-r'                    => [ true,  false, %w[ -r prime ] ],
         '--required-feature'    => [ true,  false, %w[ --required-feature=prime ] ],
         '--kvs-type'            => [ true,  false, %w[ --kvs-type=gdbm ] ],
         '--use-kvs-checksum'    => [ true,  false, %w[ --use-kvs-checksum ] ],
         '--no-use-kvs-checksum' => [ true,  false, %w[ --no-use-kvs-checksum ],
                                      { storage: {
                                          meta_key_value_store: {
                                            use_checksum: false
                                          }
                                        }
                                      }
                                    ],
         '--match-key:match'     => [ true,  false, %w[ --match-key=uid ] ],
         '--match-key:no_match'  => [ false, false, %w[ --match-key=nothing ] ],
         '--dump-size'           => [ true,  false, %w[ --dump-size ] ],
         '--no-dump-size'        => [ true,  false, %w[ --no-dump-size ] ],
         '--dump-value'          => [ true,  false, %w[ --dump-value ] ],
         '--no-dump-value'       => [ true,  false, %w[ --no-dump-value ] ],
         '--marshal-restore'     => [ true,  false, %w[ --marshal-restore ] ],
         '--no-marshal-restore'  => [ true,  false, %w[ --no-marshal-restore ] ],

         # deplicated options
         'deplicated:--load-library'     => [ true, true, %w[ --load-library=prime ] ],
         'deplicated:--use-kvs-cksum'    => [ true, true, %w[ --use-kvs-cksum ] ],
         'deplicated:--no-use-kvs-cksum' => [ true, true, %w[ --no-use-kvs-cksum ],
                                              { storage: {
                                                  meta_key_value_store: {
                                                    use_checksum: false
                                                  }
                                                }
                                              }
                                            ])
    def test_debug_dump_kvs(data)
      expected_stdout, deplicated, options, config = data

      run_server(optional: config || {}) {|imap|
        imap.login('foo', 'foo')
        imap.select('INBOX')
      }

      svc_conf = RIMS::Service::Configuration.new
      svc_conf.load(base_dir: @base_dir.to_s)
      foo_mbox_path = svc_conf.make_key_value_store_path(RIMS::MAILBOX_DATA_STRUCTURE_VERSION,
                                                         RIMS::Authentication.unique_user_id('foo'))

      stdout, stderr, status = Open3.capture3('rims', 'debug-dump-kvs', *options, (foo_mbox_path + 'meta').to_s)
      pp [ stdout, stderr, status ] if $DEBUG
      if (expected_stdout) then
        assert(! stdout.empty?)
      else
        assert_equal('', stdout)
      end
      if (deplicated) then
        assert_match(/warning/, stderr)
      else
        assert_equal('', stderr)
      end
      assert_equal(0, status.exitstatus)
    end

    include ProtocolFetchMailSample

    data('default'       => {},
         'use_ssl'       => { use_ssl: true },
         'multi-process' => { process_num: 4 },
         'use_ssl,multi-process' => {
           use_ssl: true,
           process_num: 4
         })
    def test_system(data)
      use_ssl     = (data.key? :use_ssl) ? data[:use_ssl] : false
      process_num = data[:process_num] || 0

      config = {
        server: {
          process_num: process_num
        },
        drb_services: {
          process_num: process_num
        }
      }

      run_server(use_ssl: use_ssl, optional: config) {|imap|
        assert_imap_no_response = lambda{|error_message_pattern, &block|
          error_response = assert_raise(Net::IMAP::NoResponseError) { block.call }
          assert_match(error_message_pattern, error_response.message)
        }

        assert_no_response_authenticated_state_imap_commands = lambda{|error_message_pattern|
          assert_imap_no_response[error_message_pattern] { imap.subscribe('INBOX') }
          assert_imap_no_response[error_message_pattern] { imap.unsubscribe('INBOX') }
          assert_imap_no_response[error_message_pattern] { imap.list('', '*') }
          assert_imap_no_response[error_message_pattern] { imap.lsub('', '*') }
          assert_imap_no_response[error_message_pattern] { imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]) }
          assert_imap_no_response[error_message_pattern] { imap.create('foo') }
          assert_imap_no_response[error_message_pattern] { imap.rename('foo', 'bar') }
          assert_imap_no_response[error_message_pattern] { imap.delete('bar') }
          assert_imap_no_response[error_message_pattern] { imap.append('INBOX', 'a') }
          assert_imap_no_response[error_message_pattern] { imap.select('INBOX') }
          assert_imap_no_response[error_message_pattern] { imap.examine('INBOX') }
        }

        assert_no_response_selected_state_imap_commands = lambda{|error_message_pattern|
          assert_imap_no_response[error_message_pattern] { imap.check }
          assert_imap_no_response[error_message_pattern] { imap.search(%w[ * ]) }
          assert_imap_no_response[error_message_pattern] { imap.uid_search(%w[ * ]) }
          assert_imap_no_response[error_message_pattern] { imap.fetch(1..-1, 'RFC822') }
          assert_imap_no_response[error_message_pattern] { imap.uid_fetch(1..-1, 'RFC822') }
          assert_imap_no_response[error_message_pattern] { imap.store(1..-1, '+FLAGS', [ :Deleted ]) }
          assert_imap_no_response[error_message_pattern] { imap.uid_store(1..-1, '+FLAGS', [ :Deleted ]) }
          assert_imap_no_response[error_message_pattern] { imap.copy(1..-1, 'foo') }
          assert_imap_no_response[error_message_pattern] { imap.uid_copy(1..-1, 'foo') }
          assert_imap_no_response[error_message_pattern] { imap.expunge }
          assert_imap_no_response[error_message_pattern] { imap.idle(0.1) { flunk } } # error log is a Net::IMAP bug to ignore Command Continuation Request
          assert_imap_no_response[error_message_pattern] { imap.close }
        }

        # State: Not Authenticated
        assert_equal('OK', imap.greeting.name)
        assert_equal("RIMS v#{RIMS::VERSION} IMAP4rev1 service ready.", imap.greeting.data.text)

        # IMAP commands for Any State
        assert_equal(%w[ IMAP4REV1 UIDPLUS IDLE AUTH=PLAIN AUTH=CRAM-MD5 ], imap.capability)
        imap.noop

        # IMAP commands for Authenticated State
        assert_no_response_authenticated_state_imap_commands.call(/not authenticated/)

        # IMAP commands for Selected State
        assert_no_response_selected_state_imap_commands.call(/not authenticated/)

        imap_connect(use_ssl) {|imap_auth_plain|
          imap_auth_plain.authenticate('PLAIN', 'foo', 'foo')
          imap_auth_plain.logout
        }

        imap_connect(use_ssl) {|imap_auth_cram_md5|
          imap_auth_cram_md5.authenticate('CRAM-MD5', 'foo', 'foo')
          imap_auth_cram_md5.logout
        }

        # State: Not Authenticated -> Authenticated
        imap.login('foo', 'foo')

        # IMAP commands for Any State
        assert_equal(%w[ IMAP4REV1 UIDPLUS IDLE AUTH=PLAIN AUTH=CRAM-MD5 ], imap.capability)
        imap.noop

        # IMAP commands for Authenticated State
        imap.subscribe('INBOX')
        assert_imap_no_response[/not implemented/] { imap.unsubscribe('INBOX') }

        assert_equal([ { attr: [:Noinferiors, :Unmarked], delim: nil, name: 'INBOX' } ],
                     imap.list('', '*').map(&:to_h))
        assert_equal([ { attr: [:Noinferiors, :Unmarked], delim: nil, name: 'INBOX' } ],
                     imap.lsub('', '*').map(&:to_h))

        status = {
          'MESSAGES'    => 0,
          'RECENT'      => 0,
          'UNSEEN'      => 0,
          'UIDNEXT'     => 1,
          'UIDVALIDITY' => 1
        }
        assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))

        # INBOX will not be changed.
        assert_imap_no_response[/duplicated mailbox/] { imap.create('INBOX') }
        assert_imap_no_response[/not rename inbox/] { imap.rename('INBOX', 'foo') }
        assert_imap_no_response[/not delete inbox/] { imap.delete('INBOX') }
        assert_equal([ { attr: [:Noinferiors, :Unmarked], delim: nil, name: 'INBOX' } ], imap.list('', '*').map(&:to_h))

        imap.create('foo')
        assert_equal([ { attr: [:Noinferiors, :Unmarked], delim: nil, name: 'INBOX' },
                       { attr: [:Noinferiors, :Unmarked], delim: nil, name: 'foo' }
                     ],
                     imap.list('', '*').map(&:to_h))
        imap.rename('foo', 'bar')
        assert_equal([ { attr: [:Noinferiors, :Unmarked], delim: nil, name: 'INBOX' },
                       { attr: [:Noinferiors, :Unmarked], delim: nil, name: 'bar' }
                     ],
                     imap.list('', '*').map(&:to_h))
        imap.delete('bar')
        assert_equal([ { attr: [:Noinferiors, :Unmarked], delim: nil, name: 'INBOX' } ],
                     imap.list('', '*').map(&:to_h))

        # IMAP commands for Selected State
        assert_no_response_selected_state_imap_commands.call(/not selected/)

        append_inbox = lambda{|message, *optional|
          imap.append('INBOX', message, *optional)
          if (optional[0] && (optional[0].is_a? Array)) then
            flags = optional[0]
          else
            flags = []
          end
          status['MESSAGES'] += 1
          status['RECENT']   += 1
          status['UNSEEN']   += 1 unless (flags.include? :Seen)
          status['UIDNEXT']  += 1
          assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))
        }

        # message UID offset
        uid_offset = 6
        uid_offset.times do
          append_inbox.call('', [ :Deleted ])
        end
        imap.select('INBOX')
        assert_equal((1..uid_offset).to_a.reverse, imap.expunge)
        imap.close
        status['MESSAGES'] -= uid_offset
        status['RECENT']    = 0
        status['UNSEEN']   -= uid_offset
        assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))

        make_mail_simple
        append_inbox.call(@simple_mail.raw_source, [ :Answered, :Flagged ], @simple_mail.date)

        # reset recent flag
        imap.select('INBOX')
        imap.close
        status['RECENT'] = 0
        assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))

        make_mail_multipart
        append_inbox.call(@mpart_mail.raw_source, [ :Draft, :Seen ], @mpart_mail.date)

        make_mail_mime_subject
        append_inbox.call(@mime_subject_mail.raw_source, @mime_subject_mail.date)

        assert_imap_search = lambda{|uid|
          if (uid) then
            imap_search = imap.method(:uid_search)
            seqno = lambda{|*args| args.map{|i| uid_offset + i } }
          else
            imap_search = imap.method(:search)
            seqno = lambda{|*args| args }
          end

          assert_equal(seqno[2],       imap_search.call([ 2 ]))
          assert_equal(seqno[1, 2, 3], imap_search.call(%w[ ALL ]))
          assert_equal(seqno[1],       imap_search.call([ 'ANSWERED' ]))                                              # *a
          assert_equal(seqno[3],       imap_search.call([ 'BCC', 'foo' ]))                                            # *b
          assert_equal(seqno[1],       imap_search.call([ 'BEFORE', @mpart_mail.date ]))
          assert_equal(seqno[1, 2, 3], imap_search.call([ 'BODY', 'Hello world.' ]))
          assert_equal(seqno[3],       imap_search.call([ 'CC', 'kate' ]))
          assert_equal(seqno[],        imap_search.call([ 'DELETED' ]))
          assert_equal(seqno[2],       imap_search.call([ 'DRAFT' ]))
          assert_equal(seqno[1],       imap_search.call([ 'FLAGGED' ]))
          assert_equal(seqno[2, 3],    imap_search.call([ 'FROM', 'foo' ]))
          assert_equal(seqno[3],       imap_search.call([ 'HEADER', 'Message-Id', '20131107214750.445A1255B9F' ]))
          assert_equal(seqno[],        imap_search.call([ 'KEYWORD', 'unsupported' ]))
          assert_equal(seqno[2],       imap_search.call([ 'LARGER', @mime_subject_mail.raw_source.bytesize ]))        # *c
          assert_equal(seqno[3],       imap_search.call([ 'NEW' ]))
          assert_equal(seqno[1],       imap_search.call([ 'OLD' ]))
          assert_equal(seqno[1],       imap_search.call([ 'ON', @simple_mail.date ]))
          assert_equal(seqno[2, 3],    imap_search.call([ 'RECENT' ]))
          assert_equal(seqno[2],       imap_search.call([ 'SEEN' ]))
          assert_equal(seqno[1],       imap_search.call([ 'SENTBEFORE', @mpart_mail.date ]))
          assert_equal(seqno[1],       imap_search.call([ 'SENTON', @simple_mail.date ]))
          assert_equal(seqno[2, 3],    imap_search.call([ 'SENTSINCE', @simple_mail.date ]))
          assert_equal(seqno[1],       imap_search.call([ 'SMALLER', @mime_subject_mail.raw_source.bytesize ]))
          assert_equal(seqno[2],       imap_search.call([ 'SUBJECT', 'multipart' ]))
          assert_equal(seqno[1],       imap_search.call([ 'TEXT', 'Subject: test' ]))
          assert_equal(seqno[1, 2, 3], imap_search.call([ 'TEXT', 'Hello world.' ]))
          assert_equal(seqno[1],       imap_search.call([ 'TO', 'foo' ]))
          assert_equal(seqno[1],       imap_search.call([ 'UID', uid_offset + 1 ]))
          assert_equal(seqno[2, 3],    imap_search.call([ 'UNANSWERED' ]))
          assert_equal(seqno[1, 2, 3], imap_search.call([ 'UNDELETED' ]))
          assert_equal(seqno[1, 3],    imap_search.call([ 'UNDRAFT' ]))
          assert_equal(seqno[2, 3],    imap_search.call([ 'UNFLAGGED' ]))
          assert_equal(seqno[1, 2, 3], imap_search.call([ 'UNKEYWORD', 'unsupported' ]))
          assert_equal(seqno[1, 3],    imap_search.call([ 'UNSEEN' ]))
          assert_equal(seqno[1, 3],    imap_search.call([ 'NOT', 'LARGER', @mime_subject_mail.raw_source.bytesize ])) # not *c
          assert_equal(seqno[1, 3],    imap_search.call([ 'OR', 'ANSWERED', 'BCC', 'foo' ]))                          # or *a *b
        }
        assert_imap_search_seqno = lambda{ assert_imap_search.call(false) }
        assert_imap_search_uid   = lambda{ assert_imap_search.call(true) }

        imap_date_fmt = '%d-%b-%Y %H:%M:%S %z'
        assert_imap_fetch_read_only = lambda{|uid|
          if (uid) then
            imap_fetch = imap.method(:uid_fetch)
            msg_set = lambda{|seqno_set|
              case (seqno_set)
              when Array
                seqno_set.map{|i| uid_offset + i }
              when Range
                first = uid_offset + seqno_set.first
                if (seqno_set.last >= 0) then
                  last = uid_offset + seqno_set.last
                else
                  last = seqno_set.last
                end
                first..last
              when Integer
                uid_offset + seqno_set
              else
                raise TypeError, "unknown message set type: #{seqno_set}"
              end
            }
            fetch_data = lambda{|*data_list|
              data_list.map{|seqno, attr|
                unless (attr.key? 'UID') then
                  attr = attr.merge({ 'UID' => uid_offset + seqno })
                end
                Net::IMAP::FetchData.new(seqno, attr)
              }
            }
          else
            imap_fetch = imap.method(:fetch)
            msg_set = lambda{|seqno_set| seqno_set }
            fetch_data = lambda{|*data_list| data_list.map{|i| Net::IMAP::FetchData.new(*i) } }
          end

          envelope = lambda{|mail|
            Net::IMAP::Envelope.new(mail.header['Date'],
                                    mail.header['Subject'],
                                    mail.from     ? mail.from.map{|addr| Net::IMAP::Address.new(*addr.to_a) }     : nil,
                                    mail.reply_to ? mail.reply_to.map{|addr| Net::IMAP::Address.new(*addr.to_a) } : nil,
                                    mail.sender   ? mail.sender.map{|addr| Net::IMAP::Address.new(*addr.to_a) }   : nil,
                                    mail.to       ? mail.to.map{|addr| Net::IMAP::Address.new(*addr.to_a) }       : nil,
                                    mail.cc       ? mail.cc.map{|addr| Net::IMAP::Address.new(*addr.to_a) }       : nil,
                                    mail.bcc      ? mail.bcc.map{|addr| Net::IMAP::Address.new(*addr.to_a) }      : nil,
                                    mail.header['In-Reply-To'],
                                    mail.header['Message-Id'])
          }
          body_type = lambda{|mail, extension=false|
            body_params = lambda{|params|
              if (params && ! params.empty?) then
                Hash[params.map{|n, v| [ n.upcase, v ] }]
              end
            }
            body_disposition = lambda{|mail|
              if (mail.content_disposition) then
                Net::IMAP::ContentDisposition.new(mail.content_disposition_upcase,
                                                  body_params[mail.content_disposition_parameter_list])
              end
            }
            body_language = lambda{|mail|
              if (mail.content_language) then
                if (mail.content_language.length > 1) then
                  mail.content_language_upcase
                else
                  mail.content_language_upcase[0]
                end
              end
            }
            if (mail.text?) then
              Net::IMAP::BodyTypeText.new(mail.media_main_type_upcase,
                                          mail.media_sub_type_upcase,
                                          body_params[mail.content_type_parameter_list],
                                          mail.header['Content-Id'],
                                          mail.header['Content-Description'],
                                          mail.header.fetch_upcase('Content-Transfer-Encoding'),
                                          mail.raw_source.bytesize,
                                          mail.raw_source.each_line.count,
                                          *(
                                            if (extension) then
                                              [ mail.header['Content-MD5'],
                                                body_disposition[mail],
                                                body_language[mail],
                                                [ mail.header['Content-Location'] ]
                                              ]
                                            else
                                              []
                                            end
                                          ))
            elsif (mail.message?) then
              Net::IMAP::BodyTypeMessage.new(mail.media_main_type_upcase,
                                             mail.media_sub_type_upcase,
                                             body_params[mail.content_type_parameter_list],
                                             mail.header['Content-Id'],
                                             mail.header['Content-Description'],
                                             mail.header.fetch_upcase('Content-Transfer-Encoding'),
                                             mail.raw_source.bytesize,
                                             envelope[mail.message],
                                             body_type[mail.message, extension],
                                             mail.raw_source.each_line.count,
                                             *(
                                               if (extension) then
                                                 [ mail.header['Content-MD5'],
                                                   body_disposition[mail],
                                                   body_language[mail],
                                                   [ mail.header['Content-Location'] ]
                                                 ]
                                               else
                                                 []
                                               end
                                             ))
            elsif (mail.multipart?) then
              Net::IMAP::BodyTypeMultipart.new(mail.media_main_type_upcase,
                                               mail.media_sub_type_upcase,
                                               mail.parts.map{|m| body_type[m, extension] },
                                               *(
                                                 if (extension) then
                                                   [ body_params[mail.content_type_parameter_list],
                                                     body_disposition[mail],
                                                     body_language[mail],
                                                     [ mail.header['Content-Location'] ]
                                                   ]
                                                 else
                                                   []
                                                 end
                                               ))
            else
              Net::IMAP::BodyTypeBasic.new(mail.media_main_type_upcase,
                                           mail.media_sub_type_upcase,
                                           body_params[mail.content_type_parameter_list],
                                           mail.header['Content-Id'],
                                           mail.header['Content-Description'],
                                           mail.header.fetch_upcase('Content-Transfer-Encoding'),
                                           mail.raw_source.bytesize,
                                           *(
                                             if (extension) then
                                               [ mail.header['Content-MD5'],
                                                 body_disposition[mail],
                                                 body_language[mail],
                                                 [ mail.header['Content-Location'] ]
                                               ]
                                             else
                                               []
                                             end
                                           ))
            end
          }

          assert_equal(fetch_data[
                         [ 1,
                           { 'FLAGS'        => [ :Answered, :Flagged ],
                             'INTERNALDATE' => @simple_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @simple_mail.raw_source.bytesize,
                             'ENVELOPE'     => envelope[@simple_mail]
                           }
                         ],
                         [ 2,
                           { 'FLAGS'        => [ :Seen, :Draft, :Recent ],
                             'INTERNALDATE' => @mpart_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @mpart_mail.raw_source.bytesize,
                             'ENVELOPE'     => envelope[@mpart_mail]
                           }
                         ],
                         [ 3,
                           { 'FLAGS'        => [ :Recent ],
                             'INTERNALDATE' => @mime_subject_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @mime_subject_mail.raw_source.bytesize,
                             'ENVELOPE'     => envelope[@mime_subject_mail]
                           }
                         ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'ALL'))

          assert_equal(fetch_data[
                         [ 1,
                           { 'FLAGS'        => [ :Answered, :Flagged ],
                             'INTERNALDATE' => @simple_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @simple_mail.raw_source.bytesize
                           }
                         ],
                         [ 2,
                           { 'FLAGS'        => [ :Seen, :Draft, :Recent ],
                             'INTERNALDATE' => @mpart_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @mpart_mail.raw_source.bytesize
                           }
                         ],
                         [ 3,
                           { 'FLAGS'        => [ :Recent ],
                             'INTERNALDATE' => @mime_subject_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @mime_subject_mail.raw_source.bytesize
                           }
                         ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'FAST'))

          assert_equal(fetch_data[
                         [ 1,
                           { 'FLAGS'        => [ :Answered, :Flagged ],
                             'INTERNALDATE' => @simple_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @simple_mail.raw_source.bytesize,
                             'ENVELOPE'     => envelope[@simple_mail],
                             'BODY'         => body_type[@simple_mail]
                           }
                         ],
                         [ 2,
                           { 'FLAGS'        => [ :Seen, :Draft, :Recent ],
                             'INTERNALDATE' => @mpart_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @mpart_mail.raw_source.bytesize,
                             'ENVELOPE'     => envelope[@mpart_mail],
                             'BODY'         => body_type[@mpart_mail]
                           }
                         ],
                         [ 3,
                           { 'FLAGS'        => [ :Recent ],
                             'INTERNALDATE' => @mime_subject_mail.date.getutc.strftime(imap_date_fmt),
                             'RFC822.SIZE'  => @mime_subject_mail.raw_source.bytesize,
                             'ENVELOPE'     => envelope[@mime_subject_mail],
                             'BODY'         => body_type[@mime_subject_mail]
                           }
                         ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'FULL'))

          assert_equal(fetch_data[
                         [ 1, { 'BODY' => body_type[@simple_mail] } ],
                         [ 2, { 'BODY' => body_type[@mpart_mail] } ],
                         [ 3, { 'BODY' => body_type[@mime_subject_mail] } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'BODY'))

          assert_equal(fetch_data[
                         [ 1, { 'BODYSTRUCTURE' => body_type[@simple_mail, true] } ],
                         [ 2, { 'BODYSTRUCTURE' => body_type[@mpart_mail, true] } ],
                         [ 3, { 'BODYSTRUCTURE' => body_type[@mime_subject_mail, true] } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'BODYSTRUCTURE'))

          assert_equal(fetch_data[
                         [ 1, { 'ENVELOPE' => envelope[@simple_mail] } ],
                         [ 2, { 'ENVELOPE' => envelope[@mpart_mail] } ],
                         [ 3, { 'ENVELOPE' => envelope[@mime_subject_mail] } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'ENVELOPE'))

          assert_equal(fetch_data[
                         [ 1, { 'FLAGS' => [ :Answered, :Flagged ] } ],
                         [ 2, { 'FLAGS' => [ :Seen, :Draft, :Recent ] } ],
                         [ 3, { 'FLAGS' => [ :Recent ] } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'FLAGS'))

          assert_equal(fetch_data[
                         [ 1, { 'INTERNALDATE' => @simple_mail.date.getutc.strftime(imap_date_fmt) } ],
                         [ 2, { 'INTERNALDATE' => @mpart_mail.date.getutc.strftime(imap_date_fmt) } ],
                         [ 3, { 'INTERNALDATE' => @mime_subject_mail.date.getutc.strftime(imap_date_fmt) } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'INTERNALDATE'))

          assert_equal(fetch_data[
                         [ 1, { 'RFC822.HEADER' => @simple_mail.header.raw_source } ],
                         [ 2, { 'RFC822.HEADER' => @mpart_mail.header.raw_source } ],
                         [ 3, { 'RFC822.HEADER' => @mime_subject_mail.header.raw_source } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'RFC822.HEADER'))

          assert_equal(fetch_data[
                         [ 1, { 'RFC822.SIZE' => @simple_mail.raw_source.bytesize } ],
                         [ 2, { 'RFC822.SIZE' => @mpart_mail.raw_source.bytesize } ],
                         [ 3, { 'RFC822.SIZE' => @mime_subject_mail.raw_source.bytesize } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'RFC822.SIZE'))

          assert_equal(fetch_data[
                         [ 1, { 'UID' => uid_offset + 1 } ],
                         [ 2, { 'UID' => uid_offset + 2 } ],
                         [ 3, { 'UID' => uid_offset + 3 } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'UID'))

          assert_equal(fetch_data[
                         [ 1, { 'BODY[]' => @simple_mail.raw_source } ],
                         [ 2, { 'BODY[]' => @mpart_mail.raw_source } ],
                         [ 3, { 'BODY[]' => @mime_subject_mail.raw_source } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'BODY.PEEK[]'))

          assert_equal(fetch_data[
                         [ 1, { 'BODY[HEADER]' => @simple_mail.header.raw_source } ],
                         [ 2, { 'BODY[HEADER]' => @mpart_mail.header.raw_source } ],
                         [ 3, { 'BODY[HEADER]' => @mime_subject_mail.header.raw_source } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'BODY.PEEK[HEADER]'))

          assert_equal(fetch_data[
                         [ 1,
                           { 'BODY[HEADER.FIELDS (DATE SUBJECT)]' =>
                             @simple_mail.header.find_all{|n, v|
                               %w(DATE SUBJECT).include? n.upcase
                             }.map{|n, v| "#{n}: #{v}\r\n" }.join('') + "\r\n"
                           }
                         ],
                         [ 2,
                           { 'BODY[HEADER.FIELDS (DATE SUBJECT)]' =>
                             @mpart_mail.header.find_all{|n, v|
                               %w(DATE SUBJECT).include? n.upcase
                             }.map{|n, v| "#{n}: #{v}\r\n" }.join('') + "\r\n"
                           }
                         ],
                         [ 3,
                           { 'BODY[HEADER.FIELDS (DATE SUBJECT)]' =>
                             @mime_subject_mail.header.find_all{|n, v|
                               %w(DATE SUBJECT).include? n.upcase
                             }.map{|n, v| "#{n}: #{v}\r\n" }.join('') + "\r\n"
                           }
                         ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'BODY.PEEK[HEADER.FIELDS (DATE SUBJECT)]'))

          assert_equal(fetch_data[
                         [ 1,
                           { 'BODY[HEADER.FIELDS.NOT (TO FROM)]' =>
                             @simple_mail.header.find_all{|n, v|
                               ! (%w(TO FROM).include? n.upcase)
                             }.map{|n, v| "#{n}: #{v}\r\n" }.join('') + "\r\n"
                           }
                         ],
                         [ 2,
                           { 'BODY[HEADER.FIELDS.NOT (TO FROM)]' =>
                             @mpart_mail.header.find_all{|n, v|
                               ! (%w(TO FROM).include? n.upcase)
                             }.map{|n, v| "#{n}: #{v}\r\n" }.join('') + "\r\n"
                           }
                         ],
                         [ 3,
                           { 'BODY[HEADER.FIELDS.NOT (TO FROM)]' =>
                             @mime_subject_mail.header.find_all{|n, v|
                               ! (%w(TO FROM).include? n.upcase)
                             }.map{|n, v| "#{n}: #{v}\r\n" }.join('') + "\r\n"
                           }
                         ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'BODY.PEEK[HEADER.FIELDS.NOT (TO FROM)]'))

          assert_equal(fetch_data[
                         [ 1, { 'BODY[TEXT]' => @simple_mail.body.raw_source } ],
                         [ 2, { 'BODY[TEXT]' => @mpart_mail.body.raw_source } ],
                         [ 3, { 'BODY[TEXT]' => @mime_subject_mail.body.raw_source } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'BODY.PEEK[TEXT]'))

          assert_equal(fetch_data[
                         [ 1, { 'BODY[1.MIME]' => @simple_mail.header.raw_source } ],
                         [ 2, { 'BODY[1.MIME]' => @mpart_mail.parts[0].header.raw_source } ],
                         [ 3, { 'BODY[1.MIME]' => @mime_subject_mail.header.raw_source } ]
                       ],
                       imap_fetch.call(msg_set[1..-1], 'BODY.PEEK[1.MIME]'))

          assert_fetch_body_sections = lambda{|body_section_table|
            res = imap_fetch.call(msg_set[2], body_section_table.keys)
            assert_equal(1, res.length)
            assert_equal(2, res[0].seqno)
            if (uid) then
              assert_equal(body_section_table.size + 1, res[0].attr.size)
              assert_equal(uid_offset + 2, res[0].attr['UID'])
            else
              assert_equal(body_section_table.size, res[0].attr.size)
            end
            for body_section, expected_fetch_data in body_section_table
              body_section = body_section.dup
              body_section.upcase!
              body_section.sub!(/\.PEEK/, '')
              assert_equal(expected_fetch_data, res[0].attr[body_section], body_section)
            end
          }

          assert_fetch_body_sections.call({ 'BODY.PEEK[1]'       => @mpart_mail.parts[0].body.raw_source,
                                            'BODY.PEEK[2]'       => @mpart_mail.parts[1].body.raw_source,
                                            'BODY.PEEK[3]'       => @mpart_mail.parts[2].body.raw_source,
                                            'BODY.PEEK[3.1]'     => @mpart_mail.parts[2].message.parts[0].body.raw_source,
                                            'BODY.PEEK[3.2]'     => @mpart_mail.parts[2].message.parts[1].body.raw_source,
                                            'BODY.PEEK[4]'       => @mpart_mail.parts[3].body.raw_source,
                                            'BODY.PEEK[4.1]'     => @mpart_mail.parts[3].parts[0].body.raw_source,
                                            'BODY.PEEK[4.2]'     => @mpart_mail.parts[3].parts[1].body.raw_source,
                                            'BODY.PEEK[4.2.1]'   => @mpart_mail.parts[3].parts[1].message.parts[0].body.raw_source,
                                            'BODY.PEEK[4.2.2]'   => @mpart_mail.parts[3].parts[1].message.parts[1].body.raw_source,
                                            'BODY.PEEK[4.2.2.1]' => @mpart_mail.parts[3].parts[1].message.parts[1].parts[0].body.raw_source,
                                            'BODY.PEEK[4.2.2.2]' => @mpart_mail.parts[3].parts[1].message.parts[1].parts[1].body.raw_source
                                          })

          assert_fetch_body_sections.call({ 'BODY.PEEK[1.MIME]'       => @mpart_mail.parts[0].header.raw_source,
                                            'BODY.PEEK[2.MIME]'       => @mpart_mail.parts[1].header.raw_source,
                                            'BODY.PEEK[3.MIME]'       => @mpart_mail.parts[2].header.raw_source,
                                            'BODY.PEEK[3.1.MIME]'     => @mpart_mail.parts[2].message.parts[0].header.raw_source,
                                            'BODY.PEEK[3.2.MIME]'     => @mpart_mail.parts[2].message.parts[1].header.raw_source,
                                            'BODY.PEEK[4.MIME]'       => @mpart_mail.parts[3].header.raw_source,
                                            'BODY.PEEK[4.1.MIME]'     => @mpart_mail.parts[3].parts[0].header.raw_source,
                                            'BODY.PEEK[4.2.MIME]'     => @mpart_mail.parts[3].parts[1].header.raw_source,
                                            'BODY.PEEK[4.2.1.MIME]'   => @mpart_mail.parts[3].parts[1].message.parts[0].header.raw_source,
                                            'BODY.PEEK[4.2.2.MIME]'   => @mpart_mail.parts[3].parts[1].message.parts[1].header.raw_source,
                                            'BODY.PEEK[4.2.2.1.MIME]' => @mpart_mail.parts[3].parts[1].message.parts[1].parts[0].header.raw_source,
                                            'BODY.PEEK[4.2.2.2.MIME]' => @mpart_mail.parts[3].parts[1].message.parts[1].parts[1].header.raw_source
                                          })

          assert_fetch_body_sections.call({ 'BODY.PEEK[3.HEADER]'   => @mpart_mail.parts[2].message.header.raw_source,
                                            'BODY.PEEK[4.2.HEADER]' => @mpart_mail.parts[3].parts[1].message.header.raw_source
                                          })

          assert_fetch_body_sections.call({ 'BODY.PEEK[3.TEXT]'   => @mpart_mail.parts[2].message.body.raw_source,
                                            'BODY.PEEK[4.2.TEXT]' => @mpart_mail.parts[3].parts[1].message.body.raw_source
                                          })
        }
        assert_imap_fetch_read_only_seqno = lambda{ assert_imap_fetch_read_only.call(false) }
        assert_imap_fetch_read_only_uid   = lambda{ assert_imap_fetch_read_only.call(true) }

        assert_imap_store = lambda{|uid|
          if (uid) then
            imap_store = imap.method(:uid_store)
            imap_fetch = imap.method(:uid_fetch)
            seqno = uid_offset + 3
          else
            imap_store = imap.method(:store)
            imap_fetch = imap.method(:fetch)
            seqno = 3
          end

          assert_equal([ :Answered, :Flagged, :Deleted, :Seen, :Draft, :Recent ],
                       imap_store.call(seqno, 'FLAGS', [ :Answered, :Flagged, :Deleted, :Seen, :Draft ])[0].attr['FLAGS'])
          assert_equal([ :Answered, :Flagged, :Deleted, :Seen, :Draft, :Recent ],
                       imap_fetch.call(seqno, 'FLAGS')[0].attr['FLAGS'])

          assert_nil(imap_store.call(seqno, 'FLAGS.SILENT', []))
          assert_equal([ :Recent ],
                       imap_fetch.call(seqno, 'FLAGS')[0].attr['FLAGS'])

          assert_equal([ :Answered, :Deleted, :Draft, :Recent ],
                       imap_store.call(seqno, '+FLAGS', [ :Answered, :Deleted, :Draft ])[0].attr['FLAGS'])
          assert_equal([ :Answered, :Deleted, :Draft, :Recent ],
                       imap_fetch.call(seqno, 'FLAGS')[0].attr['FLAGS'])

          assert_equal([ :Recent ], imap_store.call(seqno, '-FLAGS', [ :Answered, :Deleted, :Draft ])[0].attr['FLAGS'])
          assert_equal([ :Recent ], imap_fetch.call(seqno, 'FLAGS')[0].attr['FLAGS'])

          assert_nil(imap_store.call(seqno, '+FLAGS.SILENT', [ :Flagged, :Seen ]))
          assert_equal([ :Flagged, :Seen, :Recent ], imap_fetch.call(seqno, 'FLAGS')[0].attr['FLAGS'])

          assert_nil(imap_store.call(seqno, '-FLAGS.SILENT', [ :Flagged, :Seen ]))
          assert_equal([ :Recent ], imap_fetch.call(seqno, 'FLAGS')[0].attr['FLAGS'])
        }
        assert_imap_store_seqno = lambda{ assert_imap_store.call(false) }
        assert_imap_store_uid   = lambda{ assert_imap_store.call(true) }

        assert_imap_store_read_only = lambda{|uid|
          if (uid) then
            imap_store = imap.method(:uid_store)
            seqno = uid_offset + 3
          else
            imap_store = imap.method(:store)
            seqno = 3
          end

          assert_imap_no_response[/cannot store in read-only mode/] {
            imap_store.call(seqno, 'FLAGS', [ :Answered, :Flagged, :Deleted, :Seen, :Draft ])
          }
          assert_imap_no_response[/cannot store in read-only mode/] {
            imap_store.call(seqno, 'FLAGS.SILENT', [])
          }
          assert_imap_no_response[/cannot store in read-only mode/] {
            imap_store.call(seqno, '+FLAGS', [ :Answered, :Deleted, :Draft ])
          }
          assert_imap_no_response[/cannot store in read-only mode/] {
            imap_store.call(seqno, '-FLAGS', [ :Answered, :Deleted, :Draft ])
          }
          assert_imap_no_response[/cannot store in read-only mode/] {
            imap_store.call(seqno, '+FLAGS.SILENT', [ :Flagged, :Seen ])
          }
          assert_imap_no_response[/cannot store in read-only mode/] {
            imap_store.call(seqno, '-FLAGS.SILENT', [ :Flagged, :Seen ])
          }
        }
        assert_imap_store_read_only_seqno = lambda{ assert_imap_store_read_only.call(false) }
        assert_imap_store_read_only_uid   = lambda{ assert_imap_store_read_only.call(true) }

        assert_imap_fetch_seen = lambda{|uid, read_only|
          if (uid) then
            imap_fetch = imap.method(:uid_fetch)
            imap_store = imap.method(:uid_store)
            seqno = uid_offset + 3
            fetch_data = lambda{|attr| attr.merge({ 'UID' => seqno }) }
          else
            imap_fetch = imap.method(:fetch)
            imap_store = imap.method(:store)
            seqno = 3
            fetch_data = lambda{|attr| attr }
          end

          if (read_only) then
            assert_fetch = lambda{|attribute, expected_fetch_data|
              assert_equal(fetch_data[
                             { attribute => expected_fetch_data }
                           ],
                           imap_fetch.call(seqno, attribute)[0].attr,
                           attribute)
              assert_not_include(imap_fetch.call(seqno, 'FLAGS')[0].attr['FLAGS'], :Seen, attribute)
            }
          else
            assert_fetch = lambda{|attribute, expected_fetch_data|
              assert_equal(fetch_data[
                             { attribute => expected_fetch_data,
                               'FLAGS' => [ :Seen, :Recent ]
                             }
                           ],
                           imap_fetch.call(seqno, attribute)[0].attr,
                           attribute)
              assert_include(imap_fetch.call(seqno, 'FLAGS')[0].attr['FLAGS'], :Seen, attribute)
              imap_store.call(seqno, '-FLAGS.SILENT', [ :Seen ])
            }
          end

          assert_fetch.call('BODY[]',      @mime_subject_mail.raw_source)
          assert_fetch.call('RFC822',      @mime_subject_mail.raw_source)
          assert_fetch.call('RFC822.TEXT', @mime_subject_mail.body.raw_source)
        }
        assert_imap_fetch_seen_seqno           = lambda{ assert_imap_fetch_seen.call(false, false) }
        assert_imap_fetch_seen_uid             = lambda{ assert_imap_fetch_seen.call(true,  false) }
        assert_imap_fetch_seen_read_only_seqno = lambda{ assert_imap_fetch_seen.call(false, true) }
        assert_imap_fetch_seen_read_only_uid   = lambda{ assert_imap_fetch_seen.call(true,  true) }

        # State: Authenticated -> Selected (read-only)
        imap.examine('INBOX')

        # IMAP commands for Any State
        assert_equal(%w[ IMAP4REV1 UIDPLUS IDLE AUTH=PLAIN AUTH=CRAM-MD5 ], imap.capability)
        imap.noop

        # IMAP commands for Selected State
        imap.check
        assert_imap_search_seqno.call
        assert_imap_search_uid.call
        assert_imap_fetch_read_only_seqno.call
        assert_imap_fetch_read_only_uid.call
        assert_imap_store_read_only_seqno.call
        assert_imap_store_read_only_uid.call
        assert_imap_fetch_seen_read_only_seqno.call
        assert_imap_fetch_seen_read_only_uid.call

        # State: Authenticated <- Selected
        imap.close
        assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))

        # State: Authenticated -> Selected
        imap.select('INBOX')

        # IMAP commands for Any State
        assert_equal(%w[ IMAP4REV1 UIDPLUS IDLE AUTH=PLAIN AUTH=CRAM-MD5 ], imap.capability)
        imap.noop

        # IMAP commands for Selected State
        imap.check
        assert_imap_search_seqno.call
        assert_imap_search_uid.call
        assert_imap_fetch_read_only_seqno.call
        assert_imap_fetch_read_only_uid.call
        assert_imap_store_seqno.call
        assert_imap_store_uid.call
        assert_imap_fetch_seen_seqno.call
        assert_imap_fetch_seen_uid.call

        # State: Authenticated <- Selected
        imap.close
        status['RECENT'] = 0
        assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))

        # IMAP commands for Selected State
        assert_no_response_selected_state_imap_commands.call(/not selected/)

        imap_copy_count = 0
        imap.create('COPY')
        assert_imap_copy = lambda{|uid, read_only|
          imap_copy_count += 1

          if (uid) then
            imap_copy = imap.method(:uid_copy)
            seqno = uid_offset + 1
          else
            imap_copy = imap.method(:copy)
            seqno = 1
          end

          if (read_only) then
            imap_select = imap.method(:examine)
          else
            imap_select = imap.method(:select)
          end

          imap_select.call('INBOX')
          imap_copy.call(seqno, 'COPY')
          imap.close
          assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))

          imap.examine('COPY')
          res = imap.fetch('*', %w(BODY[] INTERNALDATE FLAGS))
          assert_equal(1, res.length)
          assert_equal(imap_copy_count, res[0].seqno)
          assert_equal(3, res[0].attr.size)
          assert_equal(@simple_mail.raw_source,                          res[0].attr['BODY[]'])
          assert_equal(@simple_mail.date.getutc.strftime(imap_date_fmt), res[0].attr['INTERNALDATE'])
          assert_equal([ :Answered, :Flagged ],                          res[0].attr['FLAGS'])
          imap.close
        }
        assert_imap_copy_seqno           = lambda{ assert_imap_copy.call(false, false) }
        assert_imap_copy_uid             = lambda{ assert_imap_copy.call(true,  false) }
        assert_imap_copy_read_only_seqno = lambda{ assert_imap_copy.call(false, true) }
        assert_imap_copy_read_only_uid   = lambda{ assert_imap_copy.call(true,  true) }

        # IMAP copy command
        assert_imap_copy_read_only_seqno.call
        assert_imap_copy_read_only_uid.call
        assert_imap_copy_seqno.call
        assert_imap_copy_uid.call

        # IMAP idle command
        assert_imap_idle = lambda{|read_only|
          if (read_only) then
            imap.examine('INBOX')
          else
            imap.select('INBOX')
          end
          imap_connect(use_ssl) {|another_imap|
            start_imap_idle_thread = lambda{
              mutex = Mutex.new
              spin_lock = true

              th = Thread.new{
                response_list = []
                imap.idle{|res|
                  mutex.synchronize{ spin_lock = false } # unlock by continuation request
                  response_list << res
                }
                response_list
              }

              timeout(10) {
                while (mutex.synchronize{ spin_lock })
                  sleep(0.1)
                end
              }

              th
            }

            imap_idle_done = lambda{
              # ad hoc way to avoid the race condition between `Net::IMAP#add_response_handler' and `Net::IMAP#idle_done'
              sleep(0.1)

              imap.idle_done
            }

            another_imap.login('foo', 'foo')
            another_imap.select('INBOX')

            th = start_imap_idle_thread.call
            another_imap.append('INBOX', 'test', [ :Deleted ])
            imap_idle_done.call

            response_list = th.value
            assert_equal(3, response_list.length)
            assert_instance_of(Net::IMAP::ContinuationRequest, response_list[0])
            assert_equal([ 'EXISTS', status['MESSAGES'] + 1 ], response_list[1].to_h.values_at(:name, :data))
            assert_equal([ 'RECENT', status['RECENT']   + 1 ], response_list[2].to_h.values_at(:name, :data))

            th = start_imap_idle_thread.call
            another_imap.copy('*', 'INBOX')
            imap_idle_done.call

            response_list = th.value
            assert_equal(3, response_list.length)
            assert_instance_of(Net::IMAP::ContinuationRequest, response_list[0])
            assert_equal([ 'EXISTS', status['MESSAGES'] + 2 ], response_list[1].to_h.values_at(:name, :data))
            assert_equal([ 'RECENT', status['RECENT']   + 2 ], response_list[2].to_h.values_at(:name, :data))

            th = start_imap_idle_thread.call
            another_imap.store('*', '+FLAGS.SILENT', [ :Deleted ])
            another_imap.expunge
            imap_idle_done.call

            response_list = th.value
            assert_equal(3, response_list.length)
            assert_instance_of(Net::IMAP::ContinuationRequest, response_list[0])
            assert_equal([ 'EXPUNGE', status['MESSAGES'] + 2 ], response_list[1].to_h.values_at(:name, :data))
            assert_equal([ 'EXPUNGE', status['MESSAGES'] + 1 ], response_list[2].to_h.values_at(:name, :data))

            another_imap.close
            another_imap.logout
          }
          imap.close
        }
        assert_imap_idle.call(true)
        assert_imap_idle.call(false)
        status['UIDNEXT'] += 2 * 2
        assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))

        # mail delivery user
        assert_not_include(imap.capability, 'X-RIMS-MAIL-DELIVERY-USER')
        imap_connect(use_ssl) {|post_mail|
          assert_not_include(post_mail.capability, 'X-RIMS-MAIL-DELIVERY-USER')

          post_mail.login('#postman', '#postman')
          assert_include(post_mail.capability, 'X-RIMS-MAIL-DELIVERY-USER')

          post_mail.append(RIMS::Protocol::Decoder.encode_delivery_target_mailbox('foo', 'INBOX'),
                           'mail delivery test')
          status['MESSAGES'] += 1
          status['RECENT']   += 1
          status['UNSEEN']   += 1
          status['UIDNEXT']  += 1
          assert_equal(status, imap.status('INBOX', %w[ MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN ]))

          post_mail.logout
        }

        imap.examine('INBOX')
        assert_equal('mail delivery test', imap.fetch('*', 'RFC822')[0].attr['RFC822'])
        imap.close
      }
    end

    data('default'       => {},
         'use_ssl'       => { use_ssl: true },
         'multi-process' => { process_num: 4 },
         'use_ssl,multi-process' => {
           use_ssl: true,
           process_num: 4
         })
    def test_system_autologout(data)
      use_ssl     = (data.key? :use_ssl) ? data[:use_ssl] : false
      process_num = data[:process_num] || 0

      command_wait_timeout_seconds = 0.1
      config = {
        server: {
          process_num: process_num
        },
        drb_services: {
          process_num: process_num
        },
        connection: {
          read_polling_interval_seconds: command_wait_timeout_seconds / 100,
          command_wait_timeout_seconds: command_wait_timeout_seconds
        }
      }

      run_server(use_ssl: use_ssl, optional: config) {
        # Not Authenticated State
        imap_connect(use_ssl) {|imap|
          assert_not_include(imap.responses, 'BYE')
          sleep(command_wait_timeout_seconds * 1.5)
          assert_include(imap.responses, 'BYE')
          assert_match(/autologout/, imap.responses['BYE'].last.text)
          assert(imap.disconnected?)
        }

        # Authenticated State
        imap_connect(use_ssl) {|imap|
          imap.login('foo', 'foo')
          assert_not_include(imap.responses, 'BYE')
          sleep(command_wait_timeout_seconds * 1.5)
          assert_include(imap.responses, 'BYE')
          assert_match(/autologout/, imap.responses['BYE'].last.text)
          assert(imap.disconnected?)
        }

        # Selected State (read-only)
        imap_connect(use_ssl) {|imap|
          imap.login('foo', 'foo')
          imap.examine('INBOX')
          assert_not_include(imap.responses, 'BYE')
          sleep(command_wait_timeout_seconds * 1.5)
          assert_include(imap.responses, 'BYE')
          assert_match(/autologout/, imap.responses['BYE'].last.text)
          assert(imap.disconnected?)
        }

        # Selected State
        imap_connect(use_ssl) {|imap|
          imap.login('foo', 'foo')
          imap.select('INBOX')
          assert_not_include(imap.responses, 'BYE')
          sleep(command_wait_timeout_seconds * 1.5)
          assert_include(imap.responses, 'BYE')
          assert_match(/autologout/, imap.responses['BYE'].last.text)
          assert(imap.disconnected?)
        }

        # IMAP IDLE command
        imap_connect(use_ssl) {|imap|
          imap.login('foo', 'foo')
          imap.select('INBOX')
          assert_not_include(imap.responses, 'BYE')
          timeout(command_wait_timeout_seconds * 10) {
            error = assert_raise(Net::IMAP::ByeResponseError) {
              imap.idle{
                # nothing to do
              }
            }
            assert_match(/autologout/, error.message)
          }
          assert_include(imap.responses, 'BYE')
          assert_match(/autologout/, imap.responses['BYE'].last.text)
          assert(imap.disconnected?)
        }
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
