# frozen_string_literal: true

# Rakefile for SSoT test suite
# Usage: rake test, rake test:unit, rake test:integration

require 'rake'
require 'rake/testtask'

desc 'Run all tests'
task default: :test

desc 'Run all tests'
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb', 'test/**/test_*.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run unit tests only'
Rake::TestTask.new(:test_unit) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_common.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run integration tests only'
Rake::TestTask.new(:test_integration) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_integration.rb']
  t.verbose = false
  t.warning = false
end

desc 'Print test summary'
task :summary do
  puts "\n📊 Test Coverage"
  puts "  Unit:       test_common.rb (compare_versions, format_version, validation)"
  puts "  Integration: test_integration.rb (build, install, check, uninstall)"
  puts "  Fixtures:   test/fixtures/"
  puts "\nRun: rake test"
end
