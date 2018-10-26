# -*- coding: utf-8 -*-

require 'bundler/gem_tasks'
require 'rake/clean'
require 'rake/testtask'
require 'rdoc/task'

Rake::TestTask.new do |task|
  if ((ENV.key? 'RUBY_DEBUG') && (! ENV['RUBY_DEBUG'].empty?)) then
    task.ruby_opts << '-d'
  end
end

Rake::RDocTask.new do |rd|
  rd.rdoc_files.include('lib/**/*.rb')
end

desc 'Build README.html from markdown source.'
task :readme => %w[ README.html ]

file 'README.html' => [ 'README.md' ] do
  sh "pandoc --from=markdown --to=html5 --standalone --self-contained --css=$HOME/.pandoc/github.css --output=README.html README.md"
end
CLOBBER.include 'README.html'

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
