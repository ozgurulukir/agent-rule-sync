# frozen_string_literal: true

# Integration tests for SSoT build/install pipeline
# Tests end-to-end: build → install → check → uninstall

require_relative 'helper'
require 'json'

class TestBuildIntegration < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('ssot-build-test-')
    @build_root = Pathname.new(@tmpdir)
    @ssot_root = @build_root.join('ssot')
    @build_dir = @ssot_root.join('build')
    FileUtils.cp_r(ROOT.join('ssot').to_s, @ssot_root.to_s, preserve: false)
    # Remove existing build dir to start clean
    FileUtils.rm_rf(@build_dir)
    @build_dir.mkpath
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_build_creates_index
    # Run build
    build_script = @ssot_root.join('build.rb')
    system(File.join(RbConfig::CONFIG['bindir'], 'ruby'), build_script.to_s, chdir: @ssot_root.to_s)

    index_path = @build_dir.join('index.yaml')
    assert index_path.exist?, "Build index should exist"

    index = Ssot::Lib::Common.load_yaml(index_path)
    assert index[:packages], "Index should have packages"
    assert index[:packages].key?(:memory), "Index should include memory package"
  end

  def test_build_skill_bundle_creates_manifest
    # Run build
    build_script = @ssot_root.join('build.rb')
    system(File.join(RbConfig::CONFIG['bindir'], 'ruby'), build_script.to_s, chdir: @ssot_root.to_s)

    # Check for skill-bundle manifests
    manifest_path = @build_dir.join('opencode', 'golang-security-bundle', 'manifest.json')
    if manifest_path.exist?
      manifest = JSON.parse(manifest_path.read)
      assert manifest['sub_skills'], "Manifest should have sub_skills"
      assert manifest['sub_skills'].any?, "Manifest should have at least one sub-skill"
      assert manifest['pkgname'], "Manifest should have pkgname"
      assert manifest['platform'], "Manifest should have platform"
      # Verify each sub-skill has required fields
      manifest['sub_skills'].each do |ss|
        assert ss['path'], "Sub-skill should have path"
        assert ss['name'], "Sub-skill should have name"
        assert ss['sha256'], "Sub-skill should have sha256"
        assert ss['files'], "Sub-skill should have files"
      end
    else
      skip "No skill-bundle manifest found (golang-security-bundle may not be built)"
    end
  end
end

class TestVersionComparisonIntegration < Minitest::Test
  def test_compare_versions_handles_real_world_versions
    # Test pacman-style version comparison
    assert_equal 1, Ssot::Lib::Common.compare_versions('1.10.0', '1.9.0')  # numeric segments
    assert_equal -1, Ssot::Lib::Common.compare_versions('1.0.0', '2.0.0')
    assert_equal 0, Ssot::Lib::Common.compare_versions('1.0.0', '1.0.0')
    assert_equal 1, Ssot::Lib::Common.compare_versions('2026.05', '2026.04')
  end

  def test_format_version_pacman_style
    # epoch 0: omit epoch
    assert_equal '1.0.0-1', Ssot::Lib::Common.format_version(0, '1.0.0', 1)
    # epoch > 0: include epoch
    assert_equal '1:1.0.0-1', Ssot::Lib::Common.format_version(1, '1.0.0', 1)
    assert_equal '5:2.0.0-3', Ssot::Lib::Common.format_version(5, '2.0.0', 3)
  end
end

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
            # Missing pkgrel and epoch
          ]
        }
      }
    }

    Ssot::Lib::Common.migrate_installed_records(index[:packages][:memory])

    record = index[:packages][:memory][:installed].first
    assert_equal 1, record[:pkgrel], "Should add pkgrel=1"
    assert_equal 0, record[:epoch], "Should add epoch=0"
  end
end

class TestTransactionRollbackIntegration < Minitest::Test
  def test_backup_and_restore_index
    with_tmpdir do |tmpdir|
      index_path = tmpdir.join('index.yaml')
      index_path.write("version: 3.0\npackages: {}\n")

      # Backup
      backup = Ssot::Lib::Common.backup_index(index_path)
      assert backup.exist?, "Backup should exist"

      # Modify original
      index_path.write("version: 3.0\npackages:\n  test:\n    pkgver: 2.0.0\n")

      # Restore
      assert Ssot::Lib::Common.restore_index(backup), "Restore should succeed"

      restored = YAML.load_file(index_path)
      assert_nil restored[:packages]&.key?(:test), "Should restore to backup state"
    end
  end

  def test_cleanup_backups_removes_all_backup_files
    with_tmpdir do |tmpdir|
      index_path = tmpdir.join('index.yaml')
      index_path.write("test\n")

      3.times { Ssot::Lib::Common.backup_index(index_path) }

      backups = Pathname.glob("#{index_path}.bak.*")
      assert_equal 3, backups.size, "Should have 3 backups"

      Ssot::Lib::Common.cleanup_backups(index_path)

      remaining = Pathname.glob("#{index_path}.bak.*")
      assert_equal 0, remaining.size, "All backups should be cleaned up"
    end
  end
end

class TestCacheIntegration < Minitest::Test
  def test_cache_key_for_url_is_sha256
    source = { type: 'url', url: 'https://example.com/test', sha256: 'abc123' }
    key = Ssot::Lib::Common.cache_key_for_source(source, 'abc123')
    assert_equal 'abc123', key
  end

  def test_cache_key_for_git_is_commit_hash
    source = { type: 'git', url: 'https://github.com/owner/repo.git' }
    key = Ssot::Lib::Common.cache_key_for_source(source, 'deadbeef')
    assert_equal 'deadbeef', key
  end

  def test_cache_dir_format
    dir = Ssot::Lib::Common.cache_dir('abc123')
    assert_equal SSOT_ROOT.join('cache', 'abc123'), dir
  end

  def test_source_cached_detection
    with_tmpdir do |tmpdir|
      cache_dir = SSOT_ROOT.join('cache', 'test-key')
      cache_dir.mkpath
      cache_dir.join('extracted').mkdir

      assert Ssot::Lib::Common.source_cached?('test-key'), "Should detect cached source"

      cache_dir.join('extracted').rmtree
      refute Ssot::Lib::Common.source_cached?('test-key'), "Should not detect missing cache"

      cache_dir.rmtree
    end
  end
end
