# frozen_string_literal: true

require_relative 'encoding_defaults'
require 'pathname'
require 'fileutils'
require 'set'
require 'stringio'
require_relative 'common'
require_relative 'installer'
require_relative 'verify'
require_relative 'installed_state'

module Rulepack
  module Fix
    module_function

    def run(options = {}, paths: nil, ui: nil)
      if ui
        Rulepack::Common.with_ui(ui) { run(options, paths: paths) }
      elsif paths
        Rulepack::Common.with_paths(paths) { run_unscoped(options) }
      else
        run_unscoped(options)
      end
    end

    def run_unscoped(options = {})
      package_arg = options[:package_name]
      target_arg = options[:target]
      project_arg = options[:project_path]
      dry_run = options.fetch(:dry_run, false)
      auto_mode = options.fetch(:auto, false)

      unless Rulepack::Common.build_index_path.exist?
        msg = 'Build index not found. Run build first.'
        return Rulepack::Result.new(status: :failure, errors: [msg])
      end

      unless Rulepack::Common.index_yaml_path.exist?
        msg = "Installed index not found at #{Rulepack::Common.index_yaml_path}. Nothing is installed."
        return Rulepack::Result.new(status: :failure, errors: [msg])
      end

      index = Rulepack::IO.load_yaml(Rulepack::Common.index_yaml_path)
      packages = index[:packages] || {}
      registry = Rulepack::Common.load_platform_registry

      targets_to_fix, target_package = begin
        Rulepack::Validation.validate_targets_and_packages(
          target_arg, package_arg, packages, registry,
          exit_on_failure: false,
          project_arg: project_arg,
          enforce_project_scope: true
        )
      rescue StandardError => e
        return Rulepack::Result.new(status: :failure, errors: [e.message])
      end

      if targets_to_fix.empty?
        return Rulepack::Result.new(
          status: :success,
          data: { platforms: [], fixed: [], orphans_removed: [] },
          messages: ['ℹ No fixes needed.']
        )
      end

      fixed = []
      failed = []
      orphans_removed = []

      targets_to_fix.each do |platform_id|
        pf = fix_platform(platform_id, target_package, project_arg, dry_run, auto_mode, index)
        fixed.concat(pf[:fixed] || [])
        failed.concat(pf[:failed] || [])
        orphans_removed.concat(pf[:orphans_removed] || [])
      end

      status = failed.empty? ? :success : :partial

      messages = []
      if fixed.any? || orphans_removed.any?
        messages << "\n✅ Fix applied. Run verify to confirm."
      else
        messages << "\nℹ No fixes needed."
      end

      Rulepack::Result.new(
        status: status,
        data: {
          platforms: targets_to_fix,
          fixed: fixed,
          failed: failed,
          orphans_removed: orphans_removed,
          dry_run: dry_run
        },
        messages: messages
      )
    end

    # Execution Helpers

    def fix_platform(platform_id, package_arg, project_arg, dry_run, auto_mode, index)
      Rulepack::Emitter.emit(:progress, message: "\n── #{platform_id} ──")

      result = Rulepack::Verify.check({ target: platform_id, package_name: package_arg, project_path: project_arg })
      data = result.data || {}
      has_drift = data[:drift].to_i > 0
      # Verify.check returns orphans as an integer count at the top level with
      # the per-platform array inside data[:platforms].  Stubbed results (tests)
      # may pass orphans as a direct array.  Handle both shapes.
      orphans = if data[:orphans].is_a?(Array)
                  data[:orphans]
                else
                  platform_data = (data[:platforms] || []).first || {}
                  platform_data[:orphans] || []
                end

      unless has_drift || orphans.any?
        Rulepack::Emitter.emit(:progress, message: '  ✓ No drift detected.')
        return { fixed: [], failed: [], orphans_removed: [] }
      end

      fixed = []
      failed = []
      orphans_removed = []

      if has_drift
        fd = fix_drift(platform_id, package_arg, project_arg, dry_run, index)
        fixed.concat(fd[:fixed] || [])
        failed.concat(fd[:failed] || [])
      end

      if orphans.any? && package_arg.nil?
        fo = fix_orphans(orphans, dry_run, auto_mode)
        orphans_removed.concat(fo[:orphans_removed] || [])
      end

      { fixed: fixed, failed: failed, orphans_removed: orphans_removed }
    end

    def fix_drift(platform_id, package_arg, project_arg, dry_run, index)
      if dry_run
        Rulepack::Emitter.emit(:progress, message: "  [DRY-RUN] Would reinstall packages on #{platform_id}")
        return { fixed: [], failed: [] }
      end

      broken = find_broken_packages(platform_id, package_arg, project_arg, index)

      if broken.empty?
        Rulepack::Emitter.emit(:progress, message: '  ✓ No broken packages matched.')
        return { fixed: [], failed: [] }
      end

      Rulepack::Emitter.emit(:progress, message: "  Reinstalling #{broken.size} package(s) on #{platform_id}...")

      # Single transactional reinstall: Install.run forces the named packages
      # past the same-version short-circuit, backs up the index, and journals
      # file operations — a failure rolls both back. No disk choreography here.
      install_result = Rulepack::Install.run(
        platform_id,
        force_packages: broken,
        project_arg: project_arg,
        collision_strategy: 'overwrite',
        dry_run: false
      )

      # Build-index package keys are Symbols (YAML round-trip symbolizes);
      # broken is built from pkgname.to_s — normalize before set arithmetic.
      installed = (install_result.data[:installed] || []).map(&:to_s)
      failed = broken - installed
      fixed = broken & installed

      if failed.empty?
        Rulepack::Emitter.emit(:progress, message: '  ✓ Reinstall complete')
      else
        failed.each do |pkgname|
          Rulepack::Emitter.emit(:progress, message: "  ⚠ Reinstall failed for #{pkgname}")
        end
        Rulepack::Emitter.emit(:progress, message: '  ⚠ Reinstall rolled back; index restored.')
      end

      { fixed: fixed, failed: failed }
    end

    def fix_orphans(orphans, dry_run, auto_mode)
      return { orphans_removed: [] } unless orphans.any?

      Rulepack::Emitter.emit(:progress, message: "\n  #{orphans.size} orphan(s) found:")
      orphans.each { |f| Rulepack::Emitter.emit(:progress, message: "    #{f}") }
      if dry_run
        Rulepack::Emitter.emit(:progress, message: '  [DRY-RUN] Would not remove orphans')
        return { orphans_removed: [] }
      end

      should_remove = if auto_mode
        true
      else
        Rulepack::Common.ui.confirm("Remove #{orphans.size} orphan(s)?")
      end

      if should_remove
        Rulepack::Emitter.emit(:progress, message: "  Removing #{orphans.size} orphan(s)...")
        orphans.each { |f| FileUtils.rm_rf(f) }
        Rulepack::Emitter.emit(:progress, message: '  ✓ Orphans removed')
        { orphans_removed: orphans }
      else
        Rulepack::Emitter.emit(:progress, message: '  Skipping orphan removal (use --auto to remove)')
        { orphans_removed: [] }
      end
    end

    def find_broken_packages(platform_id, package_arg, project_arg, index)
      platform_cfg = Rulepack::Common.platform_config(platform_id, Rulepack::Common.load_platform_registry)
      return [] unless platform_cfg

      project_root = project_arg ? Pathname.new(project_arg).expand_path : nil
      base_path = project_root || Pathname.new(Rulepack::Path.expand_user_path(platform_cfg[:base_path]))
      broken = []

      (index[:packages] || {}).each do |pkgname, pkgdata|
        next if package_arg && pkgname.to_s != package_arg
        inst = pkgdata[:installed].is_a?(Array) && pkgdata[:installed].find { |i| i[:platform] == platform_id }
        next unless inst

        target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
        verdict = InstalledState.check(
          installed: inst, target: target, platform_cfg: platform_cfg,
          pkgname: pkgname.to_s, base_path: base_path
        )
        broken << pkgname.to_s if verdict.broken?
      end

      broken
    end
  end
end

