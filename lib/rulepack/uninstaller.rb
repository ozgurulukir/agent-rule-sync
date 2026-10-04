# frozen_string_literal: true

require 'set'
require 'pathname'
require 'fileutils'
require_relative 'common'
require_relative 'models/target'
require_relative 'lib/transaction'
require_relative 'aggregate'

module Rulepack
  module Uninstaller
    module_function

    # ─── CLI dispatch: replaces uninstall.rb duplication ──────────────────────────
    def dispatch(options, paths: nil, ui: nil)
      if ui
        Rulepack::Common.with_ui(ui) { dispatch(options, paths: paths) }
      elsif paths
        Rulepack::Common.with_paths(paths) { dispatch_unscoped(options) }
      else
        dispatch_unscoped(options)
      end
    end

    def dispatch_unscoped(options)
      package_arg    = options[:package_name]
      target_arg     = options[:target]
      project_arg    = options[:project_path]
      dry_run        = options[:dry_run]

      Rulepack::Logging.log_file = Rulepack::Common.build_dir.join('uninstall.log')

      # ── Index required ─────────────────────────────────────────────────────────
      index = begin
        Rulepack::InstalledIndex.load
      rescue Rulepack::IndexNotFound => e
        return Rulepack::Result.new(status: :failure, errors: [e.message])
      end
      registry = Rulepack::Common.load_platform_registry

      # ── Resolve target package ────────────────────────────────────────────────
      target_package = nil
      if package_arg
        unless index[:packages] && (index[:packages].key?(package_arg) || index[:packages].key?(package_arg.to_sym))
          return Rulepack::Result.new(status: :failure, errors: ["Package '#{package_arg}' is not registered as installed in index."])
        end
        target_package = index[:packages].keys.find { |k| k.to_s == package_arg }.to_s
      end

      # ── Target required ───────────────────────────────────────────────────────
      unless target_arg
        return Rulepack::Result.new(status: :failure, errors: ["Please specify target platform(s) with --target <platform> (or --target all)."])
      end

      # ── Resolve targets ───────────────────────────────────────────────────────
      targets_to_uninstall = begin
        resolve_uninstall_targets(target_arg, target_package, index, registry, project_arg)
      rescue StandardError => e
        return Rulepack::Result.new(status: :failure, errors: [e.message])
      end

      if targets_to_uninstall.empty?
        return Rulepack::Result.new(
          status: :success,
          data: { uninstalled: [], targets: [] },
          messages: ['  No target platforms to uninstall.']
        )
      end

      pkg_msg = target_package ? " '#{target_package}' from" : ""
      # Prompt only in interactive contexts; non-interactive runs (pipes, CI,
      # UI::Null) proceed, matching the pre-UI behavior of this command.
      if !dry_run && !options[:force] && Rulepack::Common.ui.interactive? &&
         !Rulepack::Common.ui.confirm("Are you sure you want to uninstall#{pkg_msg} #{targets_to_uninstall.join(', ')}?")
        return Rulepack::Result.new(
          status: :success,
          data: { uninstalled: [], targets: [] },
          messages: ["\n  \e[33m⚠ Uninstall cancelled.\e[0m\n"]
        )
      end

      # ── Execute uninstall ──────────────────────────────────────────────────────
      backup_path = nil
      backup_path = Rulepack::InstalledIndex.backup unless dry_run

      uninstalled_total = []
      failed_total = []
      aggregation_failed = []
      begin
        uninstalled_total, failed_total, aggregation_failed =
          execute_uninstall(targets_to_uninstall, index, registry, target_package, project_arg, dry_run)

        # Pacman-R mimic: drop ghost packages with no remaining installed platforms
        index[:packages].reject! { |_, pkg| (pkg[:installed] || []).empty? }

        # Save updated index
        unless dry_run
          Rulepack::InstalledIndex.save(index)
          Rulepack::Emitter.emit(:progress, message: "\u{1f4dd} Index updated: #{Rulepack::Common.paths.index_yaml_path}")
        end
      rescue StandardError => e
        if backup_path && Rulepack::InstalledIndex.restore(backup_path)
          Rulepack::Common.log_error "Uninstall failed (#{e.message}). Index restored from backup."
          return Rulepack::Result.new(
            status: :failure,
            errors: ["Uninstall failed. Index restored from backup: #{backup_path.basename}"]
          )
        else
          Rulepack::Common.log_error "Uninstall failed (#{e.message})."
          return Rulepack::Result.new(status: :failure, errors: ["Uninstall failed: #{e.message}"])
        end
      ensure
        Rulepack::InstalledIndex.cleanup_backups rescue nil
      end

      missing = failed_total.select { |f| f[:reason] == :missing_from_build_index }
      skipped = failed_total.select { |f| f[:reason] == :records_skipped }

      status =
        if failed_total.any? && uninstalled_total.empty?
          :failure
        elsif failed_total.any? || aggregation_failed.any?
          :partial
        else
          :success
        end

      errors = []
      unless missing.empty?
        errors << "Package(s) absent from the build index were not uninstalled: " \
                  "#{missing.map { |f| f[:package] }.join(', ')}. Run `rulepack build` to refresh it."
      end
      unless skipped.empty?
        errors << "Outputs absent from the build index were left in place: " \
                  "#{skipped.map { |f| "#{f[:package]} (#{f[:outputs].join(', ')})" }.join(', ')}."
      end
      unless aggregation_failed.empty?
        errors << "Vendor-skill re-aggregation failed for: #{aggregation_failed.uniq.join(', ')}."
      end

      messages = uninstall_messages(uninstalled_total, failed_total, aggregation_failed, dry_run)
      Rulepack::Result.new(
        status: status,
        data: {
          uninstalled: uninstalled_total.uniq,
          failed: failed_total.uniq,
          aggregation_failed: aggregation_failed.uniq,
          targets: targets_to_uninstall,
          dry_run: dry_run
        },
        errors: errors,
        messages: messages
      )
    end

    # ─── Resolve target platforms for uninstall ──────────────────────────────────

    def resolve_uninstall_targets(target_arg, target_package, index, registry, project_arg)
      targets = []
      if target_arg.downcase == 'all'
        if target_package
          pkg_idx = Rulepack::Common.lookup(index[:packages], target_package) || {}
          targets = (pkg_idx[:installed] || []).map { |i| i[:platform] }.uniq
        else
          platforms = Set.new
          (index[:packages] || {}).each_value do |pkg|
            (pkg[:installed] || []).each { |i| platforms << i[:platform] }
          end
          targets = platforms.to_a
        end
      else
        targets = target_arg.split(',').map(&:strip).reject(&:empty?)
      end

      targets.each do |p|
        cfg = Rulepack::Common.lookup(registry, p)
        raise Rulepack::UnknownPlatform, "Unknown target platform '#{p}'." unless cfg
        raise Rulepack::ConfigError, "Platform '#{cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>." if cfg[:scope] == 'project' && !project_arg
      end
      targets
    end

    # ─── Execute uninstall across platforms ──────────────────────────────────────

    def execute_uninstall(targets, index, registry, target_package, project_arg, dry_run)
      uninstalled_total = []
      failed_total = []
      aggregation_failed = []

      targets.each do |platform_id|
        Rulepack::Emitter.emit(:progress, message: "\u{1f9f9} Uninstalling from platform: #{platform_id} #{'(dry-run)' if dry_run}")

        platform_cfg = Rulepack::Common.lookup(registry, platform_id)
        project_root = project_arg ? Pathname.new(project_arg).expand_path : nil
        base_path = project_root || Pathname.new(Rulepack::Path.expand_user_path(platform_cfg[:base_path]))

        # Skill platforms: remove aggregated vendor skill
        if platform_cfg[:type] == 'skill' && !target_package
          remove_vendor_skill(base_path, platform_cfg, dry_run)
        end

        specific_list = target_package ? [target_package] : nil
        uninstalled = uninstall_packages(index, platform_id,
                                         dry_run: dry_run,
                                         project_root: project_root,
                                         specific_packages: specific_list,
                                         failures: failed_total)
        uninstalled_total.concat(uninstalled)

        # Skill platforms: re-aggregate vendor skills after removals
        if platform_cfg[:type] == 'skill' && !dry_run
          aggregation_failed << platform_id unless reaggregate_vendor_skills(platform_id)
        end
      end

      [uninstalled_total, failed_total, aggregation_failed]
    end

    # ─── Remove vendor skill for skill-type platforms ────────────────────────────

    def remove_vendor_skill(base_path, platform_cfg, dry_run)
      Rulepack::Emitter.emit(:progress, message: '  \u{1f3af} Skill platform: removing vendor skill')
      vendor_path = base_path.join(platform_cfg[:skill_file])
      return unless vendor_path.exist?

      if dry_run
        Rulepack::Emitter.emit(:progress, message: "    [DRY-RUN] Would remove vendor skill: #{vendor_path}")
      else
        FileUtils.rm(vendor_path)
        Rulepack::Emitter.emit(:progress, message: '    \u{2713} Removed vendor skill')
      end
    end

    # ─── Re-aggregate vendor skills via direct API call ──────────────────────────

    # Returns true when the platform's vendor skill was regenerated. A failure
    # is emitted here but NOT swallowed: the caller records it and downgrades
    # the uninstall Result, so a stale vendor skill never rides a clean exit 0.
    def reaggregate_vendor_skills(platform_id)
      Rulepack::Emitter.emit(:progress, message: "  \u{1f3f1} Re-aggregating vendor skills for #{platform_id}...")
      Rulepack::Aggregate.run({ target: platform_id })
      Rulepack::Emitter.emit(:progress, message: '    \u{2713} Vendor skill regenerated')
      true
    rescue StandardError => e
      Rulepack::Emitter.emit(:progress, message: "    \u{26a0} Aggregation error: #{e.message}")
      false
    end

    # ─── Core: uninstall packages from a platform (modifies index in-place) ──────

    # failures: optional collector Array. A package that cannot be uninstalled
    # (absent from the build index) is appended there instead of evaporating
    # as a dropped nil — callers that surface failures pass a collector;
    # best-effort callers keep the original return shape.
    def uninstall_packages(index, platform_id, dry_run: false, project_root: nil,
                           specific_packages: nil, ctx: nil, failures: nil)
      platform_cfg = Rulepack::Common.platform_config(platform_id, Rulepack::Common.load_platform_registry)
      base_path = project_root || Pathname.new(Rulepack::Path.expand_user_path(platform_cfg[:base_path]))
      build_index = Rulepack::BuildIndex.load
      pkg_names = resolve_pkg_targets(index, platform_id, specific_packages)

      uninstalled = []
      pkg_names.each do |pkgname|
        result = uninstall_single_package(pkgname, index, build_index, platform_id,
                                          platform_cfg, base_path, dry_run, ctx)
        case result
        when :missing_from_build_index
          Rulepack::Common.log_error "Package not found in build index: #{pkgname}"
          failures << { package: pkgname, reason: :missing_from_build_index } if failures
        when Hash
          # Some records were skipped: partially uninstalled at best.
          uninstalled << pkgname if result[:removed_any]
          failures << result if failures
        when nil
          Rulepack::Emitter.emit(:progress, message: "  \u{26a0} #{pkgname} is not installed on #{platform_id}, skipping")
        else
          uninstalled << result
        end
      end
      uninstalled.uniq
    end

    def resolve_pkg_targets(index, platform_id, specific_packages)
      return specific_packages if specific_packages

      index[:packages].select do |_name, pkg|
        pkg[:installed].is_a?(Array) && pkg[:installed].any? { |i| i[:platform] == platform_id }
      end.keys
    end

    def uninstall_single_package(pkgname, index, build_index, platform_id,
                                 platform_cfg, base_path, dry_run, ctx = nil)
      pkg_index = Rulepack::Common.lookup(index[:packages], pkgname)
      return nil unless pkg_index

      records = pkg_index[:installed] || []
      platform_records = records.select { |r| r[:platform] == platform_id }
      return nil if platform_records.empty?

      pkgdata = Rulepack::Common.lookup(build_index[:packages], pkgname)
      return :missing_from_build_index unless pkgdata
      targets = pkgdata[:targets]&.select { |t| t[:platform] == platform_id } || []
      target_by_output = targets.to_h { |t| [t[:output], t] }

      skipped_outputs = []
      platform_records.each do |rec|
        removed = uninstall_record(rec, target_by_output, platform_cfg, base_path, pkgname, dry_run, ctx)
        skipped_outputs << rec[:output] unless removed || dry_run
        records.delete(rec) if removed && !dry_run
      end
      return pkgname if skipped_outputs.empty?

      # Records whose output has no build-index target (stale index after an
      # output rename): the files stay on disk and the records stay in the
      # index. Surface it — a silently skipped removal must not ride a clean
      # exit 0.
      { package: pkgname, reason: :records_skipped, outputs: skipped_outputs,
        removed_any: skipped_outputs.size < platform_records.size }
    end

    def uninstall_record(rec, target_by_output, platform_cfg, base_path, pkgname, dry_run, ctx = nil)
      output = rec[:output]
      target = target_by_output[output]
      unless target
        Rulepack::Emitter.emit(:progress, message: "  \u{26a0} No target found for output '#{output}' in #{pkgname}, skipping uninstall")
        return false
      end
      if dry_run
        Rulepack::Emitter.emit(:progress, message: "    [DRY-RUN] Would remove: #{output}")
        if !Target.materializable_format?(target[:format])
          begin
            install_path = Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
            if install_path.exist? && install_path.file? && !install_path.symlink?
              content = install_path.read
              start_marker = "<!-- rulepack:#{pkgname} start -->"
              end_marker = "<!-- rulepack:#{pkgname} end -->"
              if content.include?(start_marker) && content.include?(end_marker)
                Rulepack::Emitter.emit(:progress, message: "    \e[1;36m[DRY-RUN] Diff for #{install_path.basename} (Excising lines):\e[0m")
                Rulepack::Emitter.emit(:progress, message: "    \e[31m- #{start_marker}\e[0m")
                pattern = /#{Regexp.escape(start_marker)}\n(.*?)\n#{Regexp.escape(end_marker)}/m
                if content =~ pattern
                  extracted = $1
                  extracted.each_line do |line|
                    Rulepack::Emitter.emit(:progress, message: "    \e[31m- #{line.chomp}\e[0m")
                  end
                end
                Rulepack::Emitter.emit(:progress, message: "    \e[31m- #{end_marker}\e[0m")
              else
                Rulepack::Emitter.emit(:progress, message: "    \e[1;33m[DRY-RUN] File will be completely deleted: #{install_path.basename}\e[0m")
              end
            end
          rescue StandardError => e
            Rulepack::Emitter.emit(:progress, message: "Could not resolve dry-run diff: #{e.message}")
          end
        end
        return true
      end
      remove_target_file(target, platform_cfg, base_path, pkgname, ctx)
      true
    end

    def remove_target_file(target, platform_cfg, base_path, pkgname, ctx = nil)
      install_cfg = target[:install] || {}
      case target[:format]
      when 'skill-bundle'
        skills_dir = platform_cfg[:skills_dir]
        unless skills_dir
          return if %w[skill import].include?(platform_cfg[:type].to_s)
          raise Rulepack::ConfigError, "Platform #{platform_cfg[:display_name] || platform_cfg} has no skills_dir for skill-bundle"
        end
        target_dir = install_cfg[:target_dir] || raise(Rulepack::ConfigError, "Missing target_dir: #{pkgname}")
        dest_dir = base_path.join(skills_dir).join(target_dir)
        remove_path(dest_dir, pkgname, ctx)
      else
        install_path = Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
        remove_path(install_path, pkgname, ctx)
      end
    end

    def remove_path(path, pkgname = nil, ctx = nil)
      if path.exist?
        if ctx && !ctx.dry_run
          backup_path = Rulepack::Common.backup_file(path)
          if path.directory?
            Transaction.record_journal(ctx, { action: :replace_dir, path: path, backup: backup_path })
          else
            Transaction.record_journal(ctx, { action: :replace_file, path: path, backup: backup_path })
          end
        end

        if path.file? && !path.symlink? && pkgname
          res = Rulepack::IO.remove_marked_content(path, pkgname)
          if res == :removed
            Rulepack::Emitter.emit(:progress, message: "    \u{2713} Excised package content from: #{path}")
            return
          elsif res == :file_removed
            Rulepack::Emitter.emit(:progress, message: "    \u{2713} Removed empty file: #{path}")
            return
          end
        end

        if path.file? || path.symlink?
          FileUtils.rm(path)
        else
          FileUtils.rm_rf(path)
        end
        Rulepack::Emitter.emit(:progress, message: "    \u{2713} Removed: #{path}")
      else
        Rulepack::Emitter.emit(:progress, message: "    \u{2713} Already removed: #{path}")
      end
    end

    def uninstall_messages(uninstalled_total, failed_total, aggregation_failed, dry_run)
      msgs = []
      msgs << "\n[DRY-RUN] Index write skipped" if dry_run
      msgs << "\n📝 Index updated" unless dry_run
      missing = failed_total.select { |f| f[:reason] == :missing_from_build_index }
      skipped = failed_total.select { |f| f[:reason] == :records_skipped }
      unless missing.empty?
        msgs << "\n⚠ #{missing.size} package(s) not found in build index, not uninstalled:"
        missing.each { |f| msgs << "   • #{f[:package]}" }
      end
      unless skipped.empty?
        msgs << "\n⚠ #{skipped.size} package(s) had outputs missing from the build index (left in place):"
        skipped.each { |f| msgs << "   • #{f[:package]}: #{f[:outputs].join(', ')}" }
      end
      aggregation_failed.uniq.each do |platform_id|
        msgs << "  ⚠ Vendor-skill re-aggregation failed for #{platform_id}"
      end
      if uninstalled_total.empty?
        msgs << '  No packages were uninstalled.'
      else
        msgs << "\n✅ Uninstall complete. #{uninstalled_total.uniq.size} package(s):"
        uninstalled_total.uniq.each { |p| msgs << "   • #{p}" }
      end
      msgs
    end
  end
end
