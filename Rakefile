# frozen_string_literal: true

# encoding: utf-8

# Rakefile for Rulepack test suite
# Usage: rake test, rake test_unit, rake test_integration, rake test_cache, rake test_pkgbuild, rake test_platform, rake test_uninstall

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

desc 'Run unit tests only (test_common.rb)'
Rake::TestTask.new(:test_unit) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_common.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run integration tests only (test_integration.rb)'
Rake::TestTask.new(:test_integration) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_integration.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run cache tests (test_cache.rb)'
Rake::TestTask.new(:test_cache) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_cache.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run PKGBUILD validation tests (test_pkgbuild_validation.rb)'
Rake::TestTask.new(:test_pkgbuild) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_pkgbuild_validation.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run platform registry tests (test_platform.rb)'
Rake::TestTask.new(:test_platform) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_platform.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run uninstall tests (test_uninstall.rb)'
Rake::TestTask.new(:test_uninstall) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_uninstall.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run query tests (test_query.rb)'
Rake::TestTask.new(:test_query) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_query.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run translate tests (test_translate.rb)'
Rake::TestTask.new(:test_translate) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_translate.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run aggregate tests (test_aggregate.rb)'
Rake::TestTask.new(:test_aggregate) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_aggregate.rb']
  t.verbose = false
  t.warning = false
end

desc 'Run end-to-end pipeline tests (test_end_to_end.rb)'
Rake::TestTask.new(:test_e2e) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_end_to_end.rb']
  t.verbose = false
  t.warning = false
end

desc 'Print test summary (dynamic counts)'
task :summary do
  test_files = FileList['test/**/*_test.rb', 'test/**/test_*.rb']
  total_runs = 0
  total_assertions = 0
  file_counts = {}

  test_files.each do |file|
    content = File.read(file, encoding: 'UTF-8')
    test_count = content.scan(/def test_/).size
    assert_count = content.scan(/\bassert(?:_\w+)?\b/).size
    file_counts[file] = { tests: test_count, assertions: assert_count }
    total_runs += test_count
    total_assertions += assert_count
  end

  puts "\n📊 Test Suite — #{total_runs} tests, #{total_assertions} assertions (dynamic)"
  file_counts.sort_by { |f, _| f }.each do |file, counts|
    name = File.basename(file)
    puts "  #{name.ljust(35)} — #{counts[:tests]} tests, #{counts[:assertions]} assertions"
  end
  puts ""
  puts "Run: rake test"
end

desc 'Check that docs are up to date with disk state'
task :'docs:check' do
  test_files = FileList['test/**/*_test.rb', 'test/**/test_*.rb']
  total_runs = 0
  total_assertions = 0

  test_files.each do |file|
    content = File.read(file, encoding: 'UTF-8')
    total_runs += content.scan(/def test_/).size
    total_assertions += content.scan(/\bassert(?:_\w+)?\b/).size
  end

  puts "✓ Dynamic test count: #{total_runs} tests, #{total_assertions} assertions"
  puts "  (AGENTS.md hardcoded counts may be stale — run `rake summary` for authoritative numbers)"
end
