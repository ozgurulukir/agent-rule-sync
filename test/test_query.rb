# frozen_string_literal: true

# Unit tests for Rulepack::Query module
# Covers: run, list_platforms, show_package, search, orphans, depends, provides, help

require_relative 'helper'
require_relative File.join(File.expand_path('..', __dir__), 'lib', 'rulepack', 'query')

class TestQueryRun < Minitest::Test
  def test_run_help
    out, err = capture_io { Rulepack::Query.run(['help']) }
    assert_match(/Rulepack Database Query Tool/, out)
    assert_match(/list-packages/, out)
  end

  def test_run_help_is_default
    out, err = capture_io { Rulepack::Query.run([]) }
    assert_match(/Rulepack Database Query Tool/, out)
  end

  def test_run_aliases
    out, err = capture_io { Rulepack::Query.run(['lp']) }
    assert_match(/Platforms/, out)

    out, err = capture_io { Rulepack::Query.run(['h']) }
    assert_match(/Rulepack Database Query Tool/, out)
  end
end

class TestQueryPrintHelp < Minitest::Test
  def test_print_help_shows_commands
    out, err = capture_io { Rulepack::Query.print_help }
    assert_match(/list-packages/, out)
    assert_match(/installed/, out)
    assert_match(/show/, out)
    assert_match(/search/, out)
    assert_match(/check/, out)
    assert_match(/orphans/, out)
    assert_match(/depends/, out)
    assert_match(/provides/, out)
    assert_match(/help/, out)
  end
end

class TestQueryListPlatforms < Minitest::Test
  def test_list_platforms_shows_registry
    out, err = capture_io { Rulepack::Query.list_platforms }
    assert_match(/Platforms/, out)
    assert_match(/opencode/, out)
    assert_match(/crush/, out)
  end
end

class TestQuerySearch < Minitest::Test
  def test_search_no_results
    out, err = capture_io { Rulepack::Query.search('xyznonexistent12345') }
    assert_match(/No packages found/, out)
  end
end

class TestQueryShowProvides < Minitest::Test
  def test_show_provides_no_providers
    out, err = capture_io { Rulepack::Query.show_provides('xyznonexistent') }
    assert_match(/No packages provide/, out)
  end
end

class TestQueryLoadIndex < Minitest::Test
  def test_load_index_returns_hash
    index = Rulepack::Query.load_index
    assert_instance_of Hash, index
    assert index.key?(:packages)
  end
end
