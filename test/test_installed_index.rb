# frozen_string_literal: true

# Unit tests for InstalledIndex — the single owner of data/index.yaml.

require_relative 'helper'
require 'yaml'
require 'fileutils'
require 'rulepack/installed_index'

class TestInstalledIndex < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-installed-index-test-')
    @root = Pathname.new(@tmpdir)
    @build_dir = @root.join('build')
    @install_dir = @root.join('install')
    @build_dir.mkpath
    @install_dir.mkpath

    @paths = Rulepack::Paths.new(
      root: @root,
      build_dir: @build_dir,
      index_yaml_path: @install_dir.join('index.yaml')
    )
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def in_scope(&block)
    Rulepack::Common.with_paths(@paths, &block)
  end

  # ─── Strict vs lenient load ───────────────────────────────────────────────────

  def test_load_raises_index_not_found_when_missing
    in_scope do
      error = assert_raises(Rulepack::IndexNotFound) { Rulepack::InstalledIndex.load }
      assert_match(/Installed index not found/, error.message)
      assert_includes error.message, @install_dir.join('index.yaml').to_s
    end
  end

  def test_load_raises_index_corrupt_on_empty_file
    # An existing-but-empty index is lost state, not "nothing installed":
    # reading it as fresh would let install silently overwrite the wreckage.
    (@install_dir / 'index.yaml').write('')
    in_scope do
      error = assert_raises(Rulepack::IndexCorrupt) { Rulepack::InstalledIndex.load }
      assert_match(/empty or not a YAML mapping/, error.message)
    end
  end

  def test_load_raises_index_corrupt_on_unparseable_yaml
    (@install_dir / 'index.yaml').write('{{{ not yaml')
    in_scope do
      # Psych::SyntaxError must surface as the typed corrupt error, never raw.
      error = assert_raises(Rulepack::IndexCorrupt) { Rulepack::InstalledIndex.load }
      assert_match(/not valid YAML/, error.message)
    end
  end

  def test_load_or_fresh_warns_and_degrades_on_corrupt_file
    (@install_dir / 'index.yaml').write('')
    in_scope do
      index = Rulepack::InstalledIndex.load_or_fresh
      assert_equal Rulepack::SchemaMigration::CURRENT_VERSION, index[:version]
      assert_equal({}, index[:packages])
    end
  end

  def test_load_or_fresh_returns_fresh_index_when_missing
    in_scope do
      index = Rulepack::InstalledIndex.load_or_fresh
      assert_equal Rulepack::SchemaMigration::CURRENT_VERSION, index[:version]
      assert_equal({}, index[:packages])
    end
  end

  # ─── Migration through load ───────────────────────────────────────────────────

  def test_load_migrates_legacy_index
    # Pre-migration shape: no version, no pkg_type, records without
    # epoch/pkgrel, no checksums.built. Written directly to disk.
    legacy = {
      packages: {
        memory: {
          pkgname: 'memory',
          pkgver: '1.0.0',
          installed: [{ platform: 'opencode', version: '1.0.0', output: 'memory.md' }]
        }
      }
    }
    (@install_dir / 'index.yaml').write(legacy.to_yaml)

    in_scope do
      index = Rulepack::InstalledIndex.load
      assert_equal Rulepack::SchemaMigration::CURRENT_VERSION, index[:version]
      pkg = index[:packages][:memory]
      assert_equal 'rule', pkg[:pkg_type], 'schema migration must derive pkg_type on load'
      assert_equal({}, pkg[:checksums][:built])
      record = pkg[:installed].first
      assert_equal 1, record[:pkgrel], 'legacy record normalization must default pkgrel'
      assert_equal 0, record[:epoch], 'legacy record normalization must default epoch'
    end
  end

  # ─── Save ─────────────────────────────────────────────────────────────────────

  def test_save_stamps_generated_and_round_trips
    in_scope do
      index = Rulepack::InstalledIndex.load_or_fresh
      index[:packages][:memory] = { pkgname: 'memory', installed: [] }
      Rulepack::InstalledIndex.save(index)

      on_disk = Rulepack::IO.load_yaml(@install_dir / 'index.yaml')
      assert_equal 'memory', on_disk[:packages][:memory][:pkgname]
      assert on_disk[:generated], 'save must stamp :generated'
    end
  end

  def test_save_writes_through_the_scoped_path_not_the_repo
    # A scope relocated index path must never see the repo's real index.
    in_scope do
      Rulepack::InstalledIndex.save(Rulepack::InstalledIndex.load_or_fresh)
    end
    assert (@install_dir / 'index.yaml').exist?, 'sandbox index must be written inside the scope'
  end

  # ─── No memoization ───────────────────────────────────────────────────────────

  def test_load_returns_distinct_objects_each_call
    (@install_dir / 'index.yaml').write({ version: 3.0, packages: {} }.to_yaml)
    in_scope do
      first = Rulepack::InstalledIndex.load
      second = Rulepack::InstalledIndex.load
      refute_equal first.object_id, second.object_id,
                   'load must never memoize: callers mutate the hash in place'
      first[:packages][:mutated] = {}
      assert_empty second[:packages], 'mutating one load must not leak into the next'
    end
  end

  # ─── Backup / restore / cleanup ───────────────────────────────────────────────

  def test_backup_returns_nil_when_index_absent
    in_scope do
      assert_nil Rulepack::InstalledIndex.backup
    end
  end

  def test_backup_restore_round_trip_and_cleanup
    index = { version: 3.0, packages: { memory: { pkgname: 'memory' } } }
    (@install_dir / 'index.yaml').write(index.to_yaml)

    in_scope do
      backup_path = Rulepack::InstalledIndex.backup
      assert backup_path&.exist?, 'backup must exist after backing up'

      # Corrupt the live index after the backup
      (@install_dir / 'index.yaml').write({ version: 3.0, packages: {} }.to_yaml)
      assert Rulepack::InstalledIndex.restore(backup_path), 'restore must succeed'

      restored = Rulepack::IO.load_yaml(@install_dir / 'index.yaml')
      assert restored[:packages][:memory], 'restore must bring back the pre-backup packages'

      assert Rulepack::InstalledIndex.cleanup_backups
      backups = @install_dir.children.select { |p| p.basename.to_s.start_with?('index.yaml.bak.') }
      assert_empty backups, 'cleanup must remove all index backups'
    end
  end
end
