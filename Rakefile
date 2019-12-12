# -*- coding: utf-8 -*-

require 'bundler/gem_tasks'
require 'pathname'
require 'rake/clean'
require 'rake/testtask'
require 'rdoc/task'

Rake::TestTask.new do |task|
  if ((ENV.key? 'RUBY_DEBUG') && (! ENV['RUBY_DEBUG'].empty?)) then
    task.ruby_opts << '-d'
  end
end

Rake::TestTask.new(:test_cmd) do |task|
  task.description = 'Run tests for rims command'
  task.pattern = 'test/cmd/test*.rb'
  task.options = '-v'
  if ((ENV.key? 'RUBY_DEBUG') && (! ENV['RUBY_DEBUG'].empty?)) then
    task.ruby_opts << '-d'
  end
end

desc 'Run all tests'
task :test_all => [ :test, :test_cmd ]

Rake::RDocTask.new do |rd|
  rd.rdoc_files.include('lib/**/*.rb')
end

rule '.html' => '.md' do |t|
  sh "pandoc --from=markdown --to=html5 --standalone --self-contained --css=$HOME/.pandoc/github.css --output=#{t.name} #{t.source}"
end

desc 'Build README.html from markdown source'
task :readme => %w[ README.html ]
CLOBBER.include 'README.html'

desc 'Build CHANGELOG.html from markdown source'
task :changelog => %w[ CHANGELOG.html ]
CLOBBER.include 'CHANGELOG.html'

namespace :test_cert do
  tls_dir = Pathname('test/tls')

  directory tls_dir.to_path
  CLOBBER.include tls_dir.to_path

  desc 'Delete TLS certificate files for test'
  task :delete do
    rm_rf tls_dir.to_path
  end

  ca_priv_key                    = tls_dir / 'ca.priv_key'
  ca_cert_sign_req               = tls_dir / 'ca.cert_sign_req'
  ca_cert                        = tls_dir / 'ca.cert'
  server_priv_key                = tls_dir / 'server.priv_key'
  server_localhost_cert_sign_req = tls_dir / 'server_localhost.cert_sign_req'
  server_localhost_cert          = tls_dir / 'server_localhost.cert'

  file ca_priv_key.to_path => [ tls_dir ].map(&:to_path) do
    sh "openssl genrsa 2048 >#{ca_priv_key}"
  end

  file ca_cert_sign_req.to_path => [ tls_dir, ca_priv_key ].map(&:to_path) do
    sh "openssl req -new -key #{ca_priv_key} -sha256 -subj '/C=JP/ST=Tokyo/L=Tokyo/O=Private/OU=Home/CN=*' >#{ca_cert_sign_req}"
  end

  file ca_cert.to_path => [ tls_dir, ca_priv_key, ca_cert_sign_req ].map(&:to_path) do
    sh "openssl x509 -req -signkey #{ca_priv_key} -sha256 -days 3650 <#{ca_cert_sign_req} >#{ca_cert}"
  end

  file server_priv_key.to_path => [ tls_dir ].map(&:to_path) do
    sh "openssl genrsa 2048 >#{server_priv_key}"
  end

  file server_localhost_cert_sign_req.to_path => [ tls_dir, server_priv_key ].map(&:to_path) do
    sh "openssl req -new -key #{server_priv_key} -sha256 -subj '/C=JP/ST=Tokyo/L=Tokyo/O=Private/OU=Home/CN=localhost' >#{server_localhost_cert_sign_req}"
  end

  file server_localhost_cert.to_path => [ tls_dir, ca_cert, ca_priv_key, server_localhost_cert_sign_req ].map(&:to_path) do
    sh "openssl x509 -req -CA #{ca_cert} -CAkey #{ca_priv_key} -CAcreateserial -sha256 -days 3650 <#{server_localhost_cert_sign_req} >#{server_localhost_cert}"
  end

  desc 'Make TLS certificate files for test'
  task :make => [ ca_priv_key, ca_cert, server_priv_key, server_localhost_cert ].map(&:to_path)

  desc 'Show TLS certificate files for test'
  task :show => :make do
    sh "openssl rsa -text -noout <#{ca_priv_key}"
    sh "openssl req -text -noout <#{ca_cert_sign_req}"
    sh "openssl x509 -text -noout <#{ca_cert}"
    sh "openssl rsa -text -noout <#{server_priv_key}"
    sh "openssl req -text -noout <#{server_localhost_cert_sign_req}"
    sh "openssl x509 -text -noout <#{server_localhost_cert}"
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
