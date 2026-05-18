# frozen_string_literal: true

# Installer library (modular API)
# Decomposed into focused modules under lib/rulepack/lib/ for high cohesion.

require 'English'
require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require 'json'
require 'set'
require_relative 'common'
require_relative 'lib/transaction'
require_relative 'lib/install_handlers'
require_relative 'lib/skill_bundle'
require_relative 'aggregate'

module Rulepack
  module Install
    module_function

    # Context object to hold installation state and reduce argument counts
    InstallContext = Struct.new(
      :index, :build_index, :platform_id, :platform_cfg, :base_path, :project_root,
      :dry_run, :force_mode, :needed_mode, :collision_strategy, :quiet,
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

      Rulepack::Common.log_level = verbose_mode ? :debug : Rulepack::Config.log_level

      return check_platform(platform_id, project_arg: project_arg) if check_mode

      unless Rulepack::Common::BUILD_INDEX_PATH.exist?
        Rulepack::Common.log_error(
          "Build index not found at #{Rulepack::Common::BUILD_INDEX_PATH}. " \
          'Run `ruby lib/rulepack/build.rb` first.'
        )
        exit 1
      end

      build_index = Rulepack::Common.load_yaml(Rulepack::Common::BUILD_INDEX_PATH)
      index = if Rulepack::Common::INDEX_YAML_PATH.exist?
                Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
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

      ctx = nil
      begin
        ctx = InstallContext.new(
          index: index, build_index: build_index, platform_id: platform_id,
          dry_run: dry_run, force_mode: force_mode, needed_mode: needed_mode,
          collision_strategy: collision_strategy, select_list: select_list,
          project_root: project_arg ? Pathname.new(project_arg).expand_path : nil,
          installed_this_run: [],
          journal: []
        )
        install_platform(ctx, specific_package: specific_package)

        # Write index after successful install
        if dry_run
          Rulepack::Common.log '[DRY-RUN] Index write skipped'
          puts "\n[DRY-RUN] Index write skipped"
        else
          index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          Rulepack::Common.write_yaml_atomic(Rulepack::Common::INDEX_YAML_PATH, index)
          Rulepack::Common.log "📝 Index written: #{Rulepack::Common::INDEX_YAML_PATH}"
          puts "\n📝 Index written: #{Rulepack::Common::INDEX_YAML_PATH}"
        end
      rescue StandardError => e
        Rulepack::Transaction.transaction_rollback(e, backup_path, ctx&.journal)
        exit 1
      ensure
        begin
          Rulepack::Common.cleanup_backups
        rescue StandardError
          nil
        end
      end
    end

    # ─── Install all platforms ───────────────────────────────────────────────────

    def install_all(options = {})
      dry_run = options.fetch(:dry_run, false)
      verbose_mode = options.fetch(:verbose_mode, false)

      Rulepack::Common.log_level = verbose_mode ? :debug : Rulepack::Config.log_level

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

      Rulepack::Common.log "🚀 Installing ALL platforms (#{platforms.size} platforms)#{' (dry-run)' if dry_run}"
      puts "🚀 Installing ALL platforms (#{platforms.size} platforms)#{' (dry-run)' if dry_run}"

      unless Rulepack::Common::BUILD_INDEX_PATH.exist?
        Rulepack::Common.log_error(
          "Build index not found at #{Rulepack::Common::BUILD_INDEX_PATH}. " \
          'Run `ruby lib/rulepack/build.rb` first.'
        )
        exit 1
      end

      index = load_master_index
      build_index = Rulepack::Common.load_yaml(Rulepack::Common::BUILD_INDEX_PATH)

      backup_path = nil
      unless dry_run
        backup_path = Rulepack::Common.backup_index
        Rulepack::Common.log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      all_installed = Set.new
      journal = []
      begin
        platforms.each do |platform_id|
          opts = options.merge(journal: journal)
          all_installed.merge(install_single_platform(platform_id, index, build_index, opts))
        end
      rescue StandardError => e
        Rulepack::Transaction.transaction_rollback(e, backup_path, journal)
        exit 1
      ensure
        begin
          Rulepack::Common.cleanup_backups
        rescue StandardError
          nil
        end
      end

      if dry_run
        Rulepack::Common.log "\n[DRY-RUN] Index write skipped"
        puts "\n[DRY-RUN] Index write skipped"
      else
        index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        Rulepack::Common.write_yaml_atomic(Rulepack::Common::INDEX_YAML_PATH, index)
        Rulepack::Common.log "\n📝 Index written: #{Rulepack::Common::INDEX_YAML_PATH}"
        puts "\n📝 Index written: #{Rulepack::Common::INDEX_YAML_PATH}"
      end

      puts "\n✅ Install #{dry_run ? 'preview' : 'complete'}. #{all_installed.size} package(s) affected:"
      all_installed.each { |p| puts "   • #{p}" }
      puts ''
    end

    # ─── Install helpers (extracted from install_all) ────────────────────────────

    def load_master_index
      index = if Rulepack::Common::INDEX_YAML_PATH.exist?
                Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
              else
                { version: 3.0, packages: {} }
              end
      index[:packages] ||= {}
      (index[:packages] || {}).each_value { |pkg_idx| Rulepack::Common.migrate_installed_records(pkg_idx) }
      index
    end

    def install_single_platform(platform_id, index, build_index, options)
      Rulepack::Common.log "\n📦 Platform: #{platform_id}"
      ctx = InstallContext.new(
        index: index, build_index: build_index, platform_id: platform_id,
        dry_run: options.fetch(:dry_run, false), force_mode: options.fetch(:force_mode, false),
        needed_mode: options.fetch(:needed_mode, false), collision_strategy: options.fetch(:collision_strategy, 'stop'),
        select_list: options.fetch(:select_list, nil), quiet: true,
        project_root: options[:project_arg] ? Pathname.new(options[:project_arg]).expand_path : nil,
        installed_this_run: [],
        journal: options.fetch(:journal, [])
      )
      install_platform(ctx)
    rescue StandardError => e
      Rulepack::Common.log_warn "Failed to install platform #{platform_id}: #{e.message}"
      puts "  ⚠️  #{platform_id}: #{e.message}"
      raise e
    end

    # ─── Install a single platform ───────────────────────────────────────────────
    # Returns Set of installed package names for this run.

    def install_platform(ctx, specific_package: nil)
      ctx.platform_id = ctx.platform_id.to_s
      ctx.platform_cfg = platform_cfg_for(ctx.platform_id)
      warn_prerequisites(ctx.platform_id, ctx.platform_cfg, ctx.quiet)

      ctx.base_path = resolve_install_base_path(ctx.platform_cfg, ctx.project_root)
      Rulepack::Common.log "📁 Base path: #{ctx.base_path}" unless ctx.quiet
      Rulepack::Common.log "  Platform type: #{ctx.platform_cfg[:type]}" unless ctx.quiet

      ctx.build_index[:packages].each do |pkgname, pkgdata|
        next if specific_package && pkgname.to_s != specific_package.to_s

        targets = filter_targets_for_platform(pkgdata, ctx.platform_id)
        if targets.empty?
          Rulepack::Common.log "  ⊘ package '#{pkgname}': no target for #{ctx.platform_id}, skipping" unless ctx.quiet
          next
        end

        next unless should_install_or_upgrade?(pkgname, pkgdata, ctx)

        ensure_package_in_index(ctx.index, pkgname, pkgdata)

        targets.each do |target|
          install_single_target(pkgname, pkgdata, target, ctx)
        end
      end

      if ctx.platform_cfg[:type] == 'skill' && !ctx.dry_run
        aggregate_vendor_skills(ctx.platform_id, ctx.platform_cfg, ctx.base_path, ctx)
      end

      ctx.installed_this_run
    end

    # ─── Check platform ──────────────────────────────────────────────────────────

    def check_platform(platform_id, project_arg: nil)
      platform_id = platform_id.to_s
      Rulepack::Common.log "🔍 Checking installed state for platform: #{platform_id}"
      puts "🔍 Checking installed state for platform: #{platform_id}"

      unless Rulepack::Common::INDEX_YAML_PATH.exist?
        Rulepack::Common.log_error 'index.yaml not found. Run build first.'
        raise 'index.yaml not found'
      end

      index = Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
      platform_cfg = platform_cfg_for(platform_id)
      warn_prerequisites(platform_id, platform_cfg, false)

      base_path = resolve_install_base_path(platform_cfg, project_arg)

      # Skill-type platforms: check vendor skill file only
      check_vendor_skill_present(platform_cfg, base_path) if platform_cfg[:type] == 'skill'

      errors = []
      index[:packages].each do |pkgname, pkgdata|
        inst = pkgdata[:installed].find { |i| i[:platform] == platform_id }
        next unless inst

        error = verify_package_on_disk(pkgname, pkgdata, inst, platform_id, platform_cfg, base_path)
        errors << error if error
      end

      report_check_results(errors)
    end

    # ─── Platform install/check helpers ────────────────────────────────────────────

    def warn_prerequisites(platform_id, platform_cfg, quiet)
      missing = Rulepack::Common.check_prerequisites(platform_cfg)
      return if missing.empty?

      Rulepack::Common.log_warn "Platform #{platform_id} may require: #{missing.join(', ')}" unless quiet
      puts "  ⚠️  Platform #{platform_id} may require: #{missing.join(', ')}" unless quiet
    end

    def resolve_install_base_path(platform_cfg, project_arg)
      project_root = Rulepack::Common.project_root_for(platform_cfg, project_arg)
      project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
    end

    def filter_targets_for_platform(pkgdata, platform_id)
      pkgdata[:targets]&.select { |t| t[:platform] == platform_id } || []
    end

    def should_install_or_upgrade?(pkgname, pkgdata, ctx)
      pkg_index = ctx.index[:packages][pkgname] || { installed: [] }
      existing_records = (pkg_index[:installed] || []).select { |r| r[:platform] == ctx.platform_id }
      return true if existing_records.empty?

      existing = existing_records.first
      cmp = Rulepack::Common.compare_versions(
        pkgdata[:pkgver], existing[:version],
        epoch1: pkgdata[:epoch] || 0, epoch2: existing[:epoch] || 0,
        pkgrel1: pkgdata[:pkgrel] || 1, pkgrel2: existing[:pkgrel] || 1
      )

      case cmp
      when 0
        if ctx.needed_mode
          unless ctx.quiet
            ver = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
            Rulepack::Common.log "  ↺ #{pkgname} #{ver} already installed (--needed)"
          end
          return false
        end

        targets = Array(pkgdata[:targets])
        has_skill_bundle = targets.any? { |t| t[:platform] == ctx.platform_id && t[:format] == 'skill-bundle' }
        if ctx.select_list && has_skill_bundle
          ver = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log "  🔄 Re-installing #{pkgname} #{ver} (--select specified)"
          uninstall_single_package_from_index!(ctx.index, pkgname, ctx.platform_id, project_root: ctx.project_root) unless ctx.dry_run
          true
        elsif !ctx.select_list && has_skill_bundle
          # Reinstall skill-bundle to restore any sub-skills previously removed via --select
          ver = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log "  🔄 Restoring #{pkgname} #{ver} all sub-skills"
          uninstall_single_package_from_index!(ctx.index, pkgname, ctx.platform_id, project_root: ctx.project_root) unless ctx.dry_run
          true
        else
          unless ctx.quiet
            ver = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
            Rulepack::Common.log "  ↺ #{pkgname} already installed (#{ver})"
          end
          false
        end
      when 1
        unless ctx.quiet
          old_v = Rulepack::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])
          new_v = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log "  🔄 Upgrading #{pkgname} #{old_v} → #{new_v}"
        end
        uninstall_single_package_from_index!(ctx.index, pkgname, ctx.platform_id, project_root: ctx.project_root) unless ctx.dry_run
        true
      else
        handle_downgrade(pkgname, pkgdata, existing, ctx)
      end
    end

    def handle_downgrade(pkgname, pkgdata, existing, ctx)
      if ctx.force_mode
        unless ctx.quiet
          old_v = Rulepack::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])
          new_v = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log_warn "Downgrade forced for #{pkgname}: #{old_v} → #{new_v}"
        end
        uninstall_single_package_from_index!(ctx.index, pkgname, ctx.platform_id, project_root: ctx.project_root) unless ctx.dry_run
        true
      else
        unless ctx.quiet
          old_v = Rulepack::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])
          new_v = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log_error "Downgrade detected for #{pkgname}: installed #{old_v}, candidate #{new_v}"
        end
        Rulepack::Common.log_error 'Use --force to allow downgrade' unless ctx.quiet
        false
      end
    end

    def ensure_package_in_index(index, pkgname, pkgdata)
      pkg_index = index[:packages][pkgname] ||= {}
      pkg_index[:installed] ||= []
      pkg_index.merge!(pkgdata.reject { |k, _| k == :installed })
    end

    def check_vendor_skill_present(platform_cfg, base_path)
      vendor_path = base_path.join(platform_cfg[:skill_file])
      unless vendor_path.exist?
        Rulepack::Common.log_error "Vendor skill missing: #{vendor_path}"
        puts "  ❌ Vendor skill missing: #{vendor_path}"
        raise 'Vendor skill missing'
      end
      Rulepack::Common.log "  ✓ Vendor skill present: #{vendor_path}"
      puts '  ✅ Vendor skill present and readable'
    end

    def verify_package_on_disk(pkgname, pkgdata, inst, platform_id, platform_cfg, base_path)
      expected_output = inst[:output]
      expected_checksum = inst[:checksum]
      target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
      format_type = target ? target[:format] : 'directory'

      # For skill-format packages on skill-type platforms: check build artifact
      if format_type == 'skill' && platform_cfg[:type] == 'skill'
        build_artifact = Rulepack::Common::BUILD_DIR.join(platform_id, pkgname.to_s, expected_output)
        return "Build artifact missing: #{pkgname} (#{build_artifact})" unless build_artifact.exist?

        actual_sha = Digest::SHA256.hexdigest(build_artifact.read)
        return nil if actual_sha == expected_checksum

        return "Build artifact checksum mismatch: #{pkgname}"
      end

      installed_path = Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)

      if format_type == 'skill-bundle'
        verify_skill_bundle(installed_path, pkgname)
      else
        verify_single_file(installed_path, expected_checksum, pkgname, expected_output)
      end
    end

    def verify_skill_bundle(installed_path, pkgname)
      return "Skill-bundle directory missing: #{installed_path}" unless installed_path.directory?

      manifest_path = installed_path.join('manifest.json')
      return "#{pkgname}: no manifest" unless manifest_path.exist?

      begin
        manifest = JSON.parse(manifest_path.read)
        mismatches = []
        total_files = 0
        manifest['sub_skills'].each do |sub_skill|
          sub_skill['files'].each do |rel_path, expected_sha|
            total_files += 1
            file_path = installed_path.join(rel_path)
            if file_path.exist?
              actual_sha = Digest::SHA256.hexdigest(file_path.read)
              mismatches << "checksum mismatch: #{rel_path}" unless actual_sha == expected_sha
            else
              mismatches << "missing: #{rel_path}"
            end
          end
        end

        if mismatches.empty?
          count = manifest['sub_skills'].size
          Rulepack::Common.log "  ✓ Bundle manifest: #{count} sub-skill(s), #{total_files} file(s)"
          nil
        else
          Rulepack::Common.log_warn "Skill-bundle manifest: #{mismatches.size} issue(s)"
          mismatches.each { |m| Rulepack::Common.log_warn "    • #{m}" }
          mismatches.map { |m| "#{pkgname}: #{m}" }.join('; ')
        end
      rescue StandardError => e
        Rulepack::Common.log_warn "Failed to read skill-bundle manifest: #{e.message}"
        "#{pkgname}: manifest unreadable"
      end
    end

    def verify_single_file(installed_path, expected_checksum, pkgname, expected_output)
      return "Missing: #{pkgname} (#{expected_output}) at #{installed_path}" unless installed_path.exist?

      return nil if Rulepack::Common.verify_checksum(installed_path, expected_checksum, pkgname)

      "Checksum mismatch: #{pkgname} (#{expected_output})"
    end

    def report_check_results(errors)
      if errors.empty?
        Rulepack::Common.log '✅ All installed packages are valid'
        puts "\n✅ All installed packages are valid"
        exit 0
      else
        Rulepack::Common.log_error "#{errors.size} error(s) found"
        puts "\n❌ #{errors.size} error(s) found:"
        errors.each { |e| puts "  • #{e}" }
        exit 1
      end
    end

    # ─── Install a single target ─────────────────────────────────────────────────

    def install_single_target(pkgname, pkgdata, target, ctx)
      format = target[:format]

      case format
      when 'skill-bundle'
        Rulepack::SkillBundle.install_skill_bundle(pkgname, pkgdata, target, ctx, self)
      else
        install_file_or_skill(pkgname, pkgdata, target, ctx)
      end
    end

    # ─── Single-file install (directory/import/skill platform types) ───────────────

    def install_file_or_skill(pkgname, pkgdata, target, ctx)
      dry_run = ctx.dry_run
      quiet = ctx.quiet
      platform_cfg = ctx.platform_cfg
      base_path = ctx.base_path
      platform_id = ctx.platform_id
      index = ctx.index
      installed_this_run = ctx.installed_this_run
      output = target[:output]
      built_path = Rulepack::Common::BUILD_DIR.join(platform_id, pkgname.to_s, output)
      unless built_path.exist?
        Rulepack::Common.log_error "Built artifact missing: #{built_path}. Run `ruby lib/rulepack/build.rb` first."
        return
      end

      content = built_path.read
      content_sha256 = Digest::SHA256.hexdigest(content)

      # Skill-type platforms: record only, aggregation handles file install
      if platform_cfg[:type] == 'skill'
        record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256) unless dry_run
        Rulepack::Common.log "  ✓ Installed: #{pkgname}" unless quiet
        installed_this_run << pkgname
        return
      end

      install_cfg = target[:install] || {}
      format = target[:format]
      default_install_cfg = if %w[skill skill-bundle].include?(format)
                              platform_cfg[:skill_install]
                            else
                              platform_cfg[:rule_install]
                            end
      install_type = install_cfg[:type] || default_install_cfg&.[](:type) || 'copy'
      install_path = Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)

      install_path.parent.mkpath unless dry_run

      Rulepack::Common.log "  ⤷ #{pkgname} (#{output}) → #{install_path} [#{install_type}]" unless quiet
      Rulepack::InstallHandlers.perform_file_install(built_path, install_path, content, content_sha256, install_type, platform_cfg, output,
                                                     pkgname, ctx)

      record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256) unless dry_run
      Rulepack::Common.log "  ✓ Installed: #{pkgname}" unless quiet
      installed_this_run << pkgname
    end

    # ─── Common: record installation in index ──────────────────────────────────────

    def record_installation(index, pkgname, platform_id, pkgdata, output, checksum)
      pkg_index = index[:packages][pkgname] || { installed: [] }
      pkg_index[:installed] ||= []
      record = {
        platform: platform_id,
        version: pkgdata[:pkgver],
        pkgrel: pkgdata[:pkgrel],
        epoch: pkgdata[:epoch],
        output: output,
        checksum: checksum,
        installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      }
      if output == '.'
        pkg_index[:installed].reject! { |r| r[:platform] == platform_id }
      else
        pkg_index[:installed].reject! { |r| r[:platform] == platform_id && r[:output] == output }
      end
      pkg_index[:installed] << record
    end

    # ─── Vendor skill aggregation ────────────────────────────────────────────────

    def aggregate_vendor_skills(platform_id, platform_cfg, base_path, ctx)
      collision_strategy = ctx.collision_strategy || 'stop'
      Rulepack::Common.log "  🧱 Aggregating vendor skills for #{platform_id}..."
      puts "\n  🧱 Aggregating vendor skills for #{platform_id}..."
      agg_ok = begin
                 Rulepack::Aggregate.run(target: platform_id)
                 true
               rescue StandardError => e
                 Rulepack::Common.log_error "Aggregation error: #{e.message}"
                 false
               end
      if agg_ok
        Rulepack::Common.log '    ✓ Vendor skill aggregated'
        puts '    ✓ Vendor skill aggregated'
        vendor_file = Rulepack::Common::BUILD_DIR.join(platform_id, 'skills', 'vendor',
                                                       "#{platform_id}.md")
        if vendor_file.exist?
          install_path = base_path.join(platform_cfg[:skill_file])
          install_path.parent.mkpath

          if install_path.exist?
            case collision_strategy
            when 'append'
              backup_path = Rulepack::Common.backup_file(install_path)
              Rulepack::Transaction.record_journal(ctx, { action: :modify_file, path: install_path, backup: backup_path })
              result = Rulepack::Common.update_marked_content(install_path, "#{platform_id}_vendor", vendor_file.read)
              Rulepack::Common.log "  ✓ #{result.capitalize} vendor skill to #{install_path} (with backup)"
              puts "  ✓ #{result.capitalize} vendor skill to #{install_path} (with backup)"
            when 'overwrite'
              backup_path = Rulepack::Common.backup_file(install_path)
              Rulepack::Transaction.record_journal(ctx, { action: :replace_file, path: install_path, backup: backup_path })
              FileUtils.cp(vendor_file, install_path)
              Rulepack::Common.log "  ✓ Overwrote vendor skill to #{install_path} (with backup)"
              puts "  ✓ Overwrote vendor skill to #{install_path} (with backup)"
            when 'ignore'
              Rulepack::Common.log "  ⚠ Collision: #{install_path} exists, skipping vendor skill install"
              puts "  ⚠ Collision: #{install_path} exists, skipping"
            else # stop
              Rulepack::Common.log_error "Collision detected: #{install_path} exists. Use --on-collision to proceed."
              puts "  ❌ Collision: #{install_path} exists. Use --on-collision to proceed."
              raise "Collision at #{install_path}"
            end
          else
            Rulepack::Transaction.record_journal(ctx, { action: :create_file, path: install_path })
            FileUtils.cp(vendor_file, install_path)
            Rulepack::Common.log "  ✓ Installed vendor skill to #{install_path}"
            puts "  ✓ Installed vendor skill to #{install_path}"
          end
        else
          Rulepack::Common.log_error "Vendor skill not generated: #{vendor_file}"
        end
      else
        Rulepack::Common.log_error 'Vendor skill aggregation failed'
      end
    end

    # ─── Helpers ────────────────────────────────────────────────────────────────

    def uninstall_single_package_from_index!(index, pkgname, platform_id, project_root: nil)
      Rulepack::Common.uninstall_packages(index, platform_id, dry_run: false,
                                                              project_root: project_root,
                                                              specific_packages: [pkgname]).include?(pkgname)
    end

    def platform_cfg_for(platform_id)
      registry = Rulepack::Common.load_platform_registry
      Rulepack::Common.platform_config(platform_id, registry)
    rescue StandardError => e
      warn "PLATFORM_CFG_ERROR: #{e.message}"
      Rulepack::Common.log_error e.message
      exit 1
    end

    def project_root_for(_platform_id, platform_cfg, project_arg)
      Rulepack::Common.project_root_for(platform_cfg, project_arg)
    end
  end
end
