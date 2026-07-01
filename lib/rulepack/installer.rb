# frozen_string_literal: true

# Installer library — thin orchestrator
#
# Decision-making lives in install_plan.rb (InstallPlan).
# Execution (symlink/copy/inject/append, verification, vendor aggregation) lives in install_execute.rb (InstallExecute).
# This file retains only: run, install_all, load_master_index, install_single_platform,
# dispatch, and stateless CLI helpers.

require 'English'
require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require 'json'
require 'set'
require_relative 'common'
require_relative 'lib/transaction'
require_relative 'install_plan'
require_relative 'install_execute'

module Rulepack
  module Install
    module_function

    # Context object to hold installation state and reduce argument counts
    InstallContext = Struct.new(
      :index, :build_index, :platform_id, :platform_cfg, :base_path, :project_root,
      :dry_run, :force_mode, :needed_mode, :collision_strategy, :rules_to, :quiet,
      :select_list, :installed_this_run, :journal,
      keyword_init: true
    )

    # ─── Main entry point ────────────────────────────────────────────────────────

    def run(platform_id, options = {})
      dry_run = options.fetch(:dry_run, false)
      check_mode = options.fetch(:check_mode, false)
      force_mode = options.fetch(:force_mode, false)
      needed_mode = options.fetch(:needed_mode, false)
      verbose_mode = options.fetch(:verbose_mode, false)
      select_list = options.fetch(:select_list, nil)
      project_arg = options.fetch(:project_arg, nil)
      specific_package = options.fetch(:specific_package, nil)
      collision_strategy = options.fetch(:collision_strategy, 'stop')
      rules_to = options.fetch(:rules_to, nil)

      Rulepack::Logging.log_level = verbose_mode ? :debug : Rulepack::Config.log_level

      return check_platform(platform_id, project_arg: project_arg) if check_mode

      unless Rulepack::Common::BUILD_INDEX_PATH.exist?
        msg = "Build index not found at #{Rulepack::Common::BUILD_INDEX_PATH}. Run `ruby lib/rulepack/build.rb` first."
        Rulepack::Common.log_error(msg)
        return Rulepack::Result.new(status: :failure, errors: [msg])
      end

      build_index = Rulepack::Common.load_yaml(Rulepack::Common::BUILD_INDEX_PATH)
      index = if Rulepack::Common.index_yaml_path.exist?
                Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
              else
                { version: 3.0, packages: {} }
              end
      index[:packages] ||= {}
      (index[:packages] || {}).each_value { |pkg_idx| Rulepack::Common.migrate_installed_records(pkg_idx) }

      backup_path = nil
      unless dry_run
        backup_path = Rulepack::Common.backup_index
        Rulepack::Common.log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      installed = []
      ctx = nil
      begin
        ctx = InstallContext.new(
          index: index, build_index: build_index, platform_id: platform_id,
          dry_run: dry_run, force_mode: force_mode, needed_mode: needed_mode,
          collision_strategy: collision_strategy, rules_to: rules_to, select_list: select_list,
          project_root: project_arg ? Pathname.new(project_arg).expand_path : nil,
          installed_this_run: [],
          journal: []
        )
        installed = InstallExecute.install_platform(ctx, specific_package: specific_package).to_a

        if dry_run
          Rulepack::Common.log '[DRY-RUN] Index write skipped'
        else
          index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          Rulepack::Common.write_yaml_atomic(Rulepack::Common.index_yaml_path, index)
          Rulepack::Common.log "📝 Index written: #{Rulepack::Common.index_yaml_path}"
        end
      rescue StandardError => e
        Rulepack::Transaction.transaction_rollback(e, backup_path, ctx&.journal)
        return Rulepack::Result.new(
          status: :failure,
          errors: ["Install failed for #{platform_id}: #{e.message}"],
          data: { platform_id: platform_id, installed: installed }
        )
      ensure
        begin
          Rulepack::Common.cleanup_backups
        rescue StandardError
          nil
        end
      end

      status = installed.empty? && specific_package ? :success : (installed.empty? ? :success : :success)
      Rulepack::Result.new(
        status: status,
        data: {
          platform_id: platform_id,
          installed: installed,
          dry_run: dry_run
        },
        messages: install_messages(platform_id, installed, dry_run)
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

      unless Rulepack::Common::BUILD_INDEX_PATH.exist?
        msg = "Build index not found at #{Rulepack::Common::BUILD_INDEX_PATH}. Run `ruby lib/rulepack/build.rb` first."
        Rulepack::Common.log_error(msg)
        return Rulepack::Result.new(status: :failure, errors: [msg])
      end

      index = load_master_index
      build_index = Rulepack::Common.load_yaml(Rulepack::Common::BUILD_INDEX_PATH)

      backup_path = nil
      unless dry_run
        backup_path = Rulepack::Common.backup_index
        Rulepack::Common.log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      all_installed = Set.new
      failed_platforms = []
      journal = []
      begin
        platforms.each do |platform_id|
          opts = options.merge(journal: journal)
          begin
            all_installed.merge(install_single_platform(platform_id, index, build_index, opts))
          rescue StandardError => e
            failed_platforms << { platform: platform_id, error: e.message }
            Rulepack::Common.log_warn "Failed to install platform #{platform_id}: #{e.message}"
          end
        end
      rescue StandardError => e
        Rulepack::Transaction.transaction_rollback(e, backup_path, journal)
        return Rulepack::Result.new(
          status: :failure,
          errors: ["Install all failed: #{e.message}"],
          data: { installed: all_installed.to_a, failed: failed_platforms }
        )
      ensure
        begin
          Rulepack::Common.cleanup_backups
        rescue StandardError
          nil
        end
      end

      if dry_run
        Rulepack::Common.log "\n[DRY-RUN] Index write skipped"
      else
        index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        Rulepack::Common.write_yaml_atomic(Rulepack::Common.index_yaml_path, index)
        Rulepack::Common.log "\n📝 Index written: #{Rulepack::Common.index_yaml_path}"
      end

      status = failed_platforms.empty? ? :success : :partial
      Rulepack::Result.new(
        status: status,
        data: {
          installed: all_installed.to_a,
          failed: failed_platforms,
          platforms: platforms,
          dry_run: dry_run
        },
        messages: install_all_messages(all_installed, failed_platforms, dry_run)
      )
    end

    # ─── Install helpers ─────────────────────────────────────────────────────────

    def load_master_index
      index = if Rulepack::Common.index_yaml_path.exist?
                Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
              else
                { version: 3.0, packages: {} }
              end
      index[:packages] ||= {}
      # Migrate schema if needed (idempotent — safe on already-migrated data)
      Rulepack::SchemaMigration.migrate!(index)
      (index[:packages] || {}).each_value { |pkg_idx| Rulepack::Common.migrate_installed_records(pkg_idx) }
      index
    end

    def install_single_platform(platform_id, index, build_index, options)
      Rulepack::Common.log "\n📦 Platform: #{platform_id}"
      ctx = InstallContext.new(
        index: index, build_index: build_index, platform_id: platform_id,
        dry_run: options.fetch(:dry_run, false), force_mode: options.fetch(:force_mode, false),
        needed_mode: options.fetch(:needed_mode, false), collision_strategy: options.fetch(:collision_strategy, 'stop'), rules_to: options[:rules_to],
        select_list: options.fetch(:select_list, nil), quiet: true,
        project_root: options[:project_arg] ? Pathname.new(options[:project_arg]).expand_path : nil,
        installed_this_run: [],
        journal: options.fetch(:journal, [])
      )
      InstallExecute.install_platform(ctx)
    rescue StandardError => e
      Rulepack::Common.log_warn "Failed to install platform #{platform_id}: #{e.message}"
      raise e
    end

    # ─── Platform check ──────────────────────────────────────────────────────────

    def check_platform(platform_id, project_arg: nil)
      InstallExecute.check_platform(platform_id, project_arg: project_arg)
    end

    # ─── CLI dispatch ────────────────────────────────────────────────────────────

    def dispatch(options)
      target_arg       = options[:target]
      package_arg      = options[:package_name]
      project_arg      = options[:project_path]
      dry_run          = options[:dry_run]
      check_mode       = options[:check_mode]
      force_mode       = options[:force]
      verbose_mode     = options[:verbose]
      needed_mode      = options[:needed]
      select_list      = options[:select]
      collision_strategy = options[:on_collision] || 'stop'
      rules_to         = options[:rules_to]
      targets_mode     = options[:targets_mode]

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
      unless target_arg
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
          project_arg: project_arg, collision_strategy: collision_strategy, rules_to: rules_to
        )
      end

      all_installed = []
      failed = []
      targets_to_install.each do |pkg_platform|
        if target_package
          Rulepack::Common.log "\u{1f4e6} Installing #{target_package} \u{2192} #{pkg_platform}"
          puts "\u{1f4e6} Installing #{target_package} \u{2192} #{pkg_platform}"
        else
          Rulepack::Common.log "\u{1f4e6} Installing all packages \u{2192} #{pkg_platform}"
          puts "\u{1f4e6} Installing all packages \u{2192} #{pkg_platform}"
        end
        result = run(pkg_platform,
                     dry_run: dry_run, force_mode: force_mode, needed_mode: needed_mode,
                     verbose_mode: verbose_mode, select_list: select_list,
                     project_arg: project_arg, specific_package: target_package,
                     rules_to: rules_to, collision_strategy: collision_strategy)
        if result.success?
          all_installed.concat(result.data[:installed] || [])
        else
          failed.concat(result.errors)
        end
      end

      status = failed.empty? ? :success : :failure
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
      return nil unless Rulepack::Common::BUILD_INDEX_PATH.exist?
      Rulepack::Common.load_yaml(Rulepack::Common::BUILD_INDEX_PATH)
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
        cfg = registry[p.to_sym] || registry[p.to_s]
        raise "Unknown target platform '#{p}'." unless cfg
        raise "Platform '#{cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>." if cfg[:scope] == 'project' && !project_arg
      end
      targets
    end

    def show_package_targets(build_idx, target_package)
      pkg_data = build_idx[:packages][target_package.to_sym]
      targets = pkg_data[:targets] || []
      available = pkg_data[:available_targets] || []

      puts "\u{1f4e6} #{target_package} (#{Rulepack::Common.format_version(pkg_data[:epoch] || 0, pkg_data[:pkgver], pkg_data[:pkgrel] || 1)})"
      puts ''
      puts "Targets (#{targets.size}):"
      targets.each do |t|
        status = available.include?(t[:platform]) ? '\u{2713} built' : '\u{2717} not built'
        puts "  \u{2022} #{t[:platform]} (#{t[:format]}, #{t[:output]}) [#{status}]"
      end
      puts ''
      puts 'Installed on:'
      index = if Rulepack::Common.index_yaml_path.exist?
                Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
              else
                { version: 3.0, packages: {} }
              end
      pkg_idx = index[:packages]&.[](target_package.to_sym) || index[:packages]&.[](target_package.to_s) || {}
      installed = pkg_idx[:installed] || []
      if installed.empty?
        puts '  (none)'
      else
        installed.each do |rec|
          puts "  \u{2022} #{rec[:platform]} (#{Rulepack::Common.format_version(rec[:epoch] || 0, rec[:version], rec[:pkgrel] || 1)}) \u{2014} #{rec[:output]}"
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
