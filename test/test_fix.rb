# frozen_string_literal: true

# Unit tests for fix.rb (self-healing module)
# Tests drift detection, orphan removal, and auto-repair functionality

require_relative 'helper'
require 'yaml'
require 'fileutils'

require 'rulepack/fix'


class TestFix < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-fix-test-')
    @root = Pathname.new(@tmpdir)
    @build_dir = @root.join('build')
    @install_dir = @root.join('install')
    @build_dir.mkpath
    @install_dir.mkpath


    # Override common paths
    Rulepack::Common.build_index_path = @build_dir.join('index.yaml')
    Rulepack::Common.index_yaml_path = @install_dir.join('index.yaml')
    Rulepack::Common.build_dir = @build_dir

    # Write a minimal build index
    build_index = {
      version: 3.0,
      packages: {
        'test-pkg': {
          pkgname: 'test-pkg',
          pkgver: '1.0.0',
          targets: [
            { platform: 'opencode', format: 'directory', output: 'test-rule.md', checksum: 'abc123' }
          ]
        }
      }
    }
    (@build_dir / 'index.yaml').write(build_index.to_yaml)

    # Write an installed index with one package
    installed_index = {
      version: 3.0,
      generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
      packages: {
        'test-pkg': {
          pkgname: 'test-pkg',
          pkgver: '1.0.0',
          targets: [
            { platform: 'opencode', format: 'directory', output: 'test-rule.md', checksum: 'abc123' }
          ],
          installed: [
            { platform: 'opencode', version: '1.0.0', output: 'test-rule.md', checksum: 'abc123', installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), pkgrel: 1, epoch: 0 }
          ]
        }
      }
    }
    (@install_dir / 'index.yaml').write(installed_index.to_yaml)
  end


  def teardown
    Rulepack::Common.build_index_path = nil
    Rulepack::Common.index_yaml_path = nil
    Rulepack::Common.build_dir = nil
    FileUtils.rm_rf(@tmpdir)
  end

  # ─── Error Handling ──────────────────────────────────────────────────────────

  def test_run_raises_error_when_build_index_missing
    (@build_dir / 'index.yaml').delete

    error = assert_raises(StandardError) do
      Rulepack::Fix.run(target: 'opencode', exit_on_failure: false)
    end

    assert_match(/Build index not found/i, error.message)
  end

  def test_run_raises_error_when_installed_index_missing
    (@install_dir / 'index.yaml').delete

    error = assert_raises(StandardError) do
      Rulepack::Fix.run(target: 'opencode', exit_on_failure: false)
    end

    assert_match(/Installed index not found/i, error.message)
  end

  def test_run_raises_error_for_unknown_package
    error = assert_raises(StandardError) do
      Rulepack::Fix.run(package_name: 'nonexistent', target: 'opencode', exit_on_failure: false)
    end

    assert_match(/not registered as installed/i, error.message)
  end

  def test_run_raises_error_when_target_not_specified
    error = assert_raises(StandardError) do
      Rulepack::Fix.run(exit_on_failure: false)
    end

    assert_match(/Please specify target platform/i, error.message)
  end

  # ─── Orphan Detection and Removal ────────────────────────────────────────────

  def test_fix_orphans_detects_orphan_files
    # Create an orphan file in install directory
    orphan_file = @install_dir.join('orphan.md')
    orphan_file.write('# Orphan content')

    # Mock verify to report orphan
    verify_output = "  ? ORPHAN: #{orphan_file}"
    Rulepack::Fix.stub(:run_verify, verify_output) do
      result = Rulepack::Fix.run(
        target: 'opencode',
        dry_run: true,
        exit_on_failure: false
      )
      
      refute result, 'dry-run should not apply fixes'
    end
  end

  def test_fix_orphans_with_auto_flag_removes_orphans
    orphan_file = @install_dir.join('orphan.md')
    orphan_file.write('# Orphan content')
    assert orphan_file.exist?, 'orphan file should exist before fix'

    verify_output = "  ? ORPHAN: #{orphan_file}"
    Rulepack::Fix.stub(:run_verify, verify_output) do
      Rulepack::Fix.stub(:fix_drift, false) do
        result = Rulepack::Fix.run(
          target: 'opencode',
          auto: true,
          exit_on_failure: false
        )
        
        assert result, 'auto mode should apply fixes'
        refute orphan_file.exist?, 'orphan file should be removed'
      end
    end
  end

  def test_fix_orphans_without_auto_skips_removal
    orphan_file = @install_dir.join('orphan.md')
    orphan_file.write('# Orphan content')
    assert orphan_file.exist?, 'orphan file should exist'

    verify_output = "  ? ORPHAN: #{orphan_file}"
    Rulepack::Fix.stub(:run_verify, verify_output) do
      Rulepack::Fix.stub(:fix_drift, false) do
        result = Rulepack::Fix.run(
          target: 'opencode',
          auto: false,
          exit_on_failure: false
        )
        
        refute result, 'non-auto mode should skip orphan removal'
        assert orphan_file.exist?, 'orphan file should not be removed without --auto'
      end
    end
  end

  # ─── Drift Detection and Repair ───────────────────────────────────────────────

  def test_fix_drift_with_dry_run_does_not_modify_index
    # Modify installed index to simulate drift
    index = Rulepack::Common.load_yaml(@install_dir / 'index.yaml')
    index[:packages][:'test-pkg'][:installed][0][:checksum] = 'wrongchecksum'
    (@install_dir / 'index.yaml').write(index.to_yaml)

    verify_output = "  ⚠ Checksum mismatch for test-rule.md"
    Rulepack::Fix.stub(:run_verify, verify_output) do
      result = Rulepack::Fix.run(
        target: 'opencode',
        dry_run: true,
        exit_on_failure: false
      )
      
      refute result, 'dry-run should not apply fixes'
      
      # Index should remain unchanged
      index_after = Rulepack::Common.load_yaml(@install_dir / 'index.yaml')
      assert_equal 'wrongchecksum', index_after[:packages][:'test-pkg'][:installed][0][:checksum]
    end
  end

  def test_find_broken_packages_detects_missing_files
    # Remove the installed file to simulate breakage
    # (In real scenario, file would be in ~/.config/opencode/rules/test-rule.md)
    # We'll mock this by modifying the index to reference a non-existent path
    
    index = Rulepack::Common.load_yaml(@install_dir / 'index.yaml')
    
    # Stub resolve_install_path to return non-existent path
    broken_path = Pathname.new('/nonexistent/test-rule.md')
    Rulepack::Fix.stub(:resolve_install_path, broken_path) do
      broken = Rulepack::Fix.find_broken_packages(
        'opencode',
        nil,
        nil,
        index
      )
      
      assert_equal ['test-pkg'], broken, 'should detect missing file as broken'
    end
  end

  def test_find_broken_packages_skips_when_no_installed_records
    index = Rulepack::Common.load_yaml(@install_dir / 'index.yaml')
    index[:packages][:'test-pkg'][:installed] = []
    (@install_dir / 'index.yaml').write(index.to_yaml)

    broken = Rulepack::Fix.find_broken_packages('opencode', nil, nil, index)
    
    assert_empty broken, 'should return empty when no installed records'
  end

  # ─── Partial Index Corruption ───────────────────────────────────────────────

  def test_handles_partial_index_corruption
    # Create index with multiple packages, one corrupted
    index = {
      version: 3.0,
      packages: {
        'good-pkg': {
          pkgname: 'good-pkg',
          pkgver: '1.0.0',
          targets: [{ platform: 'opencode', format: 'directory', output: 'good.md', checksum: 'valid123' }],
          installed: [{ platform: 'opencode', version: '1.0.0', output: 'good.md', checksum: 'valid123', installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), pkgrel: 1, epoch: 0 }]
        },
        'bad-pkg': {
          pkgname: 'bad-pkg',
          pkgver: '1.0.0',
          targets: [{ platform: 'opencode', format: 'directory', output: 'bad.md', checksum: 'wrong456' }],
          installed: [{ platform: 'opencode', version: '1.0.0', output: 'bad.md', checksum: 'wrong456', installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), pkgrel: 1, epoch: 0 }]
        }
      }
    }
    (@install_dir / 'index.yaml').write(index.to_yaml)

    # Both should be detected as broken (good-pkg has valid checksum but file doesn't exist, bad-pkg has wrong checksum)
    broken = Rulepack::Fix.find_broken_packages('opencode', nil, nil, index)
    
    # At least bad-pkg should be detected as broken (file doesn't exist or checksum mismatch)
    assert_includes broken, 'bad-pkg', 'should detect broken package'
  end

  # ─── Clear Installed Record ───────────────────────────────────────────────────

  def test_clear_installed_record_removes_platform_entry
    index = Rulepack::Common.load_yaml(@install_dir / 'index.yaml')
    assert index[:packages][:'test-pkg'][:installed].length == 1, 'should have one installed record'
    
    Rulepack::Fix.clear_installed_record(index, 'test-pkg', 'opencode')
    
    assert_empty index[:packages][:'test-pkg'][:installed], 'should clear installed records for platform'
  end

  def test_clear_installed_record_handles_missing_package
    index = Rulepack::Common.load_yaml(@install_dir / 'index.yaml')
    
    # Should not raise error
    Rulepack::Fix.clear_installed_record(index, 'nonexistent', 'opencode')
    
    # Original package should remain unchanged
    assert index[:packages][:'test-pkg'][:installed].length == 1
  end

  # ─── Platform with No Installed Packages ──────────────────────────────────────

  def test_fix_platform_with_no_installed_packages
    index = {
      version: 3.0,
      packages: {}
    }
    (@install_dir / 'index.yaml').write(index.to_yaml)

    verify_output = "  ✓ No drift detected."
    Rulepack::Fix.stub(:run_verify, verify_output) do
      result = Rulepack::Fix.run(
        target: 'opencode',
        exit_on_failure: false
      )
      
      refute result, 'should return false when nothing to fix'
    end
  end

  # ─── Build Artifacts Missing ─────────────────────────────────────────────────

  def test_fix_skips_when_build_artifacts_missing
    # Delete build index
    (@build_dir / 'index.yaml').delete

    error = assert_raises(StandardError) do
      Rulepack::Fix.run(target: 'opencode', exit_on_failure: false)
    end

    assert_match(/Build index not found/i, error.message)
  end
end
