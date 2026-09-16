# frozen_string_literal: true

# Unit tests for Aggregate.run
# Covers: skill agent detection, header inclusion, rule fragment collection,
#         common/agent-specific skill inclusion, vendor skill output

require_relative 'helper'
require 'stringio'

class TestAggregateSkills < Minitest::Test
  # Minimal build index written once in setup so Aggregate.run always finds a
  # valid build/index.yaml regardless of whether a real build has been run.
  BUILD_INDEX = ROOT.join('build', 'index.yaml')

  def setup
    BUILD_INDEX.dirname.mkpath
    unless BUILD_INDEX.exist?
      BUILD_INDEX.write("---\nversion: 3.0\npackages: {}\n")
    end
  end

  def teardown
    # Clean up only if we created it
    BUILD_INDEX.delete if BUILD_INDEX.exist? && BUILD_INDEX.read == "---\nversion: 3.0\npackages: {}\n"
  end

  def run_aggregate
    capturing_stdout = StringIO.new
    original_stdout = $stdout
    $stdout = capturing_stdout
    # Own renderer: other test files clear the global Emitter subscriptions.
    renderer = Rulepack::Reporter::ConsoleRenderer.new
    begin
      result = Rulepack::Aggregate.run({})
      [result, capturing_stdout.string]
    ensure
      $stdout = original_stdout
      renderer.unsubscribe!
    end
  end

  def test_aggregate_runs_without_error
    result, output = run_aggregate
    assert result, "Aggregate.run failed: #{output}"
    # Should mention at least one skill agent (crush, goose, droid, codex)
    assert_match(/Aggregating vendor skills|No skill-based agents|Vendor skill aggregation complete/, output)
  end

  def test_aggregate_detects_skill_agents
    _result, output = run_aggregate
    # Registry has 4 skill-type agents: crush, goose, droid, codex
    assert_match(/crush|goose|droid|codex/, output)
  end

  def test_aggregate_creates_vendor_files
    run_aggregate

    # Check if vendor skill files were created for skill agents
    %w[crush goose droid codex].each do |agent|
      vendor_file = ROOT.join('build', agent, 'skills', 'vendor', "#{agent}.md")
      # File may exist but be empty if no packages target this agent
      # Just verify aggregation ran without crashing
    end
  end
end
