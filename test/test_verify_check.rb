# frozen_string_literal: true

require_relative 'helper'
require_relative '../lib/rulepack/verify'

class TestVerifyCheck < Minitest::Test
  def test_check_returns_result
    result = Rulepack::Verify.check(target: 'opencode')
    assert result.success? || result.partial?
    assert result.data.key?(:ok)
    assert result.data.key?(:drift)
    assert result.data.key?(:orphans)
    assert result.data.key?(:platforms)
  end

  def test_check_with_no_index
    # Temporarily override index path to a non-existent location
    original = Rulepack::Common.index_yaml_path
    Rulepack::Common.index_yaml_path = Pathname.new('/tmp/rulepack-no-index-xyz/index.yaml')
    result = Rulepack::Verify.check(target: 'opencode')
    assert result.failure?
    assert_match(/Installed index not found/, result.errors.first)
  ensure
    Rulepack::Common.index_yaml_path = original
  end
end
