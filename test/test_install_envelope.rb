# frozen_string_literal: true

# Install Result-envelope contract: requested-but-skipped packages (downgrade
# without --force, missing built artifact, unknown install type, vendor
# aggregation failure) must reach data[:failed_packages] and flip the status
# to :partial — never exit as a silent success. Rollback failures carry the
# index restore outcome.

require_relative 'helper'
require 'rulepack/installer'
require 'rulepack/aggregate'

class TestInstallEnvelope < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-install-envelope-')
    @root = Pathname.new(@tmpdir)
    @paths = Rulepack::Paths.for_root(@root)
    @root.join('data').mkpath
    @root.join('build').mkpath
    (@paths.index_yaml_path).write({ version: 3.0, packages: {} }.to_yaml)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def install(**options)
    result = nil
    capture_io do
      result = Rulepack::Common.with_paths(@paths) { Rulepack::Install.run_unscoped('opencode', options) }
    end
    result
  end

  def write_build_index(pkgs)
    (@paths.build_index_path).write({ version: 3.0, packages: pkgs }.to_yaml)
  end

  def memory_pkg(install_type: 'symlink')
    {
      pkgname: 'memory', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkg_type: 'rule',
      targets: [{ platform: 'opencode', format: 'rules', output: 'memory.md',
                  install: { type: install_type } }]
    }
  end

  def seed_artifact(pkg, output)
    dir = @paths.build_dir.join('opencode', pkg)
    dir.mkpath
    dir.join(output).write("# #{pkg}")
  end

  # NOTE: a real-run user-scope install resolves base_path to the actual
  # ~/.config/<platform> — the sandbox only relocates repo paths. Success
  # shape is therefore asserted via dry-run (no filesystem writes); the
  # real-run install path is covered by the E2E suite in its own sandboxes.

  def test_dry_run_install_reports_success_without_failed_packages
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    result = install(specific_package: 'memory', dry_run: true)
    assert_equal :success, result.status
    assert_empty result.data[:failed_packages]
  end

  def test_downgrade_skip_reports_partial_with_a_failed_package_entry
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    (@paths.index_yaml_path).write(
      { version: 3.0, packages: { memory: { pkgname: 'memory',
                                            installed: [{ platform: 'opencode', version: '2.0.0', pkgrel: 1, epoch: 0, output: 'memory.md' }] } } }.to_yaml
    )
    result = install(specific_package: 'memory')
    assert_equal :partial, result.status
    entry = result.data[:failed_packages].first
    assert_equal 'memory', entry[:package]
    assert_equal :downgrade_detected, entry[:reason]
    assert_match(/use --force/, entry[:message])
  end

  def test_downgrade_skip_is_recorded_even_in_dry_run
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    (@paths.index_yaml_path).write(
      { version: 3.0, packages: { memory: { pkgname: 'memory',
                                            installed: [{ platform: 'opencode', version: '2.0.0', pkgrel: 1, epoch: 0, output: 'memory.md' }] } } }.to_yaml
    )
    result = install(specific_package: 'memory', dry_run: true)
    assert_equal :partial, result.status, 'a dry-run preview must not report success for a would-be downgrade skip'
    assert_equal :downgrade_detected, result.data[:failed_packages].first[:reason]
  end

  def test_missing_built_artifact_reports_partial_with_a_failed_package_entry
    write_build_index(memory: memory_pkg)
    result = install(specific_package: 'memory')
    assert_equal :partial, result.status
    entry = result.data[:failed_packages].first
    assert_equal 'memory', entry[:package]
    assert_equal :missing_built_artifact, entry[:reason]
  end

  def test_unknown_install_type_reports_partial_with_a_failed_package_entry
    write_build_index(memory: memory_pkg(install_type: 'bogus'))
    seed_artifact('memory', 'memory.md')
    result = install(specific_package: 'memory')
    assert_equal :partial, result.status
    entry = result.data[:failed_packages].first
    assert_equal 'memory', entry[:package]
    assert_equal :unknown_install_type, entry[:reason]
    assert_empty result.data[:installed], 'a package whose install type is unknown must not be marked installed'
  end

  def test_vendor_aggregation_failure_is_recorded_on_the_context
    write_build_index({})
    ctx = Rulepack::Install::InstallContext.new(dry_run: false, journal: [], quiet: true)
    capture_io do
      Rulepack::Common.with_paths(@paths) do
        Rulepack::Aggregate.stub(:run, ->(_opts) { raise Rulepack::BuildIndexNotFound, 'no index' }) do
          Rulepack::InstallExecute.aggregate_vendor_skills('opencode', { skill_file: 'skills.md' }, @root.join('base'), ctx)
        end
      end
    end
    entry = ctx.failures.find { |f| f[:reason] == :vendor_aggregation_failed }
    assert entry, 'vendor aggregation failure must reach ctx.failures'
    assert_nil entry[:package]
  end

  def test_rollback_failure_surfaces_the_index_restore_outcome
    write_build_index(memory: memory_pkg)
    seed_artifact('memory', 'memory.md')
    Rulepack::InstallExecute.stub(:install_platform,
                                  ->(_ctx, specific_package: nil) { raise Rulepack::StateError, 'boom' }) do
      result = install(specific_package: 'memory')
      assert_equal :failure, result.status
      assert_equal true, result.data[:index_restored], 'a real-run install backs up the index, so rollback must restore it'
      assert result.data[:backup]
    end
  end

  # ─── Agent lazy materialization (source-centric build) ────────────────────────

  def agent_pkg
    {
      pkgname: 'ruby-agent', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkg_type: 'agent',
      source_dir: @source_dir.to_s, source_sha256: 'deadbeef',
      targets: [{ platform: 'opencode', format: 'agent', output: '.',
                  install: { type: 'copy', target_dir: 'ruby-agent/' } }]
    }
  end

  def seed_agent_source
    @source_dir = @root.join('git-sources', 'ruby-agent')
    @source_dir.mkpath
    @source_dir.join('agent.md').write('# agent instructions')
  end

  def test_agent_artifact_materializes_verbatim_from_source_on_install
    seed_agent_source
    built_path = @paths.build_dir.join('opencode', 'ruby-agent')
    ctx = Rulepack::Install::InstallContext.new(dry_run: false, journal: [], quiet: true, failures: [])
    Rulepack::Common.with_paths(@paths) do
      ok = capture_io do
        Rulepack::InstallExecute.ensure_agent_artifact('ruby-agent', agent_pkg, 'opencode', built_path, ctx, dry_run: false)
      end
      assert ok, 'materialization must succeed with source material present'
    end
    assert built_path.directory?, 'agent tree must be materialized into build/<plat>/<pkg>/'
    assert built_path.join('agent.md').exist?
    assert_empty ctx.failures
  end

  def test_agent_dry_run_with_source_material_reports_success_without_writing
    seed_agent_source
    # String key: dispatch resolves packages by pkgname.to_s — an underscore
    # key would be silently skipped by the specific-package filter.
    write_build_index('ruby-agent' => agent_pkg)
    result = install(specific_package: 'ruby-agent', dry_run: true)
    assert_equal :success, result.status
    assert_empty result.data[:failed_packages]
    refute @paths.build_dir.join('opencode', 'ruby-agent').directory?,
           'dry-run must not materialize the agent tree'
  end

  def test_agent_without_artifact_or_source_reports_missing_built_artifact
    write_build_index('ruby-agent' => agent_pkg)
    result = install(specific_package: 'ruby-agent', dry_run: true)
    assert_equal :partial, result.status
    assert_equal :missing_built_artifact, result.data[:failed_packages].first[:reason]
  end
end
