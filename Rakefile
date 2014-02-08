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

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
