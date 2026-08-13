# frozen_string_literal: true

# Validates Step 1: Rulepack has a real library spine.
#
# CRITICAL: loads Rulepack the way an EXTERNAL consumer does — `require 'rulepack'`
# via the lib load path — and deliberately does NOT load bin/rulepack. Before
# Step 1 this path raised: NameError: uninitialized constant Rulepack::Error.

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')

require 'minitest/autorun'
require 'rulepack'
require 'rulepack/cli_parser'

class TestRulepackLibrarySpine < Minitest::Test
  def test_library_root_loads_without_cli_side_effects
    refute defined?(Rulepack::CLI), 'library load must not define Rulepack::CLI'
  end

  def test_base_error_is_defined_by_the_library
    assert defined?(Rulepack::Error), 'Rulepack::Error must be defined without bin/rulepack'
    assert Rulepack::Error < StandardError
  end

  def test_error_hierarchy_is_rescuable_as_base_and_standard
    assert Rulepack::MissingOptionValue < Rulepack::CliError
    assert Rulepack::CliError < Rulepack::ConfigError
    assert Rulepack::ConfigError < Rulepack::Error
    assert Rulepack::Error < StandardError
    assert Rulepack::PathTraversalError < Rulepack::SecurityError
    assert Rulepack::SecurityError < Rulepack::Error
  end

  def test_cli_parser_raises_typed_error_for_missing_value
    err = assert_raises(Rulepack::MissingOptionValue) do
      Rulepack::CliParser.parse(['--target'])
    end
    assert_equal 'Missing value for --target', err.message
    assert_kind_of Rulepack::Error, err
  end

  def test_cli_parser_raises_typed_error_for_invalid_value
    err = assert_raises(Rulepack::InvalidOptionValue) do
      Rulepack::CliParser.parse(['--format', 'xml'])
    end
    assert_match(/Invalid --format value: xml/, err.message)
    assert_kind_of Rulepack::Error, err
  end

  def test_existing_rescue_standarderror_callers_still_catch
    caught = assert_raises(StandardError) { Rulepack::CliParser.parse(['--project']) }
    assert_kind_of Rulepack::MissingOptionValue, caught
  end

  def test_valid_parse_is_unaffected
    opts = Rulepack::CliParser.parse(['memory', '--target', 'opencode', '--dry-run'])
    assert_equal 'memory', opts[:package_name]
    assert_equal 'opencode', opts[:target]
    assert opts[:dry_run]
  end
end
