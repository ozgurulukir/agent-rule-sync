# frozen_string_literal: true

# Lockfile wiring contract: `rulepack lock <pkg>... [--remove]` is the only
# writer of rulepack.lock (pinning from build/index.yaml), and
# `install --locked` enforces the pinned (version, source_sha256) tuple per
# package — a mismatch or an unpinned package is skipped as a failed_packages
# entry (:lock_mismatch) that flips the Result to :partial, previews included.

require_relative 'helper'
require 'fileutils'
require 'rulepack/installer'
require 'rulepack/lock'
require 'rulepack/lockfile'
require 'rulepack/cli_parser'

class TestLockWiring < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-lock-wiring-')
    @root = Pathname.new(@tmpdir)
    @paths = Rulepack::Paths.for_root(@root)
    @root.join('data').mkpath
    @root.join('build').mkpath
    (@paths.index_yaml_path).write({ version: 3.0, packages: {} }.to_yaml)
    @lock_path = @root.join('rulepack.lock')
    @lockfile = Rulepack::Lockfile.new(@lock_path)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def write_build_index(pkgs)
    (@paths.build_index_path).write({ version: 3.0, packages: pkgs }.to_yaml)
  end

  def memory_pkg
    {
      pkgname: 'memory', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkg_type: 'rule',
      source_sha256: 'deadbeef',
      targets: [{ platform: 'opencode', format: 'rules', output: 'memory.md',
                  install: { type: 'symlink' } }]
    }
  end

  def seed_artifact(pkg, output)
    dir = @paths.build_dir.join('opencode', pkg)
    dir.mkpath
    dir.join(output).write("# #{pkg}")
  end

  def lock_run(options)
    result = nil
    capture_io do
      result = Rulepack::Common.with_paths(@paths) do
        Rulepack::Lock.run_unscoped(options, @lockfile)
      end
    end
    result
  end

  def install(**options)
    result = nil
    capture_io do
      result = Rulepack::Common.with_paths(@paths) do
        Rulepack::Install.run_unscoped('opencode', options)
      end
    end
    result
  end

  # ─── lock command ──────────────────────────────────────────────────────────────

  def test_lock_pin_writes_version_and_source_hash_from_the_build_index
    write_build_index(memory: memory_pkg)
    result = lock_run({ positional: ['memory'] })
    assert_equal :success, result.status
    assert_path_exists @lock_path
    entry = @lockfile.entries['memory']
    assert_equal '1.0.0', entry['version']
    assert_equal 'deadbeef', entry['source_sha256']
    assert_match(/Pinned memory 1\.0\.0/, result.messages.first)
  end

  def test_bare_lock_reports_status_without_writing
    write_build_index(memory: memory_pkg)
    result = lock_run({})
    assert_equal :success, result.status
    assert_empty result.data[:entries]
    refute_path_exists @lock_path, 'a bare status report must not create the file'
  end

  def test_lock_remove_unpins_and_rewrites_the_file
    write_build_index(memory: memory_pkg)
    lock_run({ positional: ['memory'] })
    result = lock_run({ positional: ['memory'], remove: true })
    assert_equal :success, result.status
    assert_empty @lockfile.entries
    assert_match(/Unpinned memory/, result.messages.first)
  end

  def test_lock_unknown_package_fails_without_pin
    write_build_index(memory: memory_pkg)
    result = lock_run({ positional: ['nope'] })
    assert_equal :failure, result.status
    assert_match(/not found in build index/, result.errors.first)
    assert_empty @lockfile.entries
  end

  def test_lock_without_build_index_fails
    result = lock_run({ positional: ['memory'] })
    assert_equal :failure, result.status
    assert_match(/No build index found/, result.messages.first)
  end

  # ─── install --locked ──────────────────────────────────────────────────────────

  def test_locked_install_skips_version_mismatch_as_partial
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    @lockfile.add('memory', version: '2.0.0', source_sha256: 'deadbeef')
    result = install(specific_package: 'memory', locked_mode: true, lockfile: @lockfile)
    assert_equal :partial, result.status
    entry = result.data[:failed_packages].first
    assert_equal 'memory', entry[:package]
    assert_equal :lock_mismatch, entry[:reason]
    assert_match(/Version mismatch/, entry[:message])
    assert_empty result.data[:installed]
  end

  def test_locked_install_skips_unpinned_packages_as_partial
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    result = install(specific_package: 'memory', locked_mode: true, lockfile: @lockfile)
    assert_equal :partial, result.status
    entry = result.data[:failed_packages].first
    assert_equal :lock_mismatch, entry[:reason]
    assert_match(/not pinned/, entry[:message])
  end

  def test_locked_install_source_hash_mismatch_is_reported
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    @lockfile.add('memory', version: '1.0.0', source_sha256: 'cafebabe')
    result = install(specific_package: 'memory', locked_mode: true, lockfile: @lockfile)
    assert_equal :partial, result.status
    assert_match(/Source hash mismatch/, result.data[:failed_packages].first[:message])
  end

  def test_locked_dry_run_with_a_matching_pin_stays_success
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    @lockfile.add('memory', version: '1.0.0', source_sha256: 'deadbeef')
    result = install(specific_package: 'memory', dry_run: true, locked_mode: true, lockfile: @lockfile)
    assert_equal :success, result.status
    assert_empty result.data[:failed_packages]
  end

  def test_without_the_locked_flag_a_stale_lockfile_is_ignored
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    @lockfile.add('memory', version: '9.9.9')
    result = install(specific_package: 'memory', dry_run: true, lockfile: @lockfile)
    assert_equal :success, result.status
    assert_empty result.data[:failed_packages]
  end

  # ─── parser ────────────────────────────────────────────────────────────────────

  def test_parser_accepts_remove_and_drops_extra_positional
    options = Rulepack::CliParser.parse(['--remove', 'memory', 'shell'])
    assert_equal true, options[:remove]
    assert_equal 'memory', options[:package_name]
    assert_equal %w[memory shell], options[:positional]
    refute options.key?(:extra_positional), 'extra_positional was a dead parser key'
  end
end
