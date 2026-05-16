# frozen_string_literal: true

# Installer library (modular API)
# Used by install.rb (CLI) and potentially other callers.

require 'English'
require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require 'json'
require 'set'
require_relative 'common'

module Rulepack
  module Install
    module_function

    # ─── Main entry point ────────────────────────────────────────────────────────

    def run(platform_id, options = {})
      dry_run = options.fetch(:dry_run, false)
      check_mode = options.fetch(:check_mode, false)
      force_mode = options.fetch(:force_mode, false)
      verbose_mode = options.fetch(:verbose_mode, false)
      select_list = options.fetch(:select_list, nil)
      project_arg = options.fetch(:project_arg, nil)
      specific_package = options.fetch(:specific_package, nil)

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

      begin
        install_platform(index, build_index, platform_id,
                         dry_run: dry_run, force_mode: force_mode,
                         select_list: select_list, project_arg: project_arg,
                         specific_package: specific_package)

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
        if backup_path && Rulepack::Common.restore_index(backup_path)
          Rulepack::Common.log_error "Transaction failed (#{e.message}). Index restored from backup."
          puts "  ❌ Transaction failed. Index restored from backup: #{backup_path.basename}"
        else
          Rulepack::Common.log_error "Transaction failed (#{e.message}). No backup available."
          puts "  ❌ Transaction failed: #{e.message}"
        end
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
      platforms = registry.keys

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
      begin
        platforms.each do |platform_id|
          all_installed.merge(install_single_platform(platform_id, index, build_index, options))
        end
      rescue StandardError => e
        transaction_rollback(e, backup_path)
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
      install_platform(index, build_index, platform_id,
                       dry_run: options.fetch(:dry_run, false),
                       force_mode: options.fetch(:force_mode, false),
                       select_list: options.fetch(:select_list, nil),
                       project_arg: options.fetch(:project_arg, nil),
                       quiet: true)
    rescue StandardError => e
      Rulepack::Common.log_warn "Failed to install platform #{platform_id}: #{e.message}"
      puts "  ⚠️  #{platform_id}: #{e.message}"
      Set.new
    end

    def transaction_rollback(error, backup_path)
      if backup_path && Rulepack::Common.restore_index(backup_path)
        Rulepack::Common.log_error "Transaction failed (#{error.message}). Index restored from backup."
        puts "\n❌ Transaction failed. Index restored from backup: #{backup_path.basename}"
      else
        Rulepack::Common.log_error "Transaction failed (#{error.message}). No backup available."
        puts "\n❌ Transaction failed: #{error.message}"
      end
    end

    # ─── Install a single platform ───────────────────────────────────────────────
    # Returns Set of installed package names for this run.

    def install_platform(index, build_index, platform_id, dry_run: false, force_mode: false, select_list: nil,
                         project_arg: nil, quiet: false, specific_package: nil)
      installed_this_run = Set.new
      platform_id = platform_id.to_s

      platform_cfg = platform_cfg_for(platform_id)
      warn_prerequisites(platform_id, platform_cfg, quiet)

      base_path = resolve_install_base_path(platform_cfg, project_arg)
      Rulepack::Common.log "📁 Base path: #{base_path}" unless quiet
      Rulepack::Common.log "  Platform type: #{platform_cfg[:type]}" unless quiet

      build_index[:packages].each do |pkgname, pkgdata|
        next if specific_package && pkgname.to_s != specific_package

        targets = filter_targets_for_platform(pkgdata, platform_id)
        if targets.empty?
          Rulepack::Common.log "  ⊘ package '#{pkgname}': no target for #{platform_id}, skipping" unless quiet
          next
        end

        next unless should_install_or_upgrade?(pkgname, pkgdata, platform_id, index,
                                               force_mode, dry_run, quiet, select_list)

        ensure_package_in_index(index, pkgname, pkgdata)

        targets.each do |target|
          install_single_target(index, build_index, pkgname, pkgdata, target,
                                platform_cfg, base_path, nil, platform_id,
                                installed_this_run,
                                dry_run: dry_run, select_list: select_list, quiet: quiet)
        end
      end

      aggregate_vendor_skills(platform_id, platform_cfg, base_path) if platform_cfg[:type] == 'skill' && !dry_run

      installed_this_run
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

    def should_install_or_upgrade?(pkgname, pkgdata, platform_id, index, force_mode, dry_run, quiet,
                                   select_list = nil)
      pkg_index = index[:packages][pkgname] || { installed: [] }
      existing_records = (pkg_index[:installed] || []).select { |r| r[:platform] == platform_id }
      return true if existing_records.empty?

      existing = existing_records.first
      cmp = Rulepack::Common.compare_versions(
        pkgdata[:pkgver], existing[:version],
        epoch1: pkgdata[:epoch] || 0, epoch2: existing[:epoch] || 0,
        pkgrel1: pkgdata[:pkgrel] || 1, pkgrel2: existing[:pkgrel] || 1
      )

      case cmp
      when 0
        targets = Array(pkgdata[:targets])
        has_skill_bundle = targets.any? { |t| t[:platform] == platform_id && t[:format] == 'skill-bundle' }
        if select_list && has_skill_bundle
          ver = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log "  🔄 Re-installing #{pkgname} #{ver} (--select specified)"
          uninstall_single_package_from_index!(index, pkgname, platform_id) unless dry_run
          true
        elsif !select_list && has_skill_bundle
          # Reinstall skill-bundle to restore any sub-skills previously removed via --select
          ver = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log "  🔄 Restoring #{pkgname} #{ver} all sub-skills"
          uninstall_single_package_from_index!(index, pkgname, platform_id) unless dry_run
          true
        else
          unless quiet
            ver = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
            Rulepack::Common.log "  ↺ #{pkgname} already installed (#{ver})"
          end
          false
        end
      when 1
        unless quiet
          old_v = Rulepack::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])
          new_v = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log "  🔄 Upgrading #{pkgname} #{old_v} → #{new_v}"
        end
        uninstall_single_package_from_index!(index, pkgname, platform_id) unless dry_run
        true
      else
        handle_downgrade(pkgname, pkgdata, existing, force_mode, dry_run, quiet)
      end
    end

    def handle_downgrade(pkgname, pkgdata, existing, force_mode, dry_run, quiet)
      if force_mode
        unless quiet
          old_v = Rulepack::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])
          new_v = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log_warn "Downgrade forced for #{pkgname}: #{old_v} → #{new_v}"
        end
        uninstall_single_package_from_index!(index, pkgname, platform_id) unless dry_run
        true
      else
        unless quiet
          old_v = Rulepack::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])
          new_v = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log_error "Downgrade detected for #{pkgname}: installed #{old_v}, candidate #{new_v}"
        end
        Rulepack::Common.log_error 'Use --force to allow downgrade' unless quiet
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
        build_artifact = Rulepack::Common::BUILD_DIR.join(platform_id, expected_output)
        return "Build artifact missing: #{pkgname} (#{build_artifact})" unless build_artifact.exist?

        actual_sha = Digest::SHA256.hexdigest(build_artifact.read)
        return nil if actual_sha == expected_checksum

        return "Build artifact checksum mismatch: #{pkgname}"
      end

      installed_path = resolve_check_path(platform_cfg, target, base_path, nil)

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

      actual_sha = Digest::SHA256.hexdigest(installed_path.read)
      return nil if actual_sha == expected_checksum

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

    # rubocop:disable Metrics/ParameterLists
    def install_single_target(index, _build_index, pkgname, pkgdata, target,
                              platform_cfg, base_path, project_root, platform_id,
                              installed_this_run,
                              dry_run: false, select_list: nil, quiet: false)
      format = target[:format]

      case format
      when 'skill-bundle'
        opts = { dry_run: dry_run, select_list: select_list, quiet: quiet }
        nil unless install_skill_bundle(pkgname, pkgdata, target, platform_cfg, base_path,
                                        platform_id, index, installed_this_run, opts)
      else
        opts = { dry_run: dry_run, quiet: quiet }
        install_file_or_skill(pkgname, pkgdata, target, platform_cfg, base_path, project_root,
                              platform_id, index, installed_this_run, opts)
      end
    end
    # rubocop:enable Metrics/ParameterLists

    # ─── Skill-bundle install (selective directory copy) ───────────────────────────

    # rubocop:disable Metrics/ParameterLists
    def install_skill_bundle(pkgname, pkgdata, target, platform_cfg, base_path,
                             platform_id, index, installed_this_run, opts)
      dry_run = opts[:dry_run]
      select_list = opts[:select_list]
      quiet = opts[:quiet]
      install_cfg = target[:install] || {}
      Rulepack::Common.log "  ⤷ #{pkgname} (skill-bundle) → #{install_cfg[:target_dir]} [copy]" unless quiet

      build_src_dir = Rulepack::Common::BUILD_DIR.join(platform_id, pkgname.to_s)
      unless build_src_dir.exist? && build_src_dir.directory?
        Rulepack::Common.log_error "Skill-bundle build directory missing: #{build_src_dir}"
        return false
      end

      manifest = load_skill_bundle_manifest(build_src_dir)
      sub_skills = manifest&.dig('sub_skills') || []
      warn_large_bundle(build_src_dir, sub_skills) unless select_list

      selected = select_sub_skills(sub_skills, select_list, pkgname)
      return false unless selected

      dest_dir = base_path.join(platform_cfg[:skills_dir]).join(install_cfg[:target_dir])

      if dry_run
        selected.each do |ss|
          unless quiet
            Rulepack::Common.log "    [DRY-RUN] Would copy sub-skill: #{ss['path']} → #{dest_dir.join(ss['path'])}"
          end
        end
      else
        return false unless copy_sub_skills(build_src_dir, dest_dir, selected, pkgname, quiet: quiet)

        write_selected_manifest(dest_dir, manifest, pkgname, platform_id, selected)
      end

      record_installation(index, pkgname, platform_id, pkgdata, '.', nil) unless dry_run
      Rulepack::Common.log "  ✓ Installed: #{pkgname}" unless quiet
      installed_this_run << pkgname
      true
    end
    # rubocop:enable Metrics/ParameterLists

    def load_skill_bundle_manifest(build_src_dir)
      manifest_path = build_src_dir.join('manifest.json')
      manifest_path.exist? ? JSON.parse(manifest_path.read) : nil
    rescue JSON::ParserError => e
      Rulepack::Common.log_warn "  ⚠ Invalid manifest.json: #{e.message}"
      nil
    end

    def warn_large_bundle(build_src_dir, _sub_skills)
      manifest_path = build_src_dir.join('manifest.json')
      return unless manifest_path.exist?

      m = JSON.parse(manifest_path.read)
      sub_count = m['sub_skills']&.size.to_i
      if sub_count > 50
        Rulepack::Common.log_warn "  ⚠ #{sub_count} sub-skills. Use --select <names> to install specific ones."
      end
    rescue JSON::ParserError
      # ignore
    end

    def select_sub_skills(sub_skills, select_list, pkgname)
      if select_list && !select_list.empty?
        selected = sub_skills.select { |ss| select_list.include?(ss['name']) }
        if selected.empty?
          selected_s = select_list.join(',')
          Rulepack::Common.log_warn "  ⚠ --select #{selected_s}: no match in #{pkgname}"
          return nil
        end
        selected
      elsif $stdin.isatty && sub_skills.size.between?(2, 50)
        prompt_sub_skill_selection(sub_skills, pkgname)
      else
        sub_skills
      end
    end

    def copy_sub_skills(build_src_dir, dest_dir, selected, _pkgname, quiet: false)
      if dest_dir.exist?
        FileUtils.rm_rf(dest_dir)
        Rulepack::Common.log "    ✓ Removed existing: #{dest_dir}" unless quiet
      end
      FileUtils.mkpath(dest_dir)

      selected.each do |ss|
        if ss['path'] == '.'
          ss['files'].each_key do |rel_path|
            src_file = build_src_dir.join(rel_path)
            dst_file = dest_dir.join(rel_path)
            FileUtils.mkpath(dst_file.parent)
            FileUtils.cp(src_file, dst_file)
          end
          Rulepack::Common.log "    ✓ Copied sub-skill: . (#{ss['files'].size} file(s))" unless quiet
        else
          src_sub = build_src_dir.join(ss['path'])
          dst_sub = dest_dir.join(ss['path'])
          FileUtils.cp_r(src_sub, dst_sub)
          Rulepack::Common.log "    ✓ Copied sub-skill: #{ss['path']}" unless quiet
        end
      end
      true
    rescue StandardError => e
      Rulepack::Common.log_error "Failed to install skill-bundle: #{e.message}"
      false
    end

    def write_selected_manifest(dest_dir, manifest, pkgname, platform_id, selected)
      selected_manifest = {
        generated_at: manifest&.dig('generated_at') || Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        pkgname: pkgname.to_s,
        platform: platform_id.to_s,
        sub_skills: selected
      }
      dest_dir.join('manifest.json').write(JSON.pretty_generate(selected_manifest))
    end

    # ─── Single-file install (directory/import/skill platform types) ───────────────

    # rubocop:disable Metrics/ParameterLists
    def install_file_or_skill(pkgname, pkgdata, target, platform_cfg, base_path, project_root,
                              platform_id, index, installed_this_run, opts)
      dry_run = opts[:dry_run]
      quiet = opts[:quiet]
      output = target[:output]
      built_path = Rulepack::Common::BUILD_DIR.join(platform_id, output)
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
      install_type = install_cfg[:type] || platform_cfg[:"#{format}_install"]&.[](:type) || 'copy'
      install_path = resolve_install_path_for_target(platform_cfg, target, base_path, project_root)

      install_path.parent.mkpath unless dry_run

      Rulepack::Common.log "  ⤷ #{pkgname} (#{output}) → #{install_path} [#{install_type}]" unless quiet
      perform_file_install(built_path, install_path, content, content_sha256, install_type, platform_cfg, output,
                           dry_run, quiet)

      record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256) unless dry_run
      Rulepack::Common.log "  ✓ Installed: #{pkgname}" unless quiet
      installed_this_run << pkgname
    end
    # rubocop:enable Metrics/ParameterLists

    # rubocop:disable Metrics/ParameterLists
    def perform_file_install(built_path, install_path, content, content_sha256, install_type, platform_cfg, output,
                             dry_run, quiet)
      case install_type
      when 'symlink'
        if dry_run
          Rulepack::Common.log "    [DRY-RUN] Would symlink: #{built_path} → #{install_path}" unless quiet
        else
          do_symlink(built_path, install_path)
        end
      when 'copy'
        if dry_run
          Rulepack::Common.log "    [DRY-RUN] Would copy: #{built_path} → #{install_path}" unless quiet
        else
          do_copy(built_path, install_path, content_sha256)
        end
      when 'inject', 'append'
        if dry_run
          Rulepack::Common.log "    [DRY-RUN] Would #{install_type}: #{output} → #{install_path}" unless quiet
        else
          do_inject_append(install_path, content, install_type, platform_cfg, output)
        end
      else
        Rulepack::Common.log_error "Unknown install type: #{install_type}. Valid types: symlink, copy, inject, append."
      end
    end
    # rubocop:enable Metrics/ParameterLists

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

    # ─── Install type handlers ───────────────────────────────────────────────────

    def do_symlink(built_path, install_path)
      if install_path.symlink?
        if install_path.readlink == built_path.relative_path_from(install_path.parent)
          Rulepack::Common.log '    ↺ Already symlinked'
        else
          FileUtils.rm(install_path)
          FileUtils.ln_s(built_path.relative_path_from(install_path.parent), install_path)
          Rulepack::Common.log '    ✓ Replaced symlink'
        end
      elsif install_path.exist?
        Rulepack::Common.log_warn "    ⚠ Target exists and is not a symlink, skipping: #{install_path}"
      else
        FileUtils.ln_s(built_path.relative_path_from(install_path.parent), install_path)
        Rulepack::Common.log '    ✓ Symlinked'
      end
    rescue StandardError => e
      Rulepack::Common.log_error "Symlink failed: #{e.message}"
    end

    def do_copy(built_path, install_path, content_sha256)
      if install_path.exist?
        existing_sha = Digest::SHA256.hexdigest(install_path.read)
        if existing_sha == content_sha256
          Rulepack::Common.log '    ↺ Already up-to-date'
        else
          FileUtils.cp(built_path, install_path)
          Rulepack::Common.log '    ✓ Updated'
        end
      else
        FileUtils.cp(built_path, install_path)
        Rulepack::Common.log '    ✓ Copied'
      end
    rescue StandardError => e
      Rulepack::Common.log_error "Copy failed: #{e.message}"
    end

    def do_inject_append(install_path, content, install_type, platform_cfg, output)
      if install_type == 'append'
        if content_already_present?(install_path, content)
          Rulepack::Common.log '    ↺ Already present (skipping duplicate append)'
        else
          Rulepack::Common.atomic_append(install_path, content)
          Rulepack::Common.log '    ✓ Appended'
        end
      elsif install_type == 'inject'
        directive = platform_cfg[:rule_install]&.[](:directive) || '@import'
        import_line = "#{directive} \"#{output}\"\n"
        if install_path.exist?
          existing = install_path.read
          if existing.start_with?(import_line)
            Rulepack::Common.log '    ↺ Already injected'
          else
            Rulepack::Common.atomic_write(install_path, import_line + existing)
            Rulepack::Common.log '    ✓ Injected'
          end
        else
          Rulepack::Common.atomic_write(install_path, import_line)
          Rulepack::Common.log '    ✓ Injected (created config)'
        end
      end
    rescue StandardError => e
      Rulepack::Common.log_error "Install failed (#{install_type}): #{e.message}"
    end

    # ─── Vendor skill aggregation ────────────────────────────────────────────────

    def aggregate_vendor_skills(platform_id, platform_cfg, base_path)
      Rulepack::Common.log "  🧱 Aggregating vendor skills for #{platform_id}..."
      puts "\n  🧱 Aggregating vendor skills for #{platform_id}..."
      aggregate_script = Rulepack::Common::RULEPACK_ROOT.join('lib/rulepack/aggregate.rb')
      old_argv = ARGV.dup
      ARGV.replace([platform_id.to_s])
      agg_ok = begin
        load aggregate_script.to_s
        true
               rescue SystemExit
                 false
               end
      ARGV.replace(old_argv)
      if agg_ok
        Rulepack::Common.log '    ✓ Vendor skill aggregated'
        puts '    ✓ Vendor skill aggregated'
        vendor_file = Rulepack::Common::BUILD_DIR.join(platform_id, 'skills', 'vendor',
                                                       "#{platform_id}.md")
        if vendor_file.exist?
          install_path = base_path.join(platform_cfg[:skill_file])
          install_path.parent.mkpath
          FileUtils.cp(vendor_file, install_path)
          Rulepack::Common.log "  ✓ Installed vendor skill to #{install_path}"
          puts "  ✓ Installed vendor skill to #{install_path}"
        else
          Rulepack::Common.log_error "Vendor skill not generated: #{vendor_file}"
        end
      else
        Rulepack::Common.log_error 'Vendor skill aggregation failed'
      end
    end

    # ─── Helpers ────────────────────────────────────────────────────────────────

    def content_already_present?(path, new_content)
      return false unless path.exist?

      existing = path.read
      existing.include?(new_content)
    end

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
      log_error e.message
      exit 1
    end

    def project_root_for(_platform_id, platform_cfg, project_arg)
      Rulepack::Common.project_root_for(platform_cfg, project_arg)
    end

    def resolve_install_path_for_target(platform_cfg, target, base_path, project_root)
      install_cfg = target[:install] || {}
      output = target[:output]

      if install_cfg[:target_dir]
        target_subdir = Rulepack::Common.expand_user_path(install_cfg[:target_dir])
        if platform_cfg[:type] == 'directory'
          base_subdir = if %w[skill skill-bundle].include?(target[:format])
                          platform_cfg[:skills_dir]
                        else
                          platform_cfg[:rules_dir]
                        end
          if Pathname.new(target_subdir).absolute?
            Pathname.new(target_subdir).join(output)
          else
            base_path.join(base_subdir, target_subdir, output)
          end
        elsif Pathname.new(target_subdir).absolute?
          Pathname.new(target_subdir).join(output)
        else
          base_path.join(target_subdir, output)
        end
      else
        Rulepack::Common.resolve_install_path(platform_cfg, target, project_root)
      end
    end

    # Interactive sub-skill selection menu (pacman-style)
    # Returns array of selected sub-skills, or nil to skip
    def prompt_sub_skill_selection(sub_skills, pkgname)
      puts "\n📦 #{pkgname} contains #{sub_skills.size} sub-skills."
      puts 'Select sub-skills to install:'
      sub_skills.each_with_index do |ss, i|
        puts "  #{i + 1}) #{ss['name']}"
      end
      print "\nEnter numbers (e.g. 1,2,3, 5-10, or 'all'): "
      input = $stdin.gets&.strip || ''
      return sub_skills if input.empty? || input.downcase == 'all'

      indices = []
      input.split(',').each do |part|
        part = part.strip
        if part.include?('-')
          start_s, end_s = part.split('-', 2)
          next unless start_s.match?(/^\d+$/) && end_s.match?(/^\d+$/)

          (start_s.to_i..end_s.to_i).each { |i| indices << i }
        elsif part.match?(/^\d+$/)
          indices << part.to_i
        end
      end
      indices.uniq!
      indices.select! { |i| i.between?(1, sub_skills.size) }
      return sub_skills if indices.empty?

      selected = indices.map { |i| sub_skills[i - 1] }
      puts "  → Selected #{selected.size} sub-skill(s)\n\n"
      selected
    end

    def resolve_check_path(platform_cfg, target, base_path, project_root)
      install_cfg = target[:install] || {}
      output = target[:output]
      if install_cfg[:target_dir]
        target_subdir = Rulepack::Common.expand_user_path(install_cfg[:target_dir])
        resolved = if platform_cfg[:type] == 'directory'
                     base_subdir = if %w[skill skill-bundle].include?(target[:format])
                                     platform_cfg[:skills_dir]
                                   else
                                     platform_cfg[:rules_dir]
                                   end
                     if Pathname.new(target_subdir).absolute?
                       Pathname.new(target_subdir)
                     else
                       base_path.join(base_subdir, target_subdir)
                     end
                   elsif Pathname.new(target_subdir).absolute?
                     Pathname.new(target_subdir)
                   else
                     base_path.join(target_subdir)
                   end
        resolved = resolved.join(output) unless target[:format] == 'skill-bundle'
        resolved
      else
        Rulepack::Common.resolve_install_path(platform_cfg, target, project_root)
      end
    end
  end
end
