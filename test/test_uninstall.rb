





# frozen_string_literal: true

# Unit tests for uninstall_packages (index mutation)
# Tests in-place index modification without filesystem side effects

require_relative 'helper'
require 'yaml'

class TestUninstallPackages < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('ssot-uninstall-test-')
    @build_root = Pathname.new(@tmpdir)
    @ssot_root = @build_root.join('ssot')
    @build_dir = @ssot_root.join('build')
    @ssot_root.mkpath
    @build_dir.mkpath

    # Write a minimal build index for uninstall to reference
    build_index = {
      version: 3.0,
      packages: {
        memory: {
          pkgname: 'memory',
          pkgver: '1.0.0',
          targets: [
            { platform: 'opencode', format: 'directory', output: '00-memory.md', transformer: 'copy', install: { type: 'symlink' } }
          ]
        }
      }
    }
    (@build_dir / 'index.yaml').write(build_index.to_yaml)

    @index = {
      version: 3.0,
      generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
      packages: {
        memory: {
          pkgver: '1.0.0',
          pkgdesc: 'Memory rule',
          order: 0,
          installed: [
            { platform: 'opencode', version: '1.0.0', output: '00-memory.md', checksum: 'abc123', installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), pkgrel: 1, epoch: 0 }
          ]
        }
      }
    }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def with_build_index_override
    # Temporarily scope the build index to our test build dir
    Rulepack::Common.with_paths(build_index_path: @build_dir.join('index.yaml')) do
      yield
    end
  end

  # ─── Index Mutation ──────────────────────────────────────────────────────────

  def test_uninstall_removes_installed_record_from_index
    with_build_index_override do
      uninstalled = Rulepack::InstallHelpers.uninstall_packages(@index, 'opencode', dry_run: false)
      assert_includes uninstalled, :memory, 'memory should be in uninstalled list'
      records = @index[:packages][:memory][:installed]
      assert_empty records, 'installed records should be removed after uninstall'
    end
  end

  def test_uninstall_modifies_index_in_place
    with_build_index_override do
      before_count = @index[:packages][:memory][:installed].size
      Rulepack::InstallHelpers.uninstall_packages(@index, 'opencode', dry_run: false)
      after_count = @index[:packages][:memory][:installed].size
      assert_equal before_count - 1, after_count, 'should have one fewer installed record'
    end
  end

  def test_uninstall_dry_run_does_not_modify_index
    with_build_index_override do
      before = @index[:packages][:memory][:installed].dup
      Rulepack::InstallHelpers.uninstall_packages(@index, 'opencode', dry_run: true)
      assert_equal before, @index[:packages][:memory][:installed], 'dry-run should not modify index'
    end
  end

  def test_uninstall_returns_package_names
    with_build_index_override do
      result = Rulepack::InstallHelpers.uninstall_packages(@index, 'opencode', dry_run: false)
      assert_kind_of Array, result
      assert_includes result, :memory
    end
  end

  def test_uninstall_skips_not_installed_packages
    # No packages installed on a different platform
    with_build_index_override do
      result = Rulepack::InstallHelpers.uninstall_packages(@index, 'crush', dry_run: false)
      assert_empty result, 'should return empty list when nothing is installed on platform'
    end
  end

  def test_uninstall_collects_packages_missing_from_build_index
    # A package in the installed index but absent from the build index cannot
    # be uninstalled — it must surface in the failures collector instead of
    # evaporating as a dropped nil (P-AR a).
    @index[:packages][:ghost] = {
      pkgver: '1.0.0',
      pkgdesc: 'Ghost package',
      order: 1,
      installed: [
        { platform: 'opencode', version: '1.0.0', output: 'ghost.md', checksum: 'deadbeef', installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), pkgrel: 1, epoch: 0 }
      ]
    }
    with_build_index_override do
      failed = []
      uninstalled = Rulepack::InstallHelpers.uninstall_packages(@index, 'opencode', dry_run: false, failures: failed)
      entry = failed.find { |f| f[:package] == :ghost }
      refute_nil entry, 'ghost package should be reported as failed'
      assert_equal :missing_from_build_index, entry[:reason]
      refute_includes uninstalled, :ghost, 'ghost package must not count as uninstalled'
      assert_includes uninstalled, :memory, 'healthy package still uninstalls'
    end
  end

  def test_uninstall_collects_outputs_missing_from_build_index
    # Installed output has no matching build-index target (stale index after
    # an output rename): the record is kept, the package is NOT reported as
    # uninstalled, and the skip surfaces as a structured failure.
    stale_build_index = {
      version: 3.0,
      packages: {
        memory: {
          pkgname: 'memory',
          pkgver: '1.0.0',
          targets: [
            { platform: 'opencode', format: 'directory', output: 'renamed-memory.md', transformer: 'copy', install: { type: 'symlink' } }
          ]
        }
      }
    }
    with_build_index_override do
      Rulepack::Common.with_paths(build_index_path: @build_dir.join('stale.yaml')) do
        @build_dir.join('stale.yaml').write(stale_build_index.to_yaml)
        failed = []
        uninstalled = Rulepack::InstallHelpers.uninstall_packages(@index, 'opencode', dry_run: false, failures: failed)
        entry = failed.find { |f| f[:package] == :memory }
        refute_nil entry, 'skipped record should be reported as failed'
        assert_equal :records_skipped, entry[:reason]
        assert_equal ['00-memory.md'], entry[:outputs]
        assert_equal false, entry[:removed_any]
        assert_empty uninstalled, 'nothing was actually removed'
        # The installed record survives — nothing was removed.
        assert_equal 1, @index[:packages][:memory][:installed].size
      end
    end
  end

  def test_uninstall_does_not_write_index_to_disk
    # Verify uninstall only modifies in-memory index
    with_build_index_override do
      index_file = @ssot_root.join('index.yaml')
      # Write index to disk before uninstall
      index_file.write(@index.to_yaml)
      original_content = index_file.read

      Rulepack::InstallHelpers.uninstall_packages(@index, 'opencode', dry_run: false)
      # On-disk index should be unchanged (uninstall_packages doesn't write)
      assert_equal original_content, index_file.read, 'uninstall should not write index to disk'
    end
  end

  # ─── Return Value ────────────────────────────────────────────────────────────

  def test_uninstall_dedupes_package_names
    # If a package has multiple records for same platform, name appears once in result
    @index[:packages][:memory][:installed] += [
      { platform: 'opencode', version: '1.0.0', output: 'memory-rule.md', checksum: 'def456', installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), pkgrel: 1, epoch: 0 }
    ]
    with_build_index_override do
      result = Rulepack::InstallHelpers.uninstall_packages(@index, 'opencode', dry_run: false)
      assert_equal 1, result.count(:memory), 'memory should appear only once in result'
    end
  end
end
