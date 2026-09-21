# frozen_string_literal: true

# Unit tests for InstalledState.check — the single "is this installed record
# intact on disk?" dispatch consumed by Verify, Fix and the check command.
# Golden item shapes mirror the historical verify.rb output byte-for-byte.

require_relative 'helper'
require 'rulepack/installed_state'

class TestInstalledState < Minitest::Test
  def setup
    @tmpdir = Pathname.new(Dir.mktmpdir('rulepack-installed-state-'))
    @base_path = @tmpdir.join('platform')
    @build_dir = @tmpdir.join('build')
    @build_dir.mkpath
    @base_path.mkpath

    @platform_cfg = {
      type: 'directory',
      base_path: @base_path.to_s,
      rules_dir: 'rules',
      skills_dir: 'skills',
      agents_dir: 'agents'
    }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def with_build_dir(&block)
    paths = Rulepack::Paths.new(
      root: @tmpdir,
      build_dir: @build_dir,
      index_yaml_path: @tmpdir.join('index.yaml')
    )
    Rulepack::Common.with_paths(paths, &block)
  end

  def check(installed, target: nil, platform_cfg: @platform_cfg, base_path: @base_path)
    Rulepack::InstalledState.check(
      installed: installed, target: target, platform_cfg: platform_cfg,
      pkgname: 'test-pkg', base_path: base_path
    )
  end

  def rule_target(format: 'directory', output: 'rule.md')
    { platform: 'testplat', format: format, output: output }
  end

  def rule_record(checksum:)
    { platform: 'testplat', version: '1.0.0', pkgrel: 1, epoch: 0,
      output: 'rule.md', checksum: checksum, format: nil,
      target_path: nil, installed_at: '2026-09-16T10:00:00Z' }
  end

  # ─── Single file ────────────────────────────────────────────────────────────

  def test_single_file_ok
    file = @base_path.join('rules', 'rule.md')
    file.parent.mkpath
    file.write('content')

    verdict = check(rule_record(checksum: Digest::SHA256.hexdigest('content')),
                    target: rule_target)

    assert_predicate verdict, :ok?
    refute_predicate verdict, :broken?
    assert_equal :rule, verdict.type
    item = verdict.to_item_h(pkgname: 'test-pkg', output: 'rule.md')
    assert_equal :ok, item[:status]
    assert_equal "  ✓ test-pkg (rule.md)", item[:messages].first
    assert_equal [:pkgname, :type, :status, :messages, :output, :path], item.keys
  end

  def test_single_file_missing
    verdict = check(rule_record(checksum: 'x'), target: rule_target)

    assert_equal :missing, verdict.status
    assert_predicate verdict, :broken?
    assert_equal "  ⚠ MISSING: test-pkg (rule.md) at #{@base_path.join('rules', 'rule.md')}",
                 verdict.messages.first
  end

  def test_single_file_checksum_drift
    file = @base_path.join('rules', 'rule.md')
    file.parent.mkpath
    file.write('tampered')

    verdict = check(rule_record(checksum: 'wrong'), target: rule_target)

    assert_equal :drift, verdict.status
    assert_predicate verdict, :broken?
    assert_equal '  ⚠ CHECKSUM mismatch: test-pkg (rule.md)', verdict.messages.first
  end

  def test_target_path_preferred_over_resolved_path
    record = rule_record(checksum: Digest::SHA256.hexdigest('content'))
                 .merge(target_path: @base_path.join('elsewhere.md').to_s)
    file = @base_path.join('elsewhere.md')
    file.write('content')

    verdict = check(record, target: rule_target)

    assert_predicate verdict, :ok?
    assert_equal file, verdict.path
  end

  # ─── Skill on skill-type platform (build artifact) ──────────────────────────

  def test_skill_build_artifact_checksum_ok
    platform_cfg = { type: 'skill', base_path: @base_path.to_s, skills_dir: 'skills' }
    artifact = @build_dir.join('testplat', 'test-pkg', 'skill.md')
    artifact.parent.mkpath
    artifact.write('built')

    with_build_dir do
      verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                        output: 'skill.md', checksum: Digest::SHA256.hexdigest('built'),
                        format: 'skill' },
                      target: { platform: 'testplat', format: 'skill', output: 'skill.md' },
                      platform_cfg: platform_cfg)
      assert_predicate verdict, :ok?
      assert_equal :skill, verdict.type
      assert_match(/build artifact OK/, verdict.messages.first)
    end
  end

  def test_skill_build_artifact_missing
    platform_cfg = { type: 'skill', base_path: @base_path.to_s, skills_dir: 'skills' }

    with_build_dir do
      verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                        output: 'skill.md', checksum: 'abc', format: 'skill' },
                      target: { platform: 'testplat', format: 'skill', output: 'skill.md' },
                      platform_cfg: platform_cfg)
      assert_equal :missing, verdict.status
      assert_predicate verdict, :broken?
    end
  end

  # ─── Agent ──────────────────────────────────────────────────────────────────

  def test_agent_missing_is_broken
    verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                      output: 'test-pkg', checksum: nil, format: 'agent' },
                    target: { platform: 'testplat', format: 'agent', output: 'test-pkg' })
    assert_equal :missing, verdict.status
    assert_equal @base_path.join('agents', 'test-pkg'), verdict.path
  end

  def test_agent_present_ok
    agent_dir = @base_path.join('agents', 'test-pkg')
    agent_dir.mkpath

    verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                      output: 'test-pkg', checksum: nil, format: 'agent' },
                    target: { platform: 'testplat', format: 'agent', output: 'test-pkg' })
    assert_predicate verdict, :ok?
    item = verdict.to_item_h(pkgname: 'test-pkg')
    refute item.key?(:output), 'agent items never carry :output'
    assert_equal @base_path.join('agents', 'test-pkg'), item[:path]
  end

  def test_agent_without_agents_dir_is_skipped_not_broken
    platform_cfg = { type: 'directory', base_path: @base_path.to_s, rules_dir: 'rules' }

    verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                      output: 'test-pkg', checksum: nil, format: 'agent' },
                    target: { platform: 'testplat', format: 'agent', output: 'test-pkg' },
                    platform_cfg: platform_cfg)
    assert_equal :skipped, verdict.status
    refute_predicate verdict, :broken?, 'skipped is not breakage for Fix'
    item = verdict.to_item_h(pkgname: 'test-pkg')
    assert_equal :ok, item[:status], 'Verify reports skipped as ok with ⊘ message'
    refute item.key?(:path), 'skipped agent item has no :path key'
    assert_match(/⊘/, item[:messages].first)
  end

  def test_agent_target_dir_prefers_install_config
    agent_dir = @base_path.join('agents', 'custom-dir')
    agent_dir.mkpath

    verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                      output: 'wrong-fallback', checksum: nil, format: 'agent' },
                    target: { platform: 'testplat', format: 'agent', output: 'test-pkg',
                              install: { target_dir: 'custom-dir' } })
    assert_predicate verdict, :ok?
    assert_equal agent_dir, verdict.path
  end

  # ─── Skill-bundle (manifest replay) ─────────────────────────────────────────

  def make_bundle(sub_skills)
    bundle = Rulepack::Common.resolve_install_path(@platform_cfg,
                                                   { platform: 'testplat', format: 'skill-bundle', output: '.' },
                                                   @base_path)
    bundle.mkpath
    File.write(bundle.join('manifest.json'), JSON.generate(sub_skills: sub_skills))
    bundle
  end

  def test_skill_bundle_ok
    file = Rulepack::Common.resolve_install_path(@platform_cfg,
                                                 { platform: 'testplat', format: 'skill-bundle', output: '.' },
                                                 @base_path)
                                       .join('sub.md')
    file.parent.mkpath
    file.write('sub')
    make_bundle([{ 'name' => 'sub', 'files' => { 'sub.md' => Digest::SHA256.hexdigest('sub') } }])

    verdict = check({}, target: { platform: 'testplat', format: 'skill-bundle', output: '.' })
    assert_predicate verdict, :ok?
    assert_equal 1, verdict.files.size
    assert_equal :ok, verdict.files.first[:status]
    assert_match(/skill-bundle, 1 sub-skill\(s\), 1 file\(s\)/, verdict.messages.first)
  end

  def test_skill_bundle_file_drift
    file = Rulepack::Common.resolve_install_path(@platform_cfg,
                                                 { platform: 'testplat', format: 'skill-bundle', output: '.' },
                                                 @base_path)
                                       .join('sub.md')
    file.parent.mkpath
    file.write('tampered')
    make_bundle([{ 'name' => 'sub', 'files' => { 'sub.md' => Digest::SHA256.hexdigest('sub') } }])

    verdict = check({}, target: { platform: 'testplat', format: 'skill-bundle', output: '.' })
    assert_equal :drift, verdict.status
    assert_predicate verdict, :broken?
    assert_equal '  ⚠ CHECKSUM mismatch: test-pkg/sub.md', verdict.messages.first
  end

  def test_skill_bundle_missing_file_is_flagged_but_not_appended_to_verify_item
    make_bundle([{ 'name' => 'sub', 'files' => { 'gone.md' => 'sha' } }])

    verdict = check({}, target: { platform: 'testplat', format: 'skill-bundle', output: '.' })
    assert_equal :drift, verdict.status,
                 'historical semantics: any replay failure makes the item :drift'
    assert_predicate verdict, :broken?
    assert_equal :missing, verdict.files.first[:status],
                 'the verdict tracks the missing file for error rendering'
    item = verdict.to_item_h(pkgname: 'test-pkg')
    assert_empty item[:files],
                 'historical quirk: missing files are not in Verify item files array'
    assert_match(/MISSING: test-pkg\/gone\.md/, verdict.messages.first)
  end

  def test_skill_bundle_missing_manifest
    Rulepack::Common.resolve_install_path(@platform_cfg,
                                          { platform: 'testplat', format: 'skill-bundle', output: '.' },
                                          @base_path).mkpath

    verdict = check({}, target: { platform: 'testplat', format: 'skill-bundle', output: '.' })
    assert_equal :missing, verdict.status
    assert_match(/MISSING manifest/, verdict.messages.first)
  end

  # ─── Materializable on platform without skills_dir ──────────────────────────

  def test_materializable_without_skills_dir_ok_on_import_platform
    platform_cfg = { type: 'import', base_path: @base_path.to_s, rules_dir: 'rules' }

    verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                      output: '.', checksum: nil, format: 'skill-bundle' },
                    target: { platform: 'testplat', format: 'skill-bundle', output: '.' },
                    platform_cfg: platform_cfg)
    assert_predicate verdict, :ok?
    refute_predicate verdict, :broken?
  end

  def test_materializable_without_skills_dir_checks_build_tree_on_directory_platform
    platform_cfg = { type: 'directory', base_path: @base_path.to_s, rules_dir: 'rules' }

    with_build_dir do
      verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                        output: '.', checksum: nil, format: 'skill-bundle' },
                      target: { platform: 'testplat', format: 'skill-bundle', output: '.' },
                      platform_cfg: platform_cfg)
      assert_equal :missing, verdict.status, 'no build tree yet → missing'
      assert_match(/MISSING build tree/, verdict.messages.first)
    end
  end

  # ─── Format derivation and nil target ───────────────────────────────────────

  def test_record_format_wins_over_target_format
    file = @base_path.join('rules', 'rule.md')
    file.parent.mkpath
    file.write('content')

    verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                      output: 'rule.md', checksum: Digest::SHA256.hexdigest('content'),
                      format: 'directory' },
                    target: { platform: 'testplat', format: 'skill-bundle', output: 'rule.md' })
    assert_equal :rule, verdict.type, 'record format is the canonical authority'
  end

  def test_nil_target_is_skipped_not_broken
    verdict = check(rule_record(checksum: 'whatever'), target: nil)
    assert_equal :skipped, verdict.status,
                 'legacy nil-target record has no reliable path; skipped, not broken'
    refute_predicate verdict, :broken?
  end

  # ─── Verdict contract ───────────────────────────────────────────────────────

  def test_to_error_s_nil_when_ok
    file = @base_path.join('rules', 'rule.md')
    file.parent.mkpath
    file.write('content')

    verdict = check(rule_record(checksum: Digest::SHA256.hexdigest('content')),
                    target: rule_target)
    assert_nil verdict.to_error_s('test-pkg')
  end

  def test_to_error_s_strings_for_check_command
    missing = check(rule_record(checksum: 'x'), target: rule_target)
    assert_equal "Missing: test-pkg (rule.md) at #{@base_path.join('rules', 'rule.md')}",
                 missing.to_error_s('test-pkg', output: 'rule.md')
  end

  def test_to_error_s_agent_string
    verdict = check({ platform: 'testplat', version: '1.0', pkgrel: 1, epoch: 0,
                      output: 'test-pkg', checksum: nil, format: 'agent' },
                    target: { platform: 'testplat', format: 'agent', output: 'test-pkg' })
    assert_equal "Missing agent: test-pkg at #{@base_path.join('agents', 'test-pkg')}",
                 verdict.to_error_s('test-pkg')
  end

  def test_to_error_s_skill_bundle_with_only_missing_files_lists_them
    make_bundle([{ 'name' => 'sub', 'files' => { 'gone.md' => 'sha' } }])

    verdict = check({}, target: { platform: 'testplat', format: 'skill-bundle', output: '.' })
    assert_equal 'test-pkg: missing: gone.md', verdict.to_error_s('test-pkg')
  end

  def test_skill_bundle_nested_file_paths
    # Set up a bundle with nested file paths (e.g. engineering/ask-matt/SKILL.md
    # and engineering/ask-matt/agents/openai.yaml).
    bundle = Rulepack::Common.resolve_install_path(@platform_cfg,
                                                   { platform: 'testplat', format: 'skill-bundle', output: '.' },
                                                   @base_path)
    bundle.mkpath

    # Create nested sub-skill directory with files at multiple depths
    sub_dir = bundle.join('engineering', 'ask-matt')
    sub_dir.mkpath
    agents_dir = sub_dir.join('agents')
    agents_dir.mkpath
    (sub_dir / 'SKILL.md').write('# Ask Matt Skill')
    (agents_dir / 'openai.yaml').write('openai: config')

    # Create manifest with nested file paths relative to bundle root.
    # check_skill_bundle uses bundle_path.join(rel_path) for each file key.
    make_bundle([{ 'path' => 'engineering/ask-matt',
                   'files' => {
                     'engineering/ask-matt/SKILL.md' => Digest::SHA256.hexdigest('# Ask Matt Skill'),
                     'engineering/ask-matt/agents/openai.yaml' => Digest::SHA256.hexdigest('openai: config')
                   } } ])

    verdict = check({}, target: { platform: 'testplat', format: 'skill-bundle', output: '.' })
  assert_predicate verdict, :ok?
  assert_equal 2, verdict.files.size
  assert_match /engineering\/ask-matt\/SKILL\.md/, verdict.files.first[:path]
  assert_match /engineering\/ask-matt\/agents\/openai\.yaml/, verdict.files.map { |f| f[:path] }.join('; ')
  assert_match /skill-bundle, 1 sub-skill\(s\), 2 file\(s\)/, verdict.messages.first
  end
end
