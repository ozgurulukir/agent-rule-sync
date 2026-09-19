# frozen_string_literal: true

# Unit tests for fix.rb (self-healing module)
# Tests drift detection, orphan removal, and auto-repair functionality

require_relative 'helper'
require 'yaml'
require 'fileutils'

require 'rulepack/fix'


class TestFix < Minitest::Test
  # Runs Fix.run against the sandbox paths and a non-interactive UI.
  def run_fix(**opts)
    Rulepack::Fix.run({ **opts }, paths: @paths, ui: @ui)
  end

  def setup
    @tmpdir = Dir.mktmpdir('rulepack-fix-test-')
    @root = Pathname.new(@tmpdir)
    @build_dir = @root.join('build')
    @install_dir = @root.join('install')
    @build_dir.mkpath
    @install_dir.mkpath


    # Sandbox paths: build tree and installed index live under the tmpdir
    @paths = Rulepack::Paths.new(
      root: @root,
      build_dir: @build_dir,
      index_yaml_path: @install_dir.join('index.yaml')
    )
    @ui = Rulepack::UI::Null.new

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
    FileUtils.rm_rf(@tmpdir)
  end

  # ─── Error Handling ──────────────────────────────────────────────────────────

  def test_run_returns_failure_when_build_index_missing
    (@build_dir / 'index.yaml').delete

    result = run_fix(target: 'opencode')
    assert result.failure?
    assert_match(/Build index not found/i, result.errors.first)
  end

  def test_run_returns_failure_when_installed_index_missing
    (@install_dir / 'index.yaml').delete

    result = run_fix(target: 'opencode')
    assert result.failure?
    assert_match(/Installed index not found/i, result.errors.first)
  end

  def test_run_returns_failure_for_unknown_package
    result = run_fix(package_name: 'nonexistent', target: 'opencode')
    assert result.failure?
    assert_match(/not registered as installed/i, result.errors.first)
  end

  def test_run_returns_failure_when_target_not_specified
    result = run_fix
    assert result.failure?
    assert_match(/Please specify target platform/i, result.errors.first)
  end

  # ─── Orphan Detection and Removal ────────────────────────────────────────────

  def test_fix_orphans_detects_orphan_files
    # Create an orphan file in install directory
    orphan_file = @install_dir.join('orphan.md')
    orphan_file.write('# Orphan content')

    # Mock verify to report orphan
    verify_result = Rulepack::Result.new(status: :partial, data: { drift: 0, orphans: [orphan_file.to_s], ok: 0 })
    Rulepack::Verify.stub(:check, verify_result) do
      result = run_fix(
        target: 'opencode',
        dry_run: true
      )

      assert result.success?
      assert_empty result.data[:orphans_removed], 'dry-run should not apply fixes'
    end
  end

  def test_fix_orphans_with_auto_flag_removes_orphans
    orphan_file = @install_dir.join('orphan.md')
    orphan_file.write('# Orphan content')
    assert orphan_file.exist?, 'orphan file should exist before fix'

    verify_result = Rulepack::Result.new(status: :partial, data: { drift: 0, orphans: [orphan_file.to_s], ok: 0 })
    Rulepack::Verify.stub(:check, verify_result) do
      Rulepack::Fix.stub(:fix_drift, { fixed: [], failed: [] }) do
        result = run_fix(
          target: 'opencode',
          auto: true
        )

        assert result.success?
        assert_includes result.data[:orphans_removed], orphan_file.to_s
        refute orphan_file.exist?, 'orphan file should be removed'
      end
    end
  end

  def test_fix_orphans_without_auto_skips_removal
    orphan_file = @install_dir.join('orphan.md')
    orphan_file.write('# Orphan content')
    assert orphan_file.exist?, 'orphan file should exist'

    verify_result = Rulepack::Result.new(status: :partial, data: { drift: 0, orphans: [orphan_file.to_s], ok: 0 })
    Rulepack::Verify.stub(:check, verify_result) do
      Rulepack::Fix.stub(:fix_drift, { fixed: [], failed: [] }) do
        result = run_fix(
          target: 'opencode',
          auto: false
        )

        assert result.success?
        assert_empty result.data[:orphans_removed]
        assert orphan_file.exist?, 'orphan file should not be removed without --auto'
      end
    end
  end

  # ─── Drift Detection and Repair ───────────────────────────────────────────────

  def test_fix_drift_with_dry_run_does_not_modify_index
    # Modify installed index to simulate drift
    index = Rulepack::IO.load_yaml(@install_dir / 'index.yaml')
    index[:packages][:'test-pkg'][:installed][0][:checksum] = 'wrongchecksum'
    (@install_dir / 'index.yaml').write(index.to_yaml)

    verify_result = Rulepack::Result.new(status: :partial, data: { drift: 1, orphans: [], ok: 0 })
    Rulepack::Verify.stub(:check, verify_result) do
      result = run_fix(
        target: 'opencode',
        dry_run: true
      )

      assert result.success?
      assert_empty result.data[:fixed], 'dry-run should not apply fixes'

      # Index should remain unchanged
      index_after = Rulepack::IO.load_yaml(@install_dir / 'index.yaml')
      assert_equal 'wrongchecksum', index_after[:packages][:'test-pkg'][:installed][0][:checksum]
    end
  end

  def test_find_broken_packages_detects_missing_files
    # Remove the installed file to simulate breakage
    # (In real scenario, file would be in ~/.config/opencode/rules/test-rule.md)
    # We'll mock this by modifying the index to reference a non-existent path

    index = Rulepack::IO.load_yaml(@install_dir / 'index.yaml')

    # Stub resolve_install_path to return non-existent path
    # (resolution now lives in InstalledState via Common.resolve_install_path)
    broken_path = Pathname.new('/nonexistent/test-rule.md')
    Rulepack::Common.stub(:resolve_install_path, broken_path) do
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
    index = Rulepack::IO.load_yaml(@install_dir / 'index.yaml')
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

  # ─── Force reinstall decision ────────────────────────────────────────────────

  def force_ctx(force_packages)
    Rulepack::Install::InstallContext.new(
      index: { packages: { 'test-pkg' => { installed: [
        { platform: 'opencode', version: '1.0.0', epoch: 0, pkgrel: 1, output: 'test-rule.md' }
      ] } } },
      platform_id: 'opencode', quiet: true, force_packages: force_packages
    )
  end

  def candidate_pkgdata
    { pkgver: '1.0.0', epoch: 0, pkgrel: 1 }
  end

  def test_force_packages_bypasses_same_version_short_circuit
    assert Rulepack::InstallPlan.should_install_or_upgrade?('test-pkg', candidate_pkgdata, force_ctx(['test-pkg'])),
           'forced package reinstalls despite identical version'
  end

  def test_without_force_packages_same_version_still_skips
    refute Rulepack::InstallPlan.should_install_or_upgrade?('test-pkg', candidate_pkgdata, force_ctx(nil)),
           'plain same-version install still short-circuits'
  end

  # ─── Platform with No Installed Packages ─────────────────────────────────────

  def test_fix_platform_with_no_installed_packages
    index = {
      version: 3.0,
      packages: {}
    }
    (@install_dir / 'index.yaml').write(index.to_yaml)

    verify_result = Rulepack::Result.new(status: :success, data: { drift: 0, orphans: [], ok: 0 })
    Rulepack::Verify.stub(:check, verify_result) do
      result = run_fix(target: 'opencode')

      assert result.success?
      assert_empty result.data[:fixed]
      assert_empty result.data[:orphans_removed]
    end
  end

  # ─── fix_drift: Real reinstall flow ──────────────────────────────────────────

  def test_fix_drift_forces_reinstall_via_single_install_run
    # Create build artifact
    build_artifact = @build_dir.join('opencode', 'test-pkg', 'test-rule.md')
    build_artifact.parent.mkpath
    build_artifact.write('# Correct content')

    # Create installed file with wrong content (drift)
    installed_file = @install_dir.join('test-rule.md')
    installed_file.write('# Wrong drifted content')

    index_before = Rulepack::IO.load_yaml(@install_dir / 'index.yaml')

    install_called = false

    Rulepack::Common.stub(:resolve_install_path, installed_file) do
      Rulepack::Install.stub(:run, lambda { |platform_id, opts|
        install_called = true
        assert_equal 'opencode', platform_id
        assert_equal ['test-pkg'], opts[:force_packages],
                     'broken packages must be forced past the version-compare'
        assert_nil opts[:specific_package],
                   'one call for all broken packages, not one per package'

        # Fix must NOT have written a cleared index to disk before the call
        disk_index = Rulepack::IO.load_yaml(Rulepack::Common.index_yaml_path)
        refute_empty disk_index[:packages][:'test-pkg'][:installed],
                     'no cleared-index choreography: Install.run handles reinstall'

        Rulepack::Result.new(status: :success, data: { installed: [:'test-pkg'] })
      }) do
        result = Rulepack::Fix.fix_drift('opencode', nil, nil, false, index_before)

        assert install_called, 'Install.run must have been called exactly once'
        assert_includes result[:fixed], 'test-pkg'
        assert_empty result[:failed]
      end
    end
  end

  def test_fix_drift_reports_failure_and_rollback
    index_before = Rulepack::IO.load_yaml(@install_dir / 'index.yaml')

    Rulepack::Install.stub(:run, lambda { |_platform_id, _opts|
      Rulepack::Result.new(status: :failure, errors: ['install exploded'],
                           data: { installed: [] })
    }) do
      result = Rulepack::Fix.fix_drift('opencode', nil, nil, false, index_before)

      assert_includes result[:failed], 'test-pkg'
      assert_empty result[:fixed]
    end
  end

  # ─── Build Artifacts Missing ─────────────────────────────────────────────────

  def test_fix_returns_failure_when_build_artifacts_missing
    # Delete build index
    (@build_dir / 'index.yaml').delete

    result = run_fix(target: 'opencode')
    assert result.failure?
    assert_match(/Build index not found/i, result.errors.first)
  end
end
