# frozen_string_literal: true

# Test helper — sets up load paths and shared utilities

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')
$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib', 'rulepack')

require 'minitest/autorun'
require 'pathname'
require 'tmpdir'
require 'fileutils'

ROOT = Pathname.new(__dir__).parent.expand_path

# Platform Registry Memoization Contract:
# ========================================
# The platform registry is cached after first load via Rulepack::Common.load_platform_registry
# (see lib/rulepack/platform.rb:54-67). Tests that modify data/registry/platforms.yaml or
# data/platforms/*.yaml MUST call Rulepack::Common.clear_platform_registry_cache! in their
# setup/teardown to ensure changes are picked up. Otherwise, the cached registry will cause
# false test passes or stale configuration bugs.
#
# Example:
#   def setup
#     Rulepack::Common.clear_platform_registry_cache!
#     # ... modify platform YAML ...
#   end
#
FIXTURES_ROOT = ROOT.join('test', 'fixtures')

# Load Rulepack modules
require 'rulepack/common'

module TestHelpers
  # Create a temporary directory and yield its Pathname
  def with_tmpdir
    Dir.mktmpdir do |tmpdir|
      yield Pathname.new(tmpdir)
    end
  end

  # Write a fixture file and return its Pathname
  def write_fixture(relative_path, content)
    path = FIXTURES_ROOT.join(relative_path)
    path.parent.mkpath
    path.write(content)
    path
  end

  # Clean up a fixture file
  def cleanup_fixture(relative_path)
    path = FIXTURES_ROOT.join(relative_path)
    path.delete if path.exist?
  end
end

# Set environment flag to disable interactive CLI TUI prompts during testing
ENV['RULEPACK_TEST'] = '1'

Minitest::Test.include TestHelpers
