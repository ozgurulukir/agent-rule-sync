# frozen_string_literal: true

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

desc 'Print test summary'
task :summary do
  puts "\n📊 Test Suite — 305 tests, 1040 assertions"
  puts "  test_common.rb               — 48 unit tests"
  puts "  test_integration.rb          — 29 integration tests"
  puts "  test_cache.rb                — 24 unit tests"
  puts "  test_pkgbuild_validation.rb  — 31 unit tests"
  puts "  test_platform.rb             — 33 unit tests"
  puts "  test_uninstall.rb            —  7 unit tests"
  puts "  test_query.rb                — 16 unit tests"
  puts "  test_translate.rb            —  4 unit tests"
  puts "  test_aggregate.rb            —  4 unit tests"
  puts "  test_end_to_end.rb           — 14 end-to-end tests"
  puts ""
  puts "Run: rake test"
end
