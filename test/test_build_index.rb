# frozen_string_literal: true

# Unit tests for BuildIndex — the single owner of build/index.yaml.

require_relative 'helper'
require 'yaml'
require 'fileutils'
require 'rulepack/build_index'

class TestBuildIndex < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-build-index-test-')
    @root = Pathname.new(@tmpdir)
    @build_dir = @root.join('build')
    @build_dir.mkpath

    @paths = Rulepack::Paths.new(root: @root, build_dir: @build_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def in_scope(&block)
    Rulepack::Common.with_paths(@paths, &block)
  end

  def write_build_index(hash)
    (@build_dir / 'index.yaml').write(hash.to_yaml)
  end

  # ─── Load semantics ───────────────────────────────────────────────────────────

  def test_load_raises_build_index_not_found_when_missing
    in_scope do
      error = assert_raises(Rulepack::BuildIndexNotFound) { Rulepack::BuildIndex.load }
      assert_match(/Build index not found/, error.message)
      assert_includes error.message, @build_dir.join('index.yaml').to_s
    end
  end

  def test_load_or_nil_returns_nil_when_missing
    in_scope do
      assert_nil Rulepack::BuildIndex.load_or_nil
    end
  end

  def test_load_round_trips_existing_index
    write_build_index({ version: 3.0, generated: 'x', packages: { memory: { pkgname: 'memory' } } })
    in_scope do
      index = Rulepack::BuildIndex.load
      assert_equal 'memory', index[:packages][:memory][:pkgname]
    end
  end

  def test_load_defaults_empty_packages_when_key_absent
    write_build_index({ version: 3.0, packages: nil })
    in_scope do
      assert_equal({}, Rulepack::BuildIndex.load[:packages])
    end
  end

  def test_load_raises_build_index_corrupt_on_empty_file
    (@build_dir / 'index.yaml').write('')
    in_scope do
      error = assert_raises(Rulepack::BuildIndexCorrupt) { Rulepack::BuildIndex.load }
      assert_match(/empty or not a YAML mapping/, error.message)
    end
  end

  def test_load_raises_build_index_corrupt_on_unparseable_yaml
    (@build_dir / 'index.yaml').write('{{{ not yaml')
    in_scope do
      error = assert_raises(Rulepack::BuildIndexCorrupt) { Rulepack::BuildIndex.load }
      assert_match(/not valid YAML/, error.message)
    end
  end

  def test_load_returns_distinct_objects_each_call
    write_build_index({ version: 3.0, packages: {} })
    in_scope do
      first = Rulepack::BuildIndex.load
      second = Rulepack::BuildIndex.load
      refute_equal first.object_id, second.object_id,
                   'load must never memoize: Query mutates the returned hash'
    end
  end

  # ─── Write / remove ───────────────────────────────────────────────────────────

  def test_write_builds_the_envelope_and_round_trips
    in_scope do
      Rulepack::BuildIndex.write(packages: { memory: { pkgname: 'memory', pkgver: '1.0.0' } })

      on_disk = Rulepack::IO.load_yaml(@build_dir / 'index.yaml')
      assert_equal Rulepack::SchemaMigration::CURRENT_VERSION, on_disk[:version]
      assert on_disk[:generated], 'write must stamp :generated'
      assert_equal 'memory', on_disk[:packages][:memory][:pkgname]
    end
  end

  def test_remove_is_idempotent
    in_scope do
      Rulepack::BuildIndex.write(packages: {})
      assert Rulepack::BuildIndex.remove
      refute (@build_dir / 'index.yaml').exist?
      assert Rulepack::BuildIndex.remove, 'remove on a missing index is still a success'
    end
  end

  # ─── Backup / restore / cleanup ───────────────────────────────────────────────

  def test_backup_returns_nil_when_no_index_exists
    in_scope do
      assert_nil Rulepack::BuildIndex.backup
    end
  end

  def test_backup_copies_the_index_under_the_scoped_root
    write_build_index({ version: 3.0, packages: { memory: { pkgname: 'memory' } } })
    in_scope do
      backup = Rulepack::BuildIndex.backup
      assert backup.exist?
      assert_match(/index\.yaml\.bak\.\d+\z/, backup.basename.to_s)
      refute backup.to_s.start_with?(@build_dir.to_s),
             'the backup must live outside build/ — Build.run wipes that directory on rebuild'
      assert_equal({ version: 3.0, packages: { memory: { pkgname: 'memory' } } }, Rulepack::IO.load_yaml(backup))
    end
  end

  def test_restore_puts_the_backup_back
    write_build_index({ version: 3.0, packages: { memory: { pkgname: 'memory' } } })
    in_scope do
      backup = Rulepack::BuildIndex.backup
      assert Rulepack::BuildIndex.remove
      assert Rulepack::BuildIndex.restore(backup)
      assert_equal 'memory', Rulepack::BuildIndex.load[:packages][:memory][:pkgname]
    end
  end

  def test_restore_is_false_for_a_missing_backup
    in_scope do
      refute Rulepack::BuildIndex.restore(nil)
      refute Rulepack::BuildIndex.restore(@build_dir.join('index.yaml.bak.999'))
    end
  end

  def test_cleanup_backups_removes_all_backups
    write_build_index({ version: 3.0, packages: {} })
    in_scope do
      Rulepack::BuildIndex.backup
      Rulepack::BuildIndex.backup
      assert_equal 2, Pathname.glob((@root / 'index.yaml.bak.*').to_s).count
      assert Rulepack::BuildIndex.cleanup_backups
      assert_empty Pathname.glob((@root / 'index.yaml.bak.*').to_s)
    end
  end

  # ─── Scope override ───────────────────────────────────────────────────────────

  def test_scope_override_redirects_the_store
    other_dir = Pathname.new(Dir.mktmpdir('rulepack-build-index-other-'))
    other_paths = @paths.merge(build_dir: other_dir)
    Rulepack::Common.with_paths(other_paths) do
      assert_nil Rulepack::BuildIndex.load_or_nil, 'other scope has no build index'
      Rulepack::BuildIndex.write(packages: {})
    end
    assert other_dir.join('index.yaml').exist?, 'write must land in the overridden scope'
    refute (@build_dir / 'index.yaml').exist?, 'base scope must stay untouched'
  ensure
    FileUtils.rm_rf(other_dir) if other_dir
  end
end
