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
  puts "\n📊 Test Suite — 390 tests, 1191 assertions"
  puts "  test_common.rb               — 56 unit tests"
  puts "  test_integration.rb          — 29 integration tests"
  puts "  test_cache.rb                — 27 unit tests"
  puts "  test_pkgbuild_validation.rb  — 31 unit tests"
  puts "  test_platform.rb             — 34 unit tests"
  puts "  test_uninstall.rb            —  7 unit tests"
  puts "  test_query.rb                — 12 unit tests"
  puts "  test_translate.rb            —  4 unit tests"
  puts "  test_aggregate.rb            —  4 unit tests"
  puts "  test_end_to_end.rb           — 15 end-to-end tests"
  puts "  test_result.rb               —  5 unit tests"
  puts "  test_reporter.rb             —  4 unit tests"
  puts "  test_query_installed.rb      —  3 unit tests"
  puts "  test_verify_check.rb         —  2 unit tests"
  puts "  test_fix.rb                  — 16 unit tests"
  puts "  test_outdated.rb             —  7 unit tests"
  puts "  test_bump.rb                 — 19 unit tests"
  puts "  test_build_pipeline.rb       — 10 unit tests"
  puts "  test_atomic_write.rb         — 11 unit tests"
  puts "  test_cache_eviction.rb       —  2 unit tests"
  puts "  test_cli_syntax.rb           — 20 unit tests"
  puts "  test_drift_cms.rb            —  4 unit tests"
  puts "  test_install_handlers.rb     —  2 unit tests"
  puts "  test_io.rb                   —  9 unit tests"
  puts "  test_network_failures.rb     —  9 unit tests"
  puts "  test_package_resolver.rb     —  8 unit tests"
  puts "  test_processor_loader.rb     —  5 unit tests"
  puts "  test_schema_engine.rb        —  8 unit tests"
  puts "  test_source_extract_tar_gz.rb —  9 unit tests"
  puts "  test_symlink_hardening.rb    —  6 unit tests"
  puts "  test_transaction_rollback.rb —  7 unit tests"
  puts "  test_tui_selector.rb         —  5 unit tests"
  puts ""
  puts "Run: rake test"
end
