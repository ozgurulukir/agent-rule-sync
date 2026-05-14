# frozen_string_literal: true

# Unit tests for uninstall_packages (index mutation)
# Tests in-place index modification without filesystem side effects

require_relative 'helper'
require 'yaml'

# uninstall_packages calls top-level log/log_warn/log_error — provide no-ops for tests
def log(_msg); end
def log_warn(_msg); end
def log_error(_msg); end

class TestUninstallPackages < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('ssot-uninstall-test-')
    @build_root = Pathname.new(@tmpdir)
    @ssot_root = @build_root.join('ssot')
    @build_dir = @ssot_root.join('build')
    FileUtils.cp_r(ROOT.join('ssot').to_s, @ssot_root.to_s, preserve: false)
    FileUtils.rm_rf(@build_dir)
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
    # Temporarily override BUILD_INDEX_PATH to point to our test build dir
    mod = Ssot::Lib::Common
    old_path = mod::BUILD_INDEX_PATH
    mod.const_set(:BUILD_INDEX_PATH, @build_dir.join('index.yaml'))
    yield
  ensure
    mod.const_set(:BUILD_INDEX_PATH, old_path) if mod.const_defined?(:BUILD_INDEX_PATH)
  end

  # ─── Index Mutation ──────────────────────────────────────────────────────────

  def test_uninstall_removes_installed_record_from_index
    with_build_index_override do
      uninstalled = Ssot::Lib::Common.uninstall_packages(@index, 'opencode', dry_run: false)
      assert_includes uninstalled, :memory, 'memory should be in uninstalled list'
      records = @index[:packages][:memory][:installed]
      assert_empty records, 'installed records should be removed after uninstall'
    end
  end

  def test_uninstall_modifies_index_in_place
    with_build_index_override do
      before_count = @index[:packages][:memory][:installed].size
      Ssot::Lib::Common.uninstall_packages(@index, 'opencode', dry_run: false)
      after_count = @index[:packages][:memory][:installed].size
      assert_equal before_count - 1, after_count, 'should have one fewer installed record'
    end
  end

  def test_uninstall_dry_run_does_not_modify_index
    with_build_index_override do
      before = @index[:packages][:memory][:installed].dup
      Ssot::Lib::Common.uninstall_packages(@index, 'opencode', dry_run: true)
      assert_equal before, @index[:packages][:memory][:installed], 'dry-run should not modify index'
    end
  end

  def test_uninstall_returns_package_names
    with_build_index_override do
      result = Ssot::Lib::Common.uninstall_packages(@index, 'opencode', dry_run: false)
      assert_kind_of Array, result
      assert_includes result, :memory
    end
  end

  def test_uninstall_skips_not_installed_packages
    # No packages installed on a different platform
    result = Ssot::Lib::Common.uninstall_packages(@index, 'crush', dry_run: false)
    assert_empty result, 'should return empty list when nothing is installed on platform'
  end

  def test_uninstall_does_not_write_index_to_disk
    # Verify uninstall only modifies in-memory index
    with_build_index_override do
      index_file = @ssot_root.join('index.yaml')
      # Write index to disk before uninstall
      index_file.write(@index.to_yaml)
      original_content = index_file.read

      Ssot::Lib::Common.uninstall_packages(@index, 'opencode', dry_run: false)
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
      result = Ssot::Lib::Common.uninstall_packages(@index, 'opencode', dry_run: false)
      assert_equal 1, result.count(:memory), 'memory should appear only once in result'
    end
  end
end
