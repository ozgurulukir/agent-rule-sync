# frozen_string_literal: true

require_relative 'helper'
require_relative '../lib/rulepack/result'

class TestResult < Minitest::Test
  def test_success_result
    result = Rulepack::Result.new(status: :success, data: { foo: 1 })
    assert result.success?
    refute result.failure?
    refute result.partial?
    assert_equal({ foo: 1 }, result.data)
  end

  def test_failure_result
    result = Rulepack::Result.new(status: :failure, errors: ['boom'])
    refute result.success?
    assert result.failure?
    refute result.partial?
    assert_equal ['boom'], result.errors
  end

  def test_partial_result
    result = Rulepack::Result.new(status: :partial, data: { ok: 1, drift: 1 })
    refute result.success?
    refute result.failure?
    assert result.partial?
  end

  def test_invalid_status_raises
    assert_raises(ArgumentError) { Rulepack::Result.new(status: :weird) }
  end

  def test_to_h
    result = Rulepack::Result.new(status: :success, data: { x: 1 }, errors: ['e'], messages: ['m'])
    assert_equal({ status: :success, data: { x: 1 }, errors: ['e'], messages: ['m'] }, result.to_h)
  end
end
