# frozen_string_literal: true

# Test helper — sets up load paths and shared utilities

$LOAD_PATH.unshift File.expand_path('..', __dir__)
$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'ssot', 'lib')

require 'minitest/autorun'
require 'pathname'
require 'tmpdir'
require 'fileutils'

ROOT = Pathname.new(__dir__).parent.expand_path
SSOT_ROOT = ROOT.join('ssot')
FIXTURES_ROOT = ROOT.join('test', 'fixtures')

# Load SSoT modules
require 'ssot/lib/common'

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

Minitest::Test.include TestHelpers
