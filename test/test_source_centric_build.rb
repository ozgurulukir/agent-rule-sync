# frozen_string_literal: true

# Tests for the source-centric build pipeline refactor (ADR-2026-07-29).
#
# Acceptance criteria (post-refactor):
#   1. After `bin/rulepack build`, the build/<plat>/<pkg>/ directory exists for
#      *single-file* (rule/command/import) targets but is ABSENT for
#      skill-bundle/agent format targets. The disk footprint of `build/`
#      is dominated by `git-sources/` and `store/`, not by per-platform copies.
#   2. After `bin/rulepack install <pkg> -t <plat>` for a skill-bundle target,
#      the build/<plat>/<pkg>/ directory is materialized lazily from
#      pkg_index[:source_dir] with manifest.json regenerated from the
#      installed contents.
#   3. The content store (build/store/) deduplicates identical (source_sha,
#      translator, ruleset, transformer) tuples across packages — the same
#      store file is reused when memory, shell, and task-management all
#      share a `copy` + `null translator` pipeline.
#   4. The end-to-end install→check→uninstall contract is preserved for
#      skill-bundle targets (manifest.json present, sub-skills copied, verify
#      passes after install).

require_relative 'helper'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'set'

class TestSourceCentricBuild < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-source-centric-')
    @rulepack_root = Pathname.new(@tmpdir).join('rulepack')
    @rulepack_root.mkpath
    FileUtils.cp_r(ROOT.join('lib').to_s, @rulepack_root.join('lib').to_s, preserve: false)
    FileUtils.cp_r(ROOT.join('data').to_s, @rulepack_root.join('data').to_s, preserve: false)
    index_yaml = @rulepack_root.join('data', 'index.yaml')
    FileUtils.rm_f(index_yaml) if index_yaml.exist?

    mock_git_packages(@rulepack_root.join('data', 'packages'),
                      Pathname.new(@tmpdir).join('mock-repos'))

    @build_dir = @rulepack_root.join('build')
    @build_dir.mkpath
    @home_dir = Pathname.new(@tmpdir).join('home')
    @home_dir.mkpath
    @ruby = File.join(RbConfig::CONFIG['bindir'], 'ruby')
    @env = { 'HOME' => @home_dir.to_s, 'RULEPACK_GIT_DEPTH' => '1' }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def run_build
    system(@ruby, @rulepack_root.join('lib/rulepack/build.rb').to_s,
           chdir: @rulepack_root.to_s)
  end

  def run_install(platform, *args)
    cmd_args = ['--target', platform] + args
    system(@env, @ruby, @rulepack_root.join('lib/rulepack/install.rb').to_s, *cmd_args,
           chdir: @rulepack_root.to_s)
  end

  # ─── AC1: build does not copy skill-bundles to build/<plat>/<pkg>/ ────────

  def test_build_does_not_materialize_skill_bundle_per_platform
    run_build

    # anthropics-skills is a git-source skill-bundle targeting all 14 platforms.
    # After the refactor, no per-platform build/<plat>/anthropics-skills/
    # should exist. (git-sources/ holds the raw material — that's expected.)
    build_root = @build_dir
    per_platform_bundles = Dir.glob(build_root.join('*', 'anthropics-skills')).reject do |path|
      path.include?('git-sources/') || path.include?('store/')
    end
    assert_empty per_platform_bundles,
                 "Skill-bundle should not be materialized per-platform at build time; " \
                 "found: #{per_platform_bundles.inspect}"

    # But the build index should still list all platforms as available.
    index = Rulepack::Common.load_yaml(@build_dir.join('index.yaml'))
    pkg_data = index[:packages]['anthropics-skills'] || index[:packages][:'anthropics-skills']
    assert pkg_data, 'anthropics-skills package should be in build index'
    assert pkg_data[:source_dir], 'anthropics-skills should have a source_dir recorded'
    assert pkg_data[:source_sha256], 'anthropics-skills should have a source_sha256'
  end

  # ─── AC2: install materializes skill-bundle from source_dir lazily ────────

  def test_install_materializes_skill_bundle_lazily
    run_build

    # Pre-condition: anthropics-skills/ is not present in build/opencode/.
    refute @build_dir.join('opencode', 'anthropics-skills').directory?,
           'Skill-bundle should not exist before install (lazy contract)'

    # Install triggers materialization.
    assert run_install('opencode'), 'Install should succeed'

    # Post-condition: build/opencode/anthropics-skills/ is now present with
    # manifest.json (manifest is derived from the materialized contents).
    bundle_build = @build_dir.join('opencode', 'anthropics-skills')
    assert bundle_build.directory?,
           'Skill-bundle should be materialized in build/ after install'
    assert bundle_build.join('manifest.json').exist?,
           'manifest.json should be generated on materialization'
    assert bundle_build.join('SKILL.md').exist?,
           'SKILL.md should be copied from source_dir on materialization'

    # The manifest must reflect the source content, not a stale snapshot.
    manifest = JSON.parse(bundle_build.join('manifest.json').read)
    assert manifest['pkgname'] == 'anthropics-skills'
    assert manifest['sub_skills'].is_a?(Array)
    assert manifest['sub_skills'].size >= 1
  end

  # ─── AC3: store dedup across packages with identical transforms ────────────

  def test_store_dedups_identical_transforms_across_packages
    run_build

    # Count distinct store files. After Aşama 1, build_per_pkg's
    # per-package union cache (build_per_pkg.rb:269-275) collapses 14
    # platforms per package to a single store file when the pipeline is
    # identical (same translator + transformer + format_profile). The total
    # store count is therefore bounded by (distinct source contents ×
    # distinct (translator, transformer) pairs) rather than
    # platform_count × package_count.
    store_files = Dir.glob(@build_dir.join('store', '*')).select { |f| File.file?(f) }

    # Sanity bound: store must contain at least one file (something was built).
    assert store_files.size > 0, 'store/ should not be empty after build'

    # Hard upper bound: rule-only packages (memory, shell, etc.) all share
    # the same (null translator, copy transformer) pipeline; with the
    # per-package union cache they should produce ≤ 1 store file per
    # distinct source content, so 18 packages × distinct sources
    # (~5 distinct contents) is the upper bound. Pre-refactor this was
    # ~14 × 18 = 252 entries.
    platforms_count = 14
    rule_packages_count = 18
    upper_bound = platforms_count * rule_packages_count
    assert store_files.size < upper_bound,
           "store/ has #{store_files.size} files; expected dedupe (upper bound #{upper_bound})"

    # Stronger assertion: 18 packages across 14 platforms with per-package
    # union should produce far fewer than 200 entries.
    assert store_files.size < 100,
           "store/ has #{store_files.size} files; per-package union cache " \
           'should keep this well under 100 for our test fixture'
  end

  # ─── AC4: end-to-end contract preserved ───────────────────────────────────

  def test_skill_bundle_install_uninstall_contract_preserved
    run_build
    assert run_install('opencode'), 'Install should succeed'
    assert run_install('opencode'), 'Second install (idempotent) should succeed'

    bundle_dir = @home_dir.join('.config/opencode/skills/anthropics-skills')
    assert bundle_dir.directory?, 'Skill-bundle install path should exist'
    assert bundle_dir.join('SKILL.md').exist?, 'SKILL.md should be installed'
    assert bundle_dir.join('manifest.json').exist?, 'manifest.json should be installed'
    assert bundle_dir.join('mcp-builder').directory? || bundle_dir.join('mcp-builder/SKILL.md').exist?,
           'Sub-skill mcp-builder should be installed'

    # Verify passes
    check_status = system(@env, @ruby,
                          @rulepack_root.join('lib/rulepack/install.rb').to_s,
                          '--check', '--target', 'opencode',
                          chdir: @rulepack_root.to_s)
    assert check_status, 'Check should pass after skill-bundle install'

    # Uninstall
    uninstall_status = system(@env, @ruby,
                              @rulepack_root.join('lib/rulepack/uninstall.rb').to_s,
                              '--target', 'opencode',
                              chdir: @rulepack_root.to_s)
    assert uninstall_status, 'Uninstall should succeed'

    refute bundle_dir.exist?, 'Skill-bundle should be removed after uninstall'
  end
end
