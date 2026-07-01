# frozen_string_literal: true

require_relative 'helper'
require_relative '../lib/rulepack/query'

class TestQueryInstalled < Minitest::Test
  def test_installed_returns_result_for_directory_platform
    result = Rulepack::Query.installed('opencode')
    assert result.success?
    assert_equal 'opencode', result.data[:platform_id]
    assert result.data.key?(:items)
    assert result.data.key?(:base_path)
  end

  def test_installed_fails_for_unknown_platform
    result = Rulepack::Query.installed('does-not-exist')
    assert result.failure?
    assert_match(/Unknown platform/, result.errors.first)
  end

  def test_installed_text_output
    out, _err = capture_io { Rulepack::Reporter.print(Rulepack::Query.installed('opencode')) }
    assert_match(/Installed items on opencode/, out)
  end
end
