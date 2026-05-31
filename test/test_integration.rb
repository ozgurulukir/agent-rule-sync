# frozen_string_literal: true

# Integration tests for Rulepack build/install pipeline
# Tests end-to-end: build → install → check → uninstall
# Plus unit-level tests for extracted helper functions (manifest generation)

require_relative 'helper'
require 'json'

# ─── Build Integration ────────────────────────────────────────────────────────

class TestBuildIntegration < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-build-test-')
    @build_root = Pathname.new(@tmpdir)
    FileUtils.cp_r(ROOT.join('lib').to_s, @build_root.join('lib').to_s, preserve: false)
    FileUtils.cp_r(ROOT.join('data').to_s, @build_root.join('data').to_s, preserve: false)

    # Setup 5 local mock git repositories and rewrite target PKGBUILDs to point to them
    mock_git_packages(@build_root.join('data', 'packages'), Pathname.new(@tmpdir).join('mock-repos'))

    @build_dir = @build_root.join('build')
    @build_dir.mkpath
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_build_creates_index
    build_script = @build_root.join('lib/rulepack/build.rb')
    result = system(File.join(RbConfig::CONFIG['bindir'], 'ruby'), build_script.to_s, chdir: @build_root.to_s)
    assert result, 'Build script should exit successfully'

    index_path = @build_dir.join('index.yaml')
    assert index_path.exist?, 'Build index should exist after build'

    index = Rulepack::Common.load_yaml(index_path)
    assert index[:packages], 'Index should have packages key'
    assert index[:packages].key?(:memory), 'Index should include memory package'
    assert index[:packages].key?(:shell), 'Index should include shell package'

    # Verify each package entry has required fields
    index[:packages].each do |pkgname, pkg_data|
      assert pkg_data[:pkgver], "Package #{pkgname} should have pkgver"
      assert pkg_data[:pkgdesc], "Package #{pkgname} should have pkgdesc"
      assert pkg_data[:available_targets], "Package #{pkgname} should have available_targets"
      assert_kind_of Array, pkg_data[:available_targets], "available_targets should be an Array"
    end

    # Verify index metadata
    assert index[:version], 'Index should have a version'
    assert index[:generated], 'Index should have a generated timestamp'
  end

  def test_build_creates_platform_directories
    build_script = @build_root.join('lib/rulepack/build.rb')
    result = system(File.join(RbConfig::CONFIG['bindir'], 'ruby'), build_script.to_s, chdir: @build_root.to_s)
    assert result, 'Build script should exit successfully'

    assert(Dir.glob("#{@build_dir}/*").any?, 'At least one platform build directory should exist after build')
  end
end

# ─── Skill-bundle Manifest Generation ─────────────────────────────────────────

class TestSkillBundleManifestGeneration < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('ssot-manifest-test-')
    @base = Pathname.new(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_generate_manifest_with_subskills
    pkg_dir = @base.join('my-bundle')
    pkg_dir.mkpath
    (pkg_dir / 'auth').mkpath
    (pkg_dir / 'auth' / 'SKILL.md').write('# Auth Skill')
    (pkg_dir / 'auth' / 'rules.md').write('auth rules')
    (pkg_dir / 'sql').mkpath
    (pkg_dir / 'sql' / 'SKILL.md').write('# SQL Skill')

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'my-bundle', 'opencode')

    assert manifest[:pkgname] == 'my-bundle', 'pkgname should match'
    assert manifest[:platform] == 'opencode', 'platform should match'
    assert manifest[:generated_at], 'should have generated_at timestamp'
    assert manifest[:sub_skills].size >= 2, "should have at least 2 sub-skills, got #{manifest[:sub_skills].size}"

    auth_sub = manifest[:sub_skills].find { |s| s[:path] == 'auth' }
    assert auth_sub, 'should have auth sub-skill'
    assert auth_sub[:sha256], 'auth should have sha256'
    assert auth_sub[:files], 'auth should have files map'
    assert_equal 2, auth_sub[:files].size, 'auth should have 2 files'

    sql_sub = manifest[:sub_skills].find { |s| s[:path] == 'sql' }
    assert sql_sub, 'should have sql sub-skill'
    assert_equal 1, sql_sub[:files].size, 'sql should have 1 file'
  end

  def test_generate_manifest_with_root_files
    pkg_dir = @base.join('root-files-bundle')
    pkg_dir.mkpath
    (pkg_dir / 'README.md').write('# Readme')
    (pkg_dir / 'SKILL.md').write('# Skill')

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'root-bundle', 'opencode')

    root_sub = manifest[:sub_skills].find { |s| s[:path] == '.' }
    assert root_sub, 'should have root-level sub-skill entry (path: ".")'
    assert_equal '.', root_sub[:name]
    assert root_sub[:sha256], 'root sub-skill should have sha256'
    assert_equal 2, root_sub[:files].size, 'root should have 2 files'
  end

  def test_generate_manifest_with_empty_bundle
    pkg_dir = @base.join('empty-bundle')
    pkg_dir.mkpath
    (pkg_dir / '.gitkeep').delete if (pkg_dir / '.gitkeep').exist?

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'empty-bundle', 'opencode')

    assert manifest[:sub_skills].empty?, "empty bundle should have no sub-skills, got: #{manifest[:sub_skills].inspect}"
    assert manifest[:pkgname] == 'empty-bundle'
  end

  def test_generate_manifest_writes_json_file
    pkg_dir = @base.join('write-test')
    pkg_dir.mkpath
    (pkg_dir / 'SKILL.md').write('# Skill')

    Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'write-test', 'cursor')

    manifest_file = pkg_dir.join('manifest.json')
    assert manifest_file.exist?, 'manifest.json should be written'

    parsed = JSON.parse(manifest_file.read)
    assert parsed['pkgname'] == 'write-test'
    assert parsed['platform'] == 'cursor'
    assert parsed['sub_skills'].is_a?(Array)
  end

  def test_manifest_subskill_files_have_correct_checksums
    pkg_dir = @base.join('checksum-test')
    pkg_dir.mkpath
    (pkg_dir / 'auth').mkpath
    (pkg_dir / 'auth' / 'SKILL.md').write('hello world')

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'checksum-test', 'opencode')
    auth_sub = manifest[:sub_skills].find { |s| s[:path] == 'auth' }

    expected_sha = Digest::SHA256.hexdigest('hello world')
    assert_equal expected_sha, auth_sub[:files]['auth/SKILL.md']
  end

  def test_generate_manifest_with_mixed_root_and_subskill_files
    pkg_dir = @base.join('mixed-bundle')
    pkg_dir.mkpath
    (pkg_dir / 'README.md').write('# Readme')
    (pkg_dir / 'auth').mkpath
    (pkg_dir / 'auth' / 'SKILL.md').write('# Auth Skill')

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'mixed-bundle', 'cursor')

    root_sub = manifest[:sub_skills].find { |s| s[:path] == '.' }
    assert root_sub, 'should have root sub-skill for README.md'
    assert_includes root_sub[:files], 'README.md'

    auth_sub = manifest[:sub_skills].find { |s| s[:path] == 'auth' }
    assert auth_sub, 'should have auth sub-skill'
    assert_includes auth_sub[:files], 'auth/SKILL.md'
  end

  def test_manifest_json_roundtrip
    pkg_dir = @base.join('json-roundtrip')
    pkg_dir.mkpath
    (pkg_dir / 'SKILL.md').write('# Skill')

    Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'json-roundtrip', 'opencode')
    raw = (pkg_dir / 'manifest.json').read
    parsed = JSON.parse(raw)

    assert parsed['pkgname'] == 'json-roundtrip'
    assert parsed['platform'] == 'opencode'
    assert_kind_of Array, parsed['sub_skills']
    assert parsed['generated_at'], 'should have generated_at timestamp'
  end
end

# ─── Schema Migration ─────────────────────────────────────────────────────────

class TestIndexSchemaIntegration < Minitest::Test
  def test_migrate_installed_records_adds_missing_fields
    index = {
      version: 3.0,
      packages: {
        memory: {
          pkgver: '1.0.0',
          pkgrel: 1,
          epoch: 0,
          installed: [
            { platform: 'opencode', version: '1.0.0', output: 'memory.md', checksum: 'abc123' }
          ]
        }
      }
    }

    Rulepack::Common.migrate_installed_records(index[:packages][:memory])

    record = index[:packages][:memory][:installed].first
    assert_equal 1, record[:pkgrel], 'Should add pkgrel=1'
    assert_equal 0, record[:epoch], 'Should add epoch=0'
  end

  def test_migrate_installed_records_idempotent
    index = {
      packages: {
        memory: {
          pkgver: '1.0.0',
          pkgrel: 1,
          epoch: 0,
          installed: [
            { platform: 'opencode', version: '1.0.0', output: 'memory.md', checksum: 'abc123', pkgrel: 2, epoch: 1 }
          ]
        }
      }
    }

    Rulepack::Common.migrate_installed_records(index[:packages][:memory])
    Rulepack::Common.migrate_installed_records(index[:packages][:memory])

    record = index[:packages][:memory][:installed].first
    assert_equal 2, record[:pkgrel], 'existing pkgrel should be preserved'
    assert_equal 1, record[:epoch], 'existing epoch should be preserved'
  end

  def test_migrate_handles_empty_installed_list
    index = { packages: { memory: { installed: [] } } }
    Rulepack::Common.migrate_installed_records(index[:packages][:memory])
    assert index[:packages][:memory][:installed].empty?, 'empty list should remain empty'
  end

  def test_migrate_handles_nil_installed
    index = { packages: { memory: { installed: nil } } }
    Rulepack::Common.migrate_installed_records(index[:packages][:memory])
    assert_nil index[:packages][:memory][:installed]
  end
end

# ─── Version Comparison ───────────────────────────────────────────────────────

class TestVersionComparisonIntegration < Minitest::Test
  def test_pacman_style_numeric_comparison
    assert_equal 1, Rulepack::Common.compare_versions('1.10.0', '1.9.0')
    assert_equal -1, Rulepack::Common.compare_versions('1.0.0', '2.0.0')
    assert_equal 0, Rulepack::Common.compare_versions('1.0.0', '1.0.0')
    assert_equal 1, Rulepack::Common.compare_versions('2026.05', '2026.04')
  end

  def test_format_version_pacman_style
    assert_equal '1.0.0-1', Rulepack::Common.format_version(0, '1.0.0', 1)
    assert_equal '1:1.0.0-1', Rulepack::Common.format_version(1, '1.0.0', 1)
    assert_equal '5:2.0.0-3', Rulepack::Common.format_version(5, '2.0.0', 3)
  end
end

# ─── Transaction Rollback ─────────────────────────────────────────────────────

class TestTransactionRollbackIntegration < Minitest::Test
  def test_backup_and_restore_index
    with_tmpdir do |tmpdir|
      index_path = tmpdir.join('index.yaml')
      index_path.write("version: 3.0\npackages: {}\n")

      backup = Rulepack::Common.backup_index(index_path)
      assert backup.exist?, 'Backup should exist'

      index_path.write("version: 3.0\npackages:\n  test:\n    pkgver: 2.0.0\n")

      assert Rulepack::Common.restore_index(backup, index_path), 'Restore should return true'

      restored = YAML.safe_load(File.read(index_path), permitted_classes: [Symbol], symbolize_names: true)
      assert_nil restored[:packages][:test], 'Should restore to backup state'
    end
  end

  def test_backup_contains_same_content_as_original
    with_tmpdir do |tmpdir|
      index_path = tmpdir.join('index.yaml')
      original_content = "version: 3.0\npackages:\n  foo:\n    pkgver: 1.0.0\n"
      index_path.write(original_content)

      backup = Rulepack::Common.backup_index(index_path)
      assert_equal original_content, backup.read, 'Backup content should match original'
    end
  end

  def test_cleanup_backups_removes_all_backup_files
    with_tmpdir do |tmpdir|
      index_path = tmpdir.join('index.yaml')
      index_path.write("test\n")

      backups = 3.times.map { Rulepack::Common.backup_index(index_path) }
      backups.each { |b| assert b.exist?, 'Backup should exist in tmpdir' }

      Rulepack::Common.cleanup_backups

      backups.each { |b| refute b.exist?, 'Backup tmpdir should be cleaned up' }
    end
  end

  def test_cleanup_backups_safe_when_no_backups_exist
    assert Rulepack::Common.cleanup_backups, 'cleanup should succeed with no backups'
  end

  def test_restore_nonexistent_backup_returns_false
    with_tmpdir do |tmpdir|
      fake_backup = tmpdir.join('nonexistent.bak')
      result = Rulepack::Common.restore_index(fake_backup, tmpdir.join('index.yaml'))
      refute result, 'Restore should return false for nonexistent backup'
    end
  end
end

# ─── Cache Integration ────────────────────────────────────────────────────────

class TestCacheIntegration < Minitest::Test
  def setup
    @cache_test_key = 'test-cache-key'
    @cache_dir = ROOT.join('cache', @cache_test_key)
  end

  def teardown
    FileUtils.rm_rf(@cache_dir)
  end

  def test_cache_key_for_url_is_sha256
    source = { type: 'url', url: 'https://example.com/test', sha256: 'abc123' }
    key = Rulepack::Common.cache_key_for_source(source, 'abc123')
    assert_equal 'abc123', key
  end

  def test_cache_key_for_url_uses_sha256_when_provided
    source = { type: 'url', url: 'https://example.com/test', sha256: 'deadbeef' * 8 }
    key = Rulepack::Common.cache_key_for_source(source)
    assert_equal 'deadbeef' * 8, key
  end

  def test_cache_key_for_url_raises_without_sha256
    source = { type: 'url', url: 'https://example.com/test' }
    assert_raises(RuntimeError) { Rulepack::Common.cache_key_for_source(source) }
  end

  def test_cache_key_for_git_is_commit_hash
    source = { type: 'git', url: 'https://github.com/owner/repo.git' }
    key = Rulepack::Common.cache_key_for_source(source, 'deadbeef' * 8)
    assert_equal 'deadbeef' * 8, key
  end

  def test_cache_key_for_git_raises_without_commit_hash
    source = { type: 'git', url: 'https://github.com/owner/repo.git' }
    assert_raises(RuntimeError) { Rulepack::Common.cache_key_for_source(source) }
  end

  def test_cache_dir_format
    dir = Rulepack::Common.cache_dir('abc123')
    assert_equal ROOT.join('cache', 'abc123'), dir
  end

  def test_source_cached_detection_hit
    @cache_dir.mkpath
    @cache_dir.join('extracted').mkdir

    assert Rulepack::Common.source_cached?(@cache_test_key), 'Should detect cached source'
  end

  def test_source_cached_detection_miss_no_extracted_dir
    @cache_dir.mkpath
    refute Rulepack::Common.source_cached?(@cache_test_key), 'Should not detect cache without extracted/ dir'
  end

  def test_source_cached_detection_miss_no_cache_dir
    refute Rulepack::Common.source_cached?(@cache_test_key), 'Should not detect cache without cache dir'
  end
end
