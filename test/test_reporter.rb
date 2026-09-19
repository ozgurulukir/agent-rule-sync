# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'helper'
require_relative '../lib/rulepack/result'
require_relative '../lib/rulepack/reporter'

class TestReporter < Minitest::Test
  def test_text_rendering
    result = Rulepack::Result.new(status: :success, view: :platform_registry,
                                  data: { platforms: { opencode: { type: 'directory' } } }, messages: ['header'])
    out = StringIO.new
    Rulepack::Reporter.print(result, format: :text, out: out)
    assert_match(/header/, out.string)
    assert_match(/Platforms/, out.string)
    assert_match(/opencode/, out.string)
  end

  def test_text_without_view_renders_messages_only
    # view: nil is a declaration — data is json/yaml-only; nothing is
    # inferred from data shape (the old sniffing ladder misrendered shapes).
    result = Rulepack::Result.new(status: :success, data: { platforms: [:opencode] }, messages: ['narration'])
    out = StringIO.new
    Rulepack::Reporter.print(result, format: :text, out: out)
    assert_equal "narration\n", out.string
  end

  def test_view_routes_to_the_declared_renderer
    out = StringIO.new
    result = Rulepack::Result.new(status: :success, view: :fix,
                                  data: { platforms: ['opencode'], fixed: ['pkg'], failed: [], orphans_removed: [] })
    Rulepack::Reporter::TextRenderer.print(result, out: out)
    assert_match(/Fixed: pkg/, out.string)
    refute_match(/Platforms \(0\)/, out.string)
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
    # yaml now carries the same envelope as json (status/data/errors/messages)
    assert_equal 'success', data['status']
    assert_equal 1, data['data']['count']
  end

  def test_unsupported_format_raises
    result = Rulepack::Result.new(status: :success, data: {})
    assert_raises(Rulepack::InvalidOptionValue) { Rulepack::Reporter.print(result, format: :xml) }
  end

  def test_jsonl_is_not_a_reporter_format
    result = Rulepack::Result.new(status: :success, data: {})
    e = assert_raises(Rulepack::InvalidOptionValue) { Rulepack::Reporter.print(result, format: :jsonl) }
    assert_match(/jsonl/, e.message)
  end
end
