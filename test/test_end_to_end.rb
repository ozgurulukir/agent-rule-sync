# frozen_string_literal: true

# End-to-end integration tests for the full Rulepack pipeline:
#   build → install → check → uninstall → verify

require_relative 'helper'
require 'json'
require 'fileutils'
require 'set'


# Gate full E2E tests. Now 100% offline and fast via local mock git repositories.
NETWORK_E2E = true


class TestEndToEndPipeline < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-e2e-')
    @home_dir = Pathname.new(@tmpdir).join('home')
    @home_dir.mkpath
    @rulepack_root = Pathname.new(@tmpdir).join('rulepack')
    @rulepack_root.mkpath
    FileUtils.cp_r(ROOT.join('lib').to_s, @rulepack_root.join('lib').to_s, preserve: false)
    FileUtils.cp_r(ROOT.join('data').to_s, @rulepack_root.join('data').to_s, preserve: false)
    # data/index.yaml is a generated file (gitignored); never copy it into the sandbox
    # — stale installed-package records would silently poison the install flow.
    index_yaml = @rulepack_root.join('data', 'index.yaml')
    FileUtils.rm_f(index_yaml) if index_yaml.exist?

    # Setup 5 local mock git repositories and rewrite target PKGBUILDs to point to them
    mock_git_packages(@rulepack_root.join('data', 'packages'), Pathname.new(@tmpdir).join('mock-repos'))

    FileUtils.mkpath(@rulepack_root.join('build'))
    @build_dir = @rulepack_root.join('build')
    @ruby = File.join(RbConfig::CONFIG['bindir'], 'ruby')
    @env = { 'HOME' => @home_dir.to_s, 'RULEPACK_GIT_DEPTH' => '1' }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # ─── Build helpers ──────────────────────────────────────────────────────────────

  def run_build(expected_success: true)
    result = system(@ruby, @rulepack_root.join('lib/rulepack/build.rb').to_s, chdir: @rulepack_root.to_s)
    assert_equal expected_success, result, "Build #{expected_success ? 'should' : 'should not'} succeed"
    result
  end

  def run_install(platform, *args)
    cmd_args = ["--target", platform] + args
    result = system(@env, @ruby, @rulepack_root.join('lib/rulepack/install.rb').to_s, *cmd_args,
                    chdir: @rulepack_root.to_s)
    result
  end

  def run_check(platform)
    system(@env, @ruby, @rulepack_root.join('lib/rulepack/install.rb').to_s, '--check', '--target', platform,
           chdir: @rulepack_root.to_s)
    $?.exitstatus
  end

  def run_uninstall(platform, *args)
    cmd_args = ["--target", platform] + args
    result = system(@env, @ruby, @rulepack_root.join('lib/rulepack/uninstall.rb').to_s, *cmd_args,
                    chdir: @rulepack_root.to_s)
    result
  end

  def load_index
    idx_path = @rulepack_root.join('data', 'index.yaml')
    return nil unless idx_path.exist?
    Rulepack::Common.load_yaml(idx_path)
  end

  def load_build_index
    idx_path = @build_dir.join('index.yaml')
    return nil unless idx_path.exist?
    Rulepack::Common.load_yaml(idx_path)
  end

  # ─── Test: Clean Build ──────────────────────────────────────────────────────────

  def test_build_creates_all_artifacts
    skip "Full E2E requires RULEPACK_RUN_NETWORK_E2E=1 (takes ~3 minutes)" unless NETWORK_E2E
    run_build

    # Build index exists with all packages
    build_index = load_build_index
    refute_nil build_index, 'Build index should exist'
    assert build_index[:version], 'Should have version'
    assert build_index[:generated], 'Should have timestamp'
    assert build_index[:packages], 'Should have packages key'

    pkg_names = build_index[:packages].keys.map(&:to_s)
    %w[memory shell ast-grep workstation-rules
       line-repetition-control antigravity-skills vibe-security
       cc-skills-golang].each do |expected|
      assert_includes pkg_names, expected, "Build index should include #{expected}"
    end

    # Each package has required metadata
    build_index[:packages].each do |name, data|
      refute_nil data[:pkgver], "#{name}: missing pkgver"
      refute_nil data[:pkgdesc], "#{name}: missing pkgdesc"
      refute_nil data[:available_targets], "#{name}: missing available_targets"
      assert_kind_of Array, data[:available_targets], "#{name}: available_targets must be Array"
    end

    # Platform directories created
    platform_dirs = Dir.glob("#{@build_dir}/*").select { |d| File.directory?(d) }
    platform_names = platform_dirs.map { |d| File.basename(d) }
    %w[opencode cursor windsurf claude-code gemini-cli qwen-code
       crush goose droid codex agents].each do |platform|
      assert_includes platform_names, platform, "Build dir should include #{platform}"
    end
  end

  def test_build_rebuild_is_idempotent
    skip "Full E2E requires RULEPACK_RUN_NETWORK_E2E=1 (takes ~3 minutes)" unless NETWORK_E2E
    run_build
    first_packages = load_build_index[:packages].keys.sort

    run_build
    second_packages = load_build_index[:packages].keys.sort

    assert_equal first_packages, second_packages, 'Rebuild should produce same packages'
  end

  def test_build_creates_local_packages_fast
    skip "Use RULEPACK_RUN_NETWORK_E2E=1 for full E2E" if NETWORK_E2E

    run_build

    # Build index exists with local packages only (no git clones)
    build_index = load_build_index
    refute_nil build_index, 'Build index should exist'

    # Local packages (no git repos)
    local_packages = %w[memory shell ast-grep workstation-rules line-repetition-control]
    pkg_names = build_index[:packages].keys.map(&:to_s)

    # Verify all expected local packages are present
    local_packages.each do |expected|
      assert_includes pkg_names, expected, "Build index should include local #{expected}"
    end

    # Verify metadata
    build_index[:packages].each do |name, data|
      refute_nil data[:pkgver], "#{name}: missing pkgver"
      refute_nil data[:pkgdesc], "#{name}: missing pkgdesc"
      refute_nil data[:available_targets], "#{name}: missing available_targets"
    end
  end



  # ─── Test: Install directory platform (opencode) ────────────────────────────────

  def test_install_directory_then_uninstall
    run_build

    # Dry-run first — should not create files
    result = run_install('opencode', '--dry-run')
    assert result, 'Dry-run install should succeed'
    refute Pathname.new(@home_dir).join('.config/opencode/rules/00-memory.md').exist?,
           'Dry-run should not create files'

    # Actuall install
    result = run_install('opencode')
    assert result, 'Install should succeed'

    # Check symlink created
    opencode_rules = @home_dir.join('.config/opencode/rules')
    expected_symlinks = %w[00-memory.md 01-shell.md ast-grep.md workstation-rules.md]
    expected_symlinks.each do |file|
      path = opencode_rules.join(file)
      assert path.symlink?, "Should create symlink: #{file}"
      assert path.readlink.relative?, "Symlink should be relative: #{file}"
      assert path.read.size > 0, "Symlink target should be readable: #{file}"
    end

    # Check index updated with installed records
    index = load_index
    refute_nil index, 'Index should exist'
    installed_count = 0
    index[:packages].each do |_name, pkgdata|
      installed_count += (pkgdata[:installed] || []).count { |r| r[:platform] == 'opencode' }
    end
    assert installed_count > 0, "Should have installed records for opencode, got #{installed_count}"

    # Check passes
    exit_code = run_check('opencode')
    assert_equal 0, exit_code, 'Check should pass (exit 0)'

    # Uninstall
    result = run_uninstall('opencode')
    assert result, 'Uninstall should succeed'

    # Symlinks removed
    expected_symlinks.each do |file|
      path = opencode_rules.join(file)
      refute path.exist?, "Symlink should be removed: #{file}"
    end

    # Index cleaned
    index = load_index
    remaining = 0
    index[:packages].each do |_name, pkgdata|
      remaining += (pkgdata[:installed] || []).count { |r| r[:platform] == 'opencode' }
    end
    assert_equal 0, remaining, 'Index should have no opencode records after uninstall'
  end

  def test_install_directory_dry_run_does_not_modify_index
    run_build
    original_index = load_index

    run_install('opencode', '--dry-run')

    after_index = load_index
    assert_equal original_index, after_index, 'Dry-run should not modify index'
  end

  # ─── Test: Install import platform (gemini-cli) ─────────────────────────────────

  def test_install_import_then_uninstall
    run_build

    result = run_install('gemini-cli', '--on-collision', 'overwrite')
    assert result, 'Install gemini-cli should succeed'

    # Config file created with rule content (PKGBUILD uses install.type: copy)
    config_path = @home_dir.join('.config/gemini/cli_config.yaml')
    assert config_path.exist?, 'Config file should exist'
    content = config_path.read
    assert content.length > 0, 'Config file should have content'
    # Content is the rule content (copied via install.type: copy)
    assert content.include?('Non-Interactive Shell'), 'Config should contain rule content'

    # Check index
    index = load_index
    gemini_installed_count = 0
    index[:packages].each do |_name, pkgdata|
      gemini_installed_count += (pkgdata[:installed] || []).count { |r| r[:platform] == 'gemini-cli' }
    end
    assert gemini_installed_count > 0, "Should have installed records for gemini-cli, got #{gemini_installed_count}"

    # Uninstall (dry-run first)
    result = run_uninstall('gemini-cli', '--dry-run')
    assert result, 'Dry-run uninstall should succeed'

    result = run_uninstall('gemini-cli')
    assert result, 'Uninstall should succeed'

    # Index cleaned
    index = load_index
    remaining = 0
    index[:packages].each do |_name, pkgdata|
      remaining += (pkgdata[:installed] || []).count { |r| r[:platform] == 'gemini-cli' }
    end
    assert_equal 0, remaining, 'Index should have no gemini-cli records after uninstall'
  end

  # ─── Test: Install skill platform (goose — user-scoped) ──────────────────────

  def test_install_skill_platform_then_uninstall
    run_build

    result = run_install('goose')
    assert result, 'Install goose should succeed'

    # Check vendor skill created (goose uses ~/.local/share/goose/goose.md)
    vendor_path = @home_dir.join('.local/share/goose/goose.md')
    assert vendor_path.exist?, 'Vendor skill should exist'
    content = vendor_path.read
    assert content.length > 0, 'Vendor skill should have content'

    # Check index
    index = load_index
    goose_installed_count = 0
    index[:packages].each do |_name, pkgdata|
      goose_installed_count += (pkgdata[:installed] || []).count { |r| r[:platform] == 'goose' }
    end
    assert goose_installed_count > 0, "Should have installed records for goose, got #{goose_installed_count}"

    # Uninstall
    result = run_uninstall('goose')
    assert result, 'Uninstall goose should succeed'

    # Index cleaned
    index = load_index
    remaining = 0
    index[:packages].each do |_name, pkgdata|
      remaining += (pkgdata[:installed] || []).count { |r| r[:platform] == 'goose' }
    end
    assert_equal 0, remaining, 'Index should have no goose records after uninstall'
  end

  # ─── Test: Skill-bundle install (line-repetition-control) ──────────────────────

  def test_skill_bundle_install_then_uninstall
    run_build

    # Install without --select (installs all sub-skills)
    result = run_install('opencode')
    assert result, 'Install should succeed'

    # Check skill-bundle directory created
    bundle_dir = @home_dir.join('.config/opencode/skills/line-repetition-control')
    assert bundle_dir.directory?, 'Skill-bundle directory should exist'
    assert bundle_dir.join('SKILL.md').exist?, 'SKILL.md should be installed'
    assert bundle_dir.join('manifest.json').exist?, 'manifest.json should exist'

    # Verify manifest structure
    manifest = JSON.parse(bundle_dir.join('manifest.json').read)
    assert manifest['pkgname'] == 'line-repetition-control'
    assert manifest['platform'] == 'opencode'
    assert manifest['sub_skills'].size >= 1, 'Should have at least 1 sub-skill'

    # Sub-skills
    sub_skill_names = manifest['sub_skills'].map { |s| s['name'] }
    assert_includes sub_skill_names, '.', 'Should include root sub-skill'
    assert_includes sub_skill_names, 'scripts', 'Should include scripts sub-skill'

    # Check symlinks for directory packages (memory, shell) still created
    opencode_rules = @home_dir.join('.config/opencode/rules')
    assert opencode_rules.join('00-memory.md').symlink?,
           'Directory packages should still be installed alongside skill-bundle'

    # Check passes
    exit_code = run_check('opencode')
    assert_equal 0, exit_code, 'Check should pass with skill-bundle installed'

    # Uninstall
    result = run_uninstall('opencode')
    assert result, 'Uninstall should succeed'

    # Bundle directory removed
    refute bundle_dir.exist?, 'Skill-bundle directory should be removed'
    refute opencode_rules.join('00-memory.md').exist?,
           'Symlinks should be removed on uninstall'
  end

  # ─── Test: Full cycle with check after each step ────────────────────────────────

  def test_full_cycle_install_check_uninstall_check
    run_build

    # Install
    result = run_install('opencode')
    assert result, 'Install should succeed'

    # Check passes
    exit_code = run_check('opencode')
    assert_equal 0, exit_code, 'Check should pass after install'

    # Uninstall
    result = run_uninstall('opencode')
    assert result, 'Uninstall should succeed'

    # Check passes (nothing installed = no errors)
    exit_code = run_check('opencode')
    assert_equal 0, exit_code, 'Check should pass (exit 0) after uninstall (nothing to verify)'
  end

  # ─── Test: Idempotent install ───────────────────────────────────────────────────

  def test_install_is_idempotent
    run_build

    result1 = run_install('opencode')
    assert result1, 'First install should succeed'

    result2 = run_install('opencode')
    assert result2, 'Second (idempotent) install should succeed'

    # Check still passes
    exit_code = run_check('opencode')
    assert_equal 0, exit_code, 'Check should pass after idempotent install'
  end

  # ─── Test: Uninstall is idempotent ──────────────────────────────────────────────

  def test_uninstall_is_idempotent
    run_build
    run_install('opencode')

    result1 = run_uninstall('opencode')
    assert result1, 'First uninstall should succeed'

    result2 = run_uninstall('opencode')
    assert result2, 'Second (idempotent) uninstall should succeed'
  end

  # ─── Test: Error handling ──────────────────────────────────────────────────────

  def test_install_fails_without_build
    # Don't run build — try to install directly on fresh copy
    result = run_install('opencode')
    refute result, 'Install should fail without build index'
  end

  def test_install_fails_with_unknown_platform
    run_build
    result = run_install('nonexistent-platform')
    refute result, 'Install should fail for unknown platform'
  end

  def test_uninstall_fails_with_unknown_platform
    run_build
    result = run_uninstall('nonexistent-platform')
    refute result, 'Uninstall should fail for unknown platform'
  end

  # ─── Test: Multiple platforms ───────────────────────────────────────────────────

  def test_install_multiple_platforms_independently
    run_build

    # Install to opencode
    result = run_install('opencode')
    assert result, 'Install opencode should succeed'
    opencode_rules = @home_dir.join('.config/opencode/rules')
    assert opencode_rules.join('00-memory.md').symlink?, 'OpenCode symlink should exist'

    # Install to gemini-cli
    result = run_install('gemini-cli', '--on-collision', 'overwrite')
    assert result, 'Install gemini-cli should succeed'
    config_path = @home_dir.join('.config/gemini/cli_config.yaml')
    assert config_path.exist?, 'Gemini config should exist'

    # Index has records for both
    index = load_index
    opencode_platforms = Set.new
    index[:packages].each do |_name, pkgdata|
      (pkgdata[:installed] || []).each { |r| opencode_platforms << r[:platform] }
    end
    assert_includes opencode_platforms, 'opencode'
    assert_includes opencode_platforms, 'gemini-cli'

    # Uninstall only opencode
    result = run_uninstall('opencode')
    assert result, 'Uninstall opencode should succeed'
    refute opencode_rules.join('00-memory.md').exist?, 'OpenCode symlink should be removed'

    # Gemini should still be intact
    index2 = load_index
    remaining_gemini = 0
    index2[:packages].each do |_name, pkgdata|
      remaining_gemini += (pkgdata[:installed] || []).count { |r| r[:platform] == 'gemini-cli' }
    end
    assert remaining_gemini > 0, 'Gemini records should remain after opencode uninstall'
  end
end
