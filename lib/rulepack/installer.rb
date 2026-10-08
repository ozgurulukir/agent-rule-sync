# frozen_string_literal: true

# Installer library — thin orchestrator
#
# Decision-making lives in install_plan.rb (InstallPlan).
# Execution (symlink/copy/inject/append, verification, vendor aggregation) lives in install_execute.rb (InstallExecute).
# Index file lifecycle lives in installed_index.rb / build_index.rb (the stores).
# This file retains only: run, install_all, install_single_platform,
# dispatch, and stateless CLI helpers.

require 'English'
require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require 'json'
require 'set'
require_relative 'common'
require_relative 'emitter'
require_relative 'lib/transaction'
require_relative 'install_plan'
require_relative 'install_execute'
require_relative 'lockfile'

module Rulepack
  module Install
    module_function

    # Context object to hold installation state and reduce argument counts
    InstallContext = Struct.new(
      :index, :build_index, :platform_id, :platform_cfg, :base_path, :project_root,
      :dry_run, :force_mode, :needed_mode, :collision_strategy, :rules_to, :quiet,
      :select_list, :installed_this_run, :journal, :force_packages, :failures,
      :locked_mode, :lockfile,
      keyword_init: true
    )

    # ─── Main entry point ────────────────────────────────────────────────────────

    def run(platform_id, options = {}, paths: nil, ui: nil)
      if ui
        Rulepack::Common.with_ui(ui) { run(platform_id, options, paths: paths) }
      elsif paths
        Rulepack::Common.with_paths(paths) { run_unscoped(platform_id, options) }
      else
        run_unscoped(platform_id, options)
      end
    end

    def run_unscoped(platform_id, options = {})
      dry_run = options.fetch(:dry_run, false)
      check_mode = options.fetch(:check_mode, false)
      force_mode = options.fetch(:force_mode, false)
      needed_mode = options.fetch(:needed_mode, false)
      verbose_mode = options.fetch(:verbose_mode, false)
      select_list = options.fetch(:select_list, nil)
      project_arg = options.fetch(:project_arg, nil)
      specific_package = options.fetch(:specific_package, nil)
      force_packages = options.fetch(:force_packages, nil)
      collision_strategy = options.fetch(:collision_strategy, 'interactive')
      rules_to = options.fetch(:rules_to, nil)
      locked_mode = options.fetch(:locked_mode, false)
      lockfile = locked_mode ? (options.fetch(:lockfile, nil) || Rulepack::Lockfile.new) : nil

      Rulepack::Logging.log_level = verbose_mode ? :debug : Rulepack::Config.log_level

      return check_platform(platform_id, project_arg: project_arg) if check_mode

      begin
        build_index = Rulepack::BuildIndex.load
      rescue Rulepack::BuildIndexNotFound => e
        Rulepack::Common.log_error(e.message)
        return Rulepack::Result.new(
          status: :failure, errors: [e.message],
          data: { platform_id: platform_id, installed: [] }
        )
      end

      index = Rulepack::InstalledIndex.load_or_fresh

      backup_path = nil
      unless dry_run
        backup_path = Rulepack::InstalledIndex.backup
        Rulepack::Common.log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      installed = []
      ctx = nil
      begin
        ctx = InstallContext.new(
          index: index, build_index: build_index, platform_id: platform_id,
          dry_run: dry_run, force_mode: force_mode, needed_mode: needed_mode,
          collision_strategy: collision_strategy, rules_to: rules_to, select_list: select_list,
          force_packages: force_packages,
          project_root: project_arg ? Pathname.new(project_arg).expand_path : nil,
          installed_this_run: [],
          journal: [],
          failures: [],
          locked_mode: locked_mode,
          lockfile: lockfile
        )
        installed = InstallExecute.install_platform(ctx, specific_package: specific_package).to_a

        if dry_run
          Rulepack::Common.log '[DRY-RUN] Index write skipped'
        else
          Rulepack::InstalledIndex.save(index)
          Rulepack::Common.log "📝 Index written: #{Rulepack::Common.paths.index_yaml_path}"
        end
      rescue StandardError => e
        rollback = Rulepack::Transaction.transaction_rollback(e, backup_path, ctx&.journal)
        return Rulepack::Result.new(
          status: :failure,
          errors: ["Install failed for #{platform_id}: #{e.message}"],
          data: { platform_id: platform_id, installed: installed,
                  index_restored: rollback[:index_restored], backup: rollback[:backup] }
        )
      ensure
        begin
          Rulepack::InstalledIndex.cleanup_backups
        rescue StandardError => e
          # Best-effort cleanup: never let the cleanup failure (or a logging
          # failure) mask the install outcome this ensure is attached to.
          begin
            Rulepack::Common.log_debug "Index backup cleanup failed: #{e.message}"
          rescue StandardError
            warn "Index backup cleanup failed: #{e.message}"
          end
        end
      end

      # Requested-but-skipped packages (downgrade without --force, missing
      # artifact, unknown install type, vendor aggregation failure) must be
      # visible to machine consumers, not just stderr narration.
      failures = Array(ctx.failures)
      status = failures.empty? ? :success : :partial
      messages = install_messages(platform_id, installed, dry_run)
      messages.concat(failures.map { |f| "   ⚠ #{f[:message]}" }) unless failures.empty?
      Rulepack::Result.new(
        status: status,
        data: {
          platform_id: platform_id,
          installed: installed,
          failed_packages: failures,
          dry_run: dry_run
        },
        messages: messages
      )
    end

    # ─── Install all platforms ───────────────────────────────────────────────────

    def install_all(options = {})
      dry_run = options.fetch(:dry_run, false)
      verbose_mode = options.fetch(:verbose_mode, false)

      Rulepack::Logging.log_level = verbose_mode ? :debug : Rulepack::Config.log_level

      registry  = Rulepack::Common.load_platform_registry
      platforms = registry.keys.select do |p|
        cfg = registry[p]
        scope = cfg[:scope] || 'user'
        if scope == 'project'
          !options[:project_arg].nil?
        else
          true
        end
      end

      begin
        build_index = Rulepack::BuildIndex.load
      rescue Rulepack::BuildIndexNotFound => e
        msg = e.message
        Rulepack::Common.log_error(msg)
        return Rulepack::Result.new(status: :failure, errors: [msg], data: { installed: [] })
      end

      index = Rulepack::InstalledIndex.load_or_fresh

      backup_path = nil
      unless dry_run
        backup_path = Rulepack::InstalledIndex.backup
        Rulepack::Common.log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      all_installed = Set.new
      failed_platforms = []
      failed_packages = []
      journal = []
      begin
        platforms.each do |platform_id|
          opts = options.merge(journal: journal)
          begin
            installed, pkg_failures = install_single_platform(platform_id, index, build_index, opts)
            all_installed.merge(installed)
            Array(pkg_failures).each { |f| failed_packages << f.merge(platform: platform_id) }
          rescue StandardError => e
            failed_platforms << { platform: platform_id, error: e.message }
            Rulepack::Common.log_warn "Failed to install platform #{platform_id}: #{e.message}"
          end
        end
      rescue StandardError => e
        rollback = Rulepack::Transaction.transaction_rollback(e, backup_path, journal)
        return Rulepack::Result.new(
          status: :failure,
          errors: ["Install all failed: #{e.message}"],
          data: { installed: all_installed.to_a, failed: failed_platforms,
                  index_restored: rollback[:index_restored], backup: rollback[:backup] }
        )
      ensure
        begin
          Rulepack::InstalledIndex.cleanup_backups
        rescue StandardError => e
          # Best-effort cleanup: never let the cleanup failure (or a logging
          # failure) mask the install outcome this ensure is attached to.
          begin
            Rulepack::Common.log_debug "Index backup cleanup failed: #{e.message}"
          rescue StandardError
            warn "Index backup cleanup failed: #{e.message}"
          end
        end
      end

      if dry_run
        Rulepack::Common.log "\n[DRY-RUN] Index write skipped"
      else
        Rulepack::InstalledIndex.save(index)
        Rulepack::Common.log "\n📝 Index written: #{Rulepack::Common.paths.index_yaml_path}"
      end

      status = failed_platforms.empty? && failed_packages.empty? ? :success : :partial
      messages = install_all_messages(all_installed, failed_platforms, dry_run)
      messages.concat(failed_packages.map { |f| "   ⚠ #{f[:platform]}: #{f[:message]}" }) unless failed_packages.empty?
      Rulepack::Result.new(
        status: status,
        data: {
          installed: all_installed.to_a,
          failed: failed_platforms,
          failed_packages: failed_packages,
          platforms: platforms,
          dry_run: dry_run
        },
        messages: messages
      )
    end

    # ─── Install helpers ─────────────────────────────────────────────────────────

    def install_single_platform(platform_id, index, build_index, options)
      Rulepack::Common.log "\n📦 Platform: #{platform_id}"
      ctx = InstallContext.new(
        index: index, build_index: build_index, platform_id: platform_id,
        dry_run: options.fetch(:dry_run, false), force_mode: options.fetch(:force_mode, false),
        needed_mode: options.fetch(:needed_mode, false), collision_strategy: options.fetch(:collision_strategy, 'interactive'), rules_to: options[:rules_to],
        select_list: options.fetch(:select_list, nil), quiet: true,
        project_root: options[:project_arg] ? Pathname.new(options[:project_arg]).expand_path : nil,
        installed_this_run: [],
        journal: options.fetch(:journal, []),
        failures: [],
        locked_mode: options.fetch(:locked_mode, false),
        lockfile: options[:lockfile]
      )
      installed = InstallExecute.install_platform(ctx)
      [installed, ctx.failures]
    rescue StandardError => e
      Rulepack::Common.log_warn "Failed to install platform #{platform_id}: #{e.message}"
      raise e
    end

    # ─── Platform check ──────────────────────────────────────────────────────────

    def check_platform(platform_id, project_arg: nil)
      InstallExecute.check_platform(platform_id, project_arg: project_arg)
    end

    # ─── CLI dispatch ────────────────────────────────────────────────────────────

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
      target_arg       = options[:target]
      package_arg      = options[:package_name]
      project_arg      = options[:project_path]
      dry_run          = options[:dry_run]
      check_mode       = options[:check_mode]
      force_mode       = options[:force]
      verbose_mode     = options[:verbose]
      needed_mode      = options[:needed]
      select_list      = options[:select]
      collision_strategy = options[:on_collision] || 'interactive'
      rules_to         = options[:rules_to]
      targets_mode     = options[:targets_mode]
      locked_mode      = options.fetch(:locked, false)
      lockfile         = locked_mode ? (options.fetch(:lockfile, nil) || Rulepack::Lockfile.new) : nil

      Rulepack::Logging.log_level = verbose_mode ? :debug : Rulepack::Config.log_level

      build_idx = nil

      # ── Resolve target package ─────────────────────────────────────────────────
      target_package = nil
      if package_arg
        build_idx = ensure_build_index
        unless build_idx && build_idx[:packages] && (build_idx[:packages].key?(package_arg) || build_idx[:packages].key?(package_arg.to_sym))
          return Rulepack::Result.new(status: :failure, errors: ["Package '#{package_arg}' not found in build index."])
        end
        target_package = build_idx[:packages].keys.find { |k| k.to_s == package_arg }.to_s
      end

      # ── Targets mode ──────────────────────────────────────────────────────────
      if targets_mode
        unless target_package
          return Rulepack::Result.new(status: :failure, errors: ["--targets requires a package name."])
        end
        build_idx ||= ensure_build_index
        show_package_targets(build_idx, target_package)
        return Rulepack::Result.new(status: :success, data: { package: target_package })
      end

      # ── Target required ────────────────────────────────────────────────────────
      if (target_arg.nil? || target_arg.empty?) && Rulepack::Common.ui.interactive?
        target_arg = options[:target] = Rulepack::Common.ui.ask("Please specify target platform(s) (e.g., opencode, all):")
      end

      unless target_arg && !target_arg.empty?
        return Rulepack::Result.new(status: :failure, errors: ["Please specify target platform(s) with --target <platform> (or --target all)."])
      end

      # ── Check mode ─────────────────────────────────────────────────────────────
      if check_mode
        return check_platform(target_arg, project_arg: project_arg)
      end

      # ── Resolve target list ────────────────────────────────────────────────────
      build_idx ||= ensure_build_index
      registry = Rulepack::Common.load_platform_registry
      targets_to_install = resolve_targets(target_arg, target_package, build_idx, registry, project_arg)

      if targets_to_install.empty?
        return Rulepack::Result.new(status: :failure, errors: ["No target platforms matched."])
      end

      # ── Dispatch ───────────────────────────────────────────────────────────────
      if target_arg.downcase == 'all' && !target_package
        return install_all(
          dry_run: dry_run, force_mode: force_mode, needed_mode: needed_mode,
          verbose_mode: verbose_mode, select_list: select_list,
          project_arg: project_arg, collision_strategy: collision_strategy, rules_to: rules_to,
          locked_mode: locked_mode, lockfile: lockfile
        )
      end

      all_installed = []
      failed = []
      saw_failure = false
      saw_partial = false
      targets_to_install.each do |pkg_platform|
        if target_package
          Rulepack::Emitter.emit(:progress, message: "\u{1f4e6} Installing #{target_package} \u{2192} #{pkg_platform}")
        else
          Rulepack::Emitter.emit(:progress, message: "\u{1f4e6} Installing all packages \u{2192} #{pkg_platform}")
        end
        result = run(pkg_platform,
                     { dry_run: dry_run, force_mode: force_mode, needed_mode: needed_mode,
                       verbose_mode: verbose_mode, select_list: select_list,
                       project_arg: project_arg, specific_package: target_package,
                       rules_to: rules_to, collision_strategy: collision_strategy,
                       locked_mode: locked_mode, lockfile: lockfile })
        if result.success?
          all_installed.concat(result.data[:installed] || [])
        elsif result.partial?
          # Skipped packages (downgrade, collision-ignore, missing artifact…)
          # keep the run honest without escalating to a hard failure.
          saw_partial = true
          all_installed.concat(result.data[:installed] || [])
          Array(result.data[:failed_packages]).each { |f| failed << "⚠ #{f[:message]}" }
        else
          saw_failure = true
          failed.concat(result.errors)
          Array(result.data[:failed_packages]).each { |f| failed << f[:message] }
        end
      end

      status = saw_failure ? :failure : saw_partial ? :partial : :success
      Rulepack::Result.new(
        status: status,
        data: {
          installed: all_installed.uniq,
          failed: failed,
          targets: targets_to_install,
          dry_run: dry_run
        },
        messages: install_messages(targets_to_install.join(','), all_installed.uniq, dry_run) + failed.map { |e| "Error: #{e}" }
      )
    end

    def ensure_build_index
      Rulepack::BuildIndex.load_or_nil
    end

    def resolve_targets(target_arg, target_package, build_idx, registry, project_arg)
      targets = []
      if target_arg.downcase == 'all'
        if target_package
          pkgdata = build_idx[:packages][target_package.to_sym]
          targets = (pkgdata[:targets] || []).map { |t| t[:platform] }
        else
          targets = registry.keys.select { |p| registry[p][:scope] == 'user' || !registry[p].key?(:scope) }
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

    def show_package_targets(build_idx, target_package)
      pkg_data = build_idx[:packages][target_package.to_sym]
      targets = pkg_data[:targets] || []
      available = pkg_data[:available_targets] || []

      Rulepack::Emitter.emit(:info, message: "\u{1f4e6} #{target_package} (#{Rulepack::Common.format_version(pkg_data[:epoch] || 0, pkg_data[:pkgver], pkg_data[:pkgrel] || 1)})")
      Rulepack::Emitter.emit(:info, message: '')
      Rulepack::Emitter.emit(:info, message: "Targets (#{targets.size}):")
      targets.each do |t|
        status = available.include?(t[:platform]) ? "\u{2713} built" : "\u{2717} not built"
        Rulepack::Emitter.emit(:info, message: "  \u{2022} #{t[:platform]} (#{t[:format]}, #{t[:output]}) [#{status}]")
      end
      Rulepack::Emitter.emit(:info, message: '')
      Rulepack::Emitter.emit(:info, message: 'Installed on:')
      index = Rulepack::InstalledIndex.load_or_fresh
      pkg_idx = index[:packages]&.[](target_package.to_sym) || index[:packages]&.[](target_package.to_s) || {}
      installed = pkg_idx[:installed] || []
      if installed.empty?
        Rulepack::Emitter.emit(:info, message: '  (none)')
      else
        installed.each do |rec|
          Rulepack::Emitter.emit(:info, message: "  \u{2022} #{rec[:platform]} (#{Rulepack::Common.format_version(rec[:epoch] || 0, rec[:version], rec[:pkgrel] || 1)}) \u{2014} #{rec[:output]}")
        end
      end
    end

    # ─── Message helpers ─────────────────────────────────────────────────────────

    def install_messages(platform_id, installed, dry_run)
      msgs = []
      msgs << "\n📝 Index written" unless dry_run
      msgs << "\n✅ Install #{dry_run ? 'preview' : 'complete'} for #{platform_id}. #{installed.size} package(s) affected:"
      installed.each { |p| msgs << "   • #{p}" }
      msgs << ''
      msgs
    end

    def install_all_messages(installed, failed, dry_run)
      msgs = []
      msgs << "\n[DRY-RUN] Index write skipped" if dry_run
      msgs << "\n✅ Install #{dry_run ? 'preview' : 'complete'}. #{installed.size} package(s) affected:"
      installed.each { |p| msgs << "   • #{p}" }
      failed.each { |f| msgs << "   ⚠ #{f[:platform]}: #{f[:error]}" }
      msgs << ''
      msgs
    end
  end
end
