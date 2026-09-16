# frozen_string_literal: true

# Unit tests for InstalledRecord — the installed-record schema owner
# (models/installed_record.rb). Disk format of data/index.yaml is unchanged;
# the model owns construction at the read/write boundary.

require_relative 'helper'
require 'rulepack/models/installed_record'

class TestInstalledRecord < Minitest::Test
  def setup
    @full = {
      platform: 'opencode',
      version: '1.2.0',
      pkgrel: 1,
      epoch: 0,
      output: '00-memory.md',
      checksum: 'deadbeef',
      format: 'directory',
      target_path: '/home/user/.config/opencode/rules/00-memory.md',
      installed_at: '2026-09-16T10:00:00Z'
    }
  end

  def test_round_trip_full_record
    record = Rulepack::InstalledRecord.from_h(@full)
    assert_equal @full, record.to_h
  end

  def test_from_h_tolerates_legacy_record_without_format_and_target_path
    legacy = {
      platform: 'opencode',
      version: '1.0.0',
      pkgrel: 1,
      epoch: 0,
      output: 'rule.md',
      checksum: 'abc',
      installed_at: '2026-01-01T00:00:00Z'
    }
    record = Rulepack::InstalledRecord.from_h(legacy)
    assert_nil record.format
    assert_nil record.target_path
    assert_equal legacy.merge(format: nil, target_path: nil), record.to_h,
                 'to_h normalizes to the full 9-key shape'
  end

  def test_from_h_ignores_unknown_keys
    record = Rulepack::InstalledRecord.from_h(@full.merge(future_key: 42))
    assert_equal @full, record.to_h
  end

  def test_to_h_preserves_dot_output_and_nil_checksum
    record = Rulepack::InstalledRecord.from_h(
      platform: 'oh-my-pi', version: '1.0', pkgrel: 1, epoch: 0,
      output: '.', checksum: nil, format: 'agent', target_path: nil,
      installed_at: '2026-09-16T10:00:00Z'
    )
    h = record.to_h
    assert_equal '.', h[:output]
    assert_nil h[:checksum]
    assert h.key?(:target_path), 'all nine keys always present'
  end

  def test_record_is_immutable
    record = Rulepack::InstalledRecord.from_h(@full)
    assert record.frozen?
    assert_raises(NoMethodError) { record.version = '9.9.9' }
  end

  # ─── canonical_format: inst[:format] → target format → 'directory' ─────────

  def test_canonical_format_prefers_record_format
    record = Rulepack::InstalledRecord.from_h(@full)
    assert_equal 'directory', record.canonical_format('skill-bundle')
  end

  def test_canonical_format_falls_back_to_target_format
    record = Rulepack::InstalledRecord.from_h(@full.merge(format: nil))
    assert_equal 'skill-bundle', record.canonical_format('skill-bundle')
  end

  def test_canonical_format_defaults_to_directory
    record = Rulepack::InstalledRecord.from_h(@full.merge(format: nil))
    assert_equal 'directory', record.canonical_format(nil)
  end
end
