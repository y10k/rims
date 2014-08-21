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
task :readme do
  sh "markdown README.md >README.html"
end

desc 'Remove README.html.'
task :clobber_readme do
  rm_f 'README.html'
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
