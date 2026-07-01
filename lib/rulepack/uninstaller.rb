# frozen_string_literal: true

require 'set'
require 'pathname'
require 'fileutils'
require_relative 'common'
require_relative 'lib/transaction'
require_relative 'aggregate'

module Rulepack
  module Uninstaller
    module_function

    # ─── CLI dispatch: replaces uninstall.rb duplication ──────────────────────────
    def dispatch(options)
      package_arg    = options[:package_name]
      target_arg     = options[:target]
      project_arg    = options[:project_path]
      dry_run        = options[:dry_run]

      Rulepack::Logging.log_file = Rulepack::Common.build_dir.join('uninstall.log')

      # Check positional count
      if options[:positional]&.size.to_i > 1
        return Rulepack::Result.new(status: :failure, errors: ["Too many positional arguments. Usage: rulepack uninstall [package] --target <platform|all>"])
      end

      # ── Index required ─────────────────────────────────────────────────────────
      unless Rulepack::Common.index_yaml_path.exist?
        return Rulepack::Result.new(
          status: :failure,
          errors: ["Installed index not found at #{Rulepack::Common.index_yaml_path}. Nothing is installed."]
        )
      end

      index = Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
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

      # ── Execute uninstall ──────────────────────────────────────────────────────
      backup_path = nil
      backup_path = Rulepack::Common.backup_index unless dry_run

      uninstalled_total = []
      begin
        uninstalled_total = execute_uninstall(targets_to_uninstall, index, registry, target_package, project_arg, dry_run)

        # Pacman-R mimic: drop ghost packages with no remaining installed platforms
        index[:packages].reject! { |_, pkg| (pkg[:installed] || []).empty? }

        # Save updated index
        unless dry_run
          index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          Rulepack::Common.write_yaml_atomic(Rulepack::Common.index_yaml_path, index)
          Rulepack::Common.log "\u{1f4dd} Index updated: #{Rulepack::Common.index_yaml_path}"
        end
      rescue StandardError => e
        if backup_path && Rulepack::Common.restore_index(backup_path)
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
        Rulepack::Common.cleanup_backups rescue nil
      end

      messages = uninstall_messages(uninstalled_total, dry_run)
      Rulepack::Result.new(
        status: :success,
        data: {
          uninstalled: uninstalled_total.uniq,
          targets: targets_to_uninstall,
          dry_run: dry_run
        },
        messages: messages
      )
    end

    # ─── Resolve target platforms for uninstall ──────────────────────────────────

    def resolve_uninstall_targets(target_arg, target_package, index, registry, project_arg)
      targets = []
      if target_arg.downcase == 'all'
        if target_package
          pkg_idx = index[:packages][target_package.to_sym] || index[:packages][target_package.to_s] || {}
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
        cfg = registry[p.to_sym] || registry[p.to_s]
        raise "Unknown target platform '#{p}'." unless cfg
        raise "Platform '#{cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>." if cfg[:scope] == 'project' && !project_arg
      end
      targets
    end

    # ─── Execute uninstall across platforms ──────────────────────────────────────

    def execute_uninstall(targets, index, registry, target_package, project_arg, dry_run)
      uninstalled_total = []

      targets.each do |platform_id|
        Rulepack::Common.log "\u{1f9f9} Uninstalling from platform: #{platform_id} #{'(dry-run)' if dry_run}"
        puts "\u{1f9f9} Uninstalling from platform: #{platform_id} #{'(dry-run)' if dry_run}"

        platform_cfg = registry[platform_id.to_sym] || registry[platform_id.to_s]
        project_root = project_arg ? Pathname.new(project_arg).expand_path : nil
        base_path = project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))

        # Skill platforms: remove aggregated vendor skill
        if platform_cfg[:type] == 'skill' && !target_package
          remove_vendor_skill(base_path, platform_cfg, dry_run)
        end

        specific_list = target_package ? [target_package] : nil
        uninstalled = uninstall_packages(index, platform_id,
                                         dry_run: dry_run,
                                         project_root: project_root,
                                         specific_packages: specific_list)
        uninstalled_total.concat(uninstalled)

        # Skill platforms: re-aggregate vendor skills after removals
        if platform_cfg[:type] == 'skill' && !dry_run
          reaggregate_vendor_skills(platform_id)
        end
      end

      uninstalled_total
    end

    # ─── Remove vendor skill for skill-type platforms ────────────────────────────

    def remove_vendor_skill(base_path, platform_cfg, dry_run)
      Rulepack::Common.log '  \u{1f3af} Skill platform: removing vendor skill'
      vendor_path = base_path.join(platform_cfg[:skill_file])
      return unless vendor_path.exist?

      if dry_run
        Rulepack::Common.log "    [DRY-RUN] Would remove vendor skill: #{vendor_path}"
      else
        FileUtils.rm(vendor_path)
        Rulepack::Common.log '    \u{2713} Removed vendor skill'
      end
    end

    # ─── Re-aggregate vendor skills via direct API call ──────────────────────────

    def reaggregate_vendor_skills(platform_id)
      Rulepack::Common.log "  \u{1f9f1} Re-aggregating vendor skills for #{platform_id}..."
      begin
        Rulepack::Aggregate.run(target: platform_id)
        Rulepack::Common.log '    \u{2713} Vendor skill regenerated'
      rescue StandardError => e
        Rulepack::Common.log_warn "    \u{26a0} Aggregation error: #{e.message}"
      end
    end

    # ─── Core: uninstall packages from a platform (modifies index in-place) ──────

    def uninstall_packages(index, platform_id, dry_run: false, project_root: nil,
                           specific_packages: nil, ctx: nil)
      platform_cfg = Rulepack::Common.platform_config(platform_id, Rulepack::Common.load_platform_registry)
      base_path = project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
      build_index = Rulepack::Common.load_yaml(Rulepack::Common.build_index_path)
      pkg_names = resolve_pkg_targets(index, platform_id, specific_packages)

      uninstalled = []
      pkg_names.each do |pkgname|
        result = uninstall_single_package(pkgname, index, build_index, platform_id,
                                          platform_cfg, base_path, dry_run, ctx)
        uninstalled << result if result
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
      pkg_index = index[:packages][pkgname.to_sym] || index[:packages][pkgname.to_s]
      return nil unless pkg_index

      records = pkg_index[:installed] || []
      platform_records = records.select { |r| r[:platform] == platform_id }
      return nil if platform_records.empty?

      pkgdata = build_index[:packages][pkgname.to_sym] || build_index[:packages][pkgname.to_s]
      unless pkgdata
        Rulepack::Common.log_error "Package not found in build index: #{pkgname}"
        return nil
      end
      targets = pkgdata[:targets]&.select { |t| t[:platform] == platform_id } || []
      target_by_output = targets.to_h { |t| [t[:output], t] }

      platform_records.each do |rec|
        removed = uninstall_record(rec, target_by_output, platform_cfg, base_path, pkgname, dry_run, ctx)
        records.delete(rec) if removed && !dry_run
      end
      pkgname
    end

    def uninstall_record(rec, target_by_output, platform_cfg, base_path, pkgname, dry_run, ctx = nil)
      output = rec[:output]
      target = target_by_output[output]
      unless target
        Rulepack::Common.log_warn "  \u{26a0} No target found for output '#{output}' in #{pkgname}, skipping uninstall"
        return false
      end
      if dry_run
        Rulepack::Common.log "    [DRY-RUN] Would remove: #{output}"
        if target[:format] != 'skill-bundle' && target[:format] != 'agent'
          begin
            install_path = Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
            if install_path.exist? && install_path.file? && !install_path.symlink?
              content = install_path.read
              start_marker = "<!-- rulepack:#{pkgname} start -->"
              end_marker = "<!-- rulepack:#{pkgname} end -->"
              if content.include?(start_marker) && content.include?(end_marker)
                puts "    \e[1;36m[DRY-RUN] Diff for #{install_path.basename} (Excising lines):\e[0m"
                puts "    \e[31m- #{start_marker}\e[0m"
                pattern = /#{Regexp.escape(start_marker)}\n(.*?)\n#{Regexp.escape(end_marker)}/m
                if content =~ pattern
                  extracted = $1
                  extracted.each_line do |line|
                    puts "    \e[31m- #{line.chomp}\e[0m"
                  end
                end
                puts "    \e[31m- #{end_marker}\e[0m"
              else
                puts "    \e[1;33m[DRY-RUN] File will be completely deleted: #{install_path.basename}\e[0m"
              end
            end
          rescue StandardError => e
            Rulepack::Common.log_warn "Could not resolve dry-run diff: #{e.message}"
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
          raise "Platform #{platform_cfg[:display_name] || platform_cfg} has no skills_dir for skill-bundle"
        end
        target_dir = install_cfg[:target_dir] || raise("Missing target_dir: #{pkgname}")
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
          res = Rulepack::Common.remove_marked_content(path, pkgname)
          if res == :removed
            Rulepack::Common.log "    \u{2713} Excised package content from: #{path}"
            return
          elsif res == :file_removed
            Rulepack::Common.log "    \u{2713} Removed empty file: #{path}"
            return
          end
        end

        if path.file? || path.symlink?
          FileUtils.rm(path)
        else
          FileUtils.rm_rf(path)
        end
        Rulepack::Common.log "    \u{2713} Removed: #{path}"
      else
        Rulepack::Common.log "    \u{2713} Already removed: #{path}"
      end
    end

    # Migrate installed records to include pkgrel/epoch if missing (for old index)
    def migrate_installed_records(pkg_index)
      return if pkg_index[:installed].nil?

      unless pkg_index[:installed].is_a?(Array)
        pkg_index[:installed] = []
        return
      end

      pkg_index[:installed].each do |rec|
        rec[:pkgrel] ||= 1
        rec[:epoch] ||= 0
      end
    end

    def uninstall_messages(uninstalled_total, dry_run)
      msgs = []
      msgs << "\n[DRY-RUN] Index write skipped" if dry_run
      msgs << "\n📝 Index updated" unless dry_run
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
