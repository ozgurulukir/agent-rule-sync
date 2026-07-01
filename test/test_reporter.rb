# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'helper'
require_relative '../lib/rulepack/result'
require_relative '../lib/rulepack/reporter'

class TestReporter < Minitest::Test
  def test_text_rendering
    result = Rulepack::Result.new(status: :success, data: { platforms: { opencode: { type: 'directory' } } }, messages: ['header'])
    out = StringIO.new
    Rulepack::Reporter.print(result, format: :text, out: out)
    assert_match(/header/, out.string)
    assert_match(/Platforms/, out.string)
    assert_match(/opencode/, out.string)
  end

  def test_json_rendering
    result = Rulepack::Result.new(status: :success, data: { platforms: { opencode: { type: 'directory' } } })
    out = StringIO.new
    Rulepack::Reporter.print(result, format: :json, out: out)
    data = JSON.parse(out.string)
    assert_equal 'success', data['status']
    assert data['data']['platforms'].key?('opencode')
  end

  def test_yaml_rendering
    result = Rulepack::Result.new(status: :success, data: { count: 1 })
    out = StringIO.new
    Rulepack::Reporter.print(result, format: :yaml, out: out)
    data = YAML.safe_load(out.string)
    assert_equal 1, data['count']
  end

  def test_unsupported_format_raises
    result = Rulepack::Result.new(status: :success, data: {})
    assert_raises(ArgumentError) { Rulepack::Reporter.print(result, format: :xml) }
  end
end
