# frozen_string_literal: true

# Contract tests for Rulepack::BuildRecord — the single owner of the
# build/index.yaml entry schema.

require_relative 'helper'
require 'rulepack/models/package'
require 'rulepack/models/target'
require 'rulepack/models/build_record'
require 'yaml'

class TestBuildRecord < Minitest::Test
  def build_package(targets: nil)
    Rulepack::Package.from_hash(
      pkgname: 'test-pkg',
      pkgver: '1.0.0',
      pkg_type: 'rule',
      pkgdesc: 'test package',
      source: [{ type: 'local', path: 'src/memory.md' }],
      targets: targets
    )
  end

  def test_from_package_seeds_schema_without_legacy_keys
    record = Rulepack::BuildRecord.from_package(build_package)

    h = record.to_h
    assert_equal '1.0.0', h[:pkgver]
    assert_equal 'rule', h[:pkg_type]
    refute h.key?(:status), 'build index must not carry the legacy :status key'
    refute h.key?(:installed), ':installed belongs to data/index.yaml, not the build index'
    assert_empty h[:available_targets]
    assert_equal({ source: nil, built: {} }, h[:checksums])
    assert h.key?(:targets)
  end

  def test_record_target_accumulates_immutably
    record = Rulepack::BuildRecord.from_package(build_package)
    record = record.with_target('opencode', 'aaa')
    record = record.with_target('codex', 'bbb')
    record = record.with_target('opencode', 'aaa') # idempotent

    h = record.to_h
    assert_equal %w[opencode codex], h[:available_targets].map(&:to_s)
    assert_equal 'aaa', h[:checksums][:built]['opencode']
    assert_equal 'bbb', h[:checksums][:built]['codex']
  end

  def test_to_h_serializes_targets_as_hashes_and_round_trips_yaml
    target = Rulepack::Target.from_hash(platform: 'opencode', format: 'directory', output: 'x.md')
    record = Rulepack::BuildRecord.from_package(build_package(targets: [target]))
    record = record.with_target('opencode', 'sha1')

    h = record.to_h
    assert_kind_of Hash, h[:targets].first
    assert_equal 'opencode', h[:targets].first[:platform]

    # YAML round-trip with the same safe_load settings the readers use
    loaded = YAML.safe_load(record.to_h.to_yaml, permitted_classes: [Symbol], symbolize_names: true)
    assert_equal 'x.md', loaded[:targets].first[:output]
  end

  def test_materializable_package_requires_source_sha256
    target = Rulepack::Target.from_hash(platform: 'opencode', format: 'skill-bundle', output: '.')
    record = Rulepack::BuildRecord.from_package(build_package(targets: [target]))

    assert record.materializable?
    assert_raises(Rulepack::StateError) { record.to_h }

    record = record.with_source(source_dir: 'src', source_sha256: 'abc')
    assert_equal 'abc', record.to_h[:source_sha256]
  end

  def test_file_based_package_needs_no_source_sha256
    target = Rulepack::Target.from_hash(platform: 'opencode', format: 'directory', output: 'x.md')
    record = Rulepack::BuildRecord.from_package(build_package(targets: [target]))

    refute record.materializable?
    assert_nil record.to_h[:source_sha256]
  end

  def test_target_materializable_predicates
    t = ->(format) { Rulepack::Target.from_hash(platform: 'p', format: format, output: '.') }
    assert t.call('skill-bundle').materializable?
    assert t.call('agent').materializable?
    refute t.call('directory').materializable?
    refute t.call('skill').materializable?
    assert t.call('directory').file_based?
    assert Rulepack::Target.materializable_format?('skill-bundle')
    refute Rulepack::Target.materializable_format?('skill')
  end

  def test_package_materializable_only_predicate
    pkg = build_package
    refute pkg.materializable_only?

    t = Rulepack::Target.from_hash(platform: 'p', format: 'skill-bundle', output: '.')
    pkg = build_package(targets: [t])
    assert pkg.materializable_only?
  end

  def test_from_package_seeds_skill_exclude
    pkg = Rulepack::Package.from_hash(
      pkgname: 'test-pkg',
      pkgver: '1.0.0',
      pkg_type: 'skill',
      pkgdesc: 'test package',
      source: [{ type: 'local', path: 'src/memory.md' }],
      skill_exclude: ['in-progress', 'deprecated']
    )
    record = Rulepack::BuildRecord.from_package(pkg)

    assert_equal ['in-progress', 'deprecated'], record.skill_exclude
  end

  def test_to_h_includes_skill_exclude_when_non_empty
    pkg = Rulepack::Package.from_hash(
      pkgname: 'test-pkg',
      pkgver: '1.0.0',
      pkg_type: 'skill',
      pkgdesc: 'test package',
      source: [{ type: 'local', path: 'src/memory.md' }],
      skill_exclude: ['in-progress']
    )
    record = Rulepack::BuildRecord.from_package(pkg)

    h = record.to_h
    assert h.key?(:skill_exclude), 'to_h should include skill_exclude when non-empty'
    assert_equal ['in-progress'], h[:skill_exclude]
  end

  def test_to_h_omits_skill_exclude_when_empty
    pkg = Rulepack::Package.from_hash(
      pkgname: 'test-pkg',
      pkgver: '1.0.0',
      pkg_type: 'skill',
      pkgdesc: 'test package',
      source: [{ type: 'local', path: 'src/memory.md' }],
      skill_exclude: []
    )
    record = Rulepack::BuildRecord.from_package(pkg)

    h = record.to_h
    refute h.key?(:skill_exclude), 'to_h should omit skill_exclude when empty'
  end
end
