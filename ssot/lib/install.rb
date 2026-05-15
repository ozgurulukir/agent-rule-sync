# frozen_string_literal: true

# ssot/lib/install.rb — Installer library (modular API)
# Used by ssot/install.rb (CLI) and potentially other callers.

require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require 'json'
require 'set'
require_relative 'common'

module Ssot
  module Install
    module_function

    # ─── Main entry point ────────────────────────────────────────────────────────

    def run(platform_id, options = {})
      dry_run   = options.fetch(:dry_run, false)
      check_mode = options.fetch(:check_mode, false)
      force_mode = options.fetch(:force_mode, false)
      verbose_mode = options.fetch(:verbose_mode, false)
      select_list = options.fetch(:select_list, nil)
      project_arg = options.fetch(:project_arg, nil)

      $LOG_LEVEL = verbose_mode ? :debug : Ssot::Lib::Config.log_level

      if check_mode
        return check_platform(platform_id, project_arg: project_arg)
      end

      unless Ssot::Lib::Common::BUILD_INDEX_PATH.exist?
        Ssot::Lib::Common.log_error "Build index not found at #{Ssot::Lib::Common::BUILD_INDEX_PATH}. Run `ruby ssot/build.rb` first."
        exit 1
      end

      build_index = Ssot::Lib::Common.load_yaml(Ssot::Lib::Common::BUILD_INDEX_PATH)
      index = if Ssot::Lib::Common::INDEX_YAML_PATH.exist?
                Ssot::Lib::Common.load_yaml(Ssot::Lib::Common::INDEX_YAML_PATH)
              else
                { version: 3.0, packages: {} }
              end
      index[:packages] ||= {}
      (index[:packages] || {}).each_value { |pkg_idx| Ssot::Lib::Common.migrate_installed_records(pkg_idx) }

      backup_path = nil
      unless dry_run
        backup_path = Ssot::Lib::Common.backup_index
        Ssot::Lib::Common.log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      begin
        install_platform(index, build_index, platform_id,
                         dry_run: dry_run, force_mode: force_mode,
                         select_list: select_list, project_arg: project_arg)

        # Write index after successful install
        unless dry_run
          index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          Ssot::Lib::Common.write_yaml_atomic(Ssot::Lib::Common::INDEX_YAML_PATH, index)
          Ssot::Lib::Common.log "📝 Index written: #{Ssot::Lib::Common::INDEX_YAML_PATH}"
          puts "\n📝 Index written: #{Ssot::Lib::Common::INDEX_YAML_PATH}"
        else
          Ssot::Lib::Common.log "[DRY-RUN] Index write skipped"
          puts "\n[DRY-RUN] Index write skipped"
        end
      rescue => e
        if backup_path && Ssot::Lib::Common.restore_index(backup_path)
          Ssot::Lib::Common.log_error "Transaction failed (#{e.message}). Index restored from backup."
          puts "  ❌ Transaction failed. Index restored from backup: #{backup_path.basename}"
        else
          Ssot::Lib::Common.log_error "Transaction failed (#{e.message}). No backup available."
          puts "  ❌ Transaction failed: #{e.message}"
        end
        exit 1
      ensure
        Ssot::Lib::Common.cleanup_backups rescue nil
      end
    end

    # ─── Install all platforms ───────────────────────────────────────────────────

    def install_all(options = {})
      dry_run    = options.fetch(:dry_run, false)
      force_mode = options.fetch(:force_mode, false)
      verbose_mode = options.fetch(:verbose_mode, false)
      select_list = options.fetch(:select_list, nil)
      project_arg = options.fetch(:project_arg, nil)

      $LOG_LEVEL = verbose_mode ? :debug : Ssot::Lib::Config.log_level

      registry  = Ssot::Lib::Common.load_platform_registry
      platforms = registry.keys

      Ssot::Lib::Common.log "🚀 Installing ALL platforms (#{platforms.size} platforms)#{dry_run ? ' (dry-run)' : ''}"
      puts "🚀 Installing ALL platforms (#{platforms.size} platforms)#{dry_run ? ' (dry-run)' : ''}"

      unless Ssot::Lib::Common::BUILD_INDEX_PATH.exist?
        Ssot::Lib::Common.log_error "Build index not found at #{Ssot::Lib::Common::BUILD_INDEX_PATH}. Run `ruby ssot/build.rb` first."
        exit 1
      end

      build_index = Ssot::Lib::Common.load_yaml(Ssot::Lib::Common::BUILD_INDEX_PATH)
      index = if Ssot::Lib::Common::INDEX_YAML_PATH.exist?
                Ssot::Lib::Common.load_yaml(Ssot::Lib::Common::INDEX_YAML_PATH)
              else
                { version: 3.0, packages: {} }
              end
      index[:packages] ||= {}
      (index[:packages] || {}).each_value { |pkg_idx| Ssot::Lib::Common.migrate_installed_records(pkg_idx) }

      backup_path = nil
      unless dry_run
        backup_path = Ssot::Lib::Common.backup_index
        Ssot::Lib::Common.log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      all_installed = Set.new
      begin
        platforms.each do |platform_id|
          Ssot::Lib::Common.log "\n📦 Platform: #{platform_id}"
          begin
            installed = install_platform(index, build_index, platform_id,
                                         dry_run: dry_run, force_mode: force_mode,
                                         select_list: select_list, project_arg: project_arg,
                                         quiet: true)
            all_installed.merge(installed)
          rescue => e
            Ssot::Lib::Common.log_warn "Failed to install platform #{platform_id}: #{e.message}"
            puts "  ⚠️  #{platform_id}: #{e.message}"
          end
        end
      rescue => e
        if backup_path && Ssot::Lib::Common.restore_index(backup_path)
          Ssot::Lib::Common.log_error "Transaction failed (#{e.message}). Index restored from backup."
          puts "\n❌ Transaction failed. Index restored from backup: #{backup_path.basename}"
        else
          Ssot::Lib::Common.log_error "Transaction failed (#{e.message}). No backup available."
          puts "\n❌ Transaction failed: #{e.message}"
        end
        exit 1
      ensure
        Ssot::Lib::Common.cleanup_backups rescue nil
      end

      unless dry_run
        index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        Ssot::Lib::Common.write_yaml_atomic(Ssot::Lib::Common::INDEX_YAML_PATH, index)
        Ssot::Lib::Common.log "\n📝 Index written: #{Ssot::Lib::Common::INDEX_YAML_PATH}"
        puts "\n📝 Index written: #{Ssot::Lib::Common::INDEX_YAML_PATH}"
      else
        Ssot::Lib::Common.log "\n[DRY-RUN] Index write skipped"
        puts "\n[DRY-RUN] Index write skipped"
      end

      puts "\n✅ Install #{dry_run ? 'preview' : 'complete'}. #{all_installed.size} package(s) affected:"
      all_installed.each { |p| puts "   • #{p}" }
      puts ""
    end

    # ─── Install a single platform ───────────────────────────────────────────────
    # Returns Set of installed package names for this run.

    def install_platform(index, build_index, platform_id, dry_run: false, force_mode: false, select_list: nil, project_arg: nil, quiet: false)
      installed_this_run = Set.new
      platform_id = platform_id.to_s

      platform_cfg = platform_cfg_for(platform_id)
      warn_prerequisites(platform_id, platform_cfg, quiet)

      base_path = resolve_install_base_path(platform_cfg, project_arg)
      Ssot::Lib::Common.log "📁 Base path: #{base_path}" unless quiet
      Ssot::Lib::Common.log "  Platform type: #{platform_cfg[:type]}" unless quiet

      build_index[:packages].each do |pkgname, pkgdata|
        targets = filter_targets_for_platform(pkgdata, platform_id)
        if targets.empty?
          Ssot::Lib::Common.log "  ⊘ #{pkgname}: no target for #{platform_id}, skipping" unless quiet
          next
        end

        next unless should_install_or_upgrade?(pkgname, pkgdata, platform_id, index,
                                               force_mode, dry_run, quiet)

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
      Ssot::Lib::Common.log "🔍 Checking installed state for platform: #{platform_id}"
      puts "🔍 Checking installed state for platform: #{platform_id}"

      unless Ssot::Lib::Common::INDEX_YAML_PATH.exist?
        Ssot::Lib::Common.log_error "index.yaml not found. Run build first."
        raise "index.yaml not found"
      end

      index = Ssot::Lib::Common.load_yaml(Ssot::Lib::Common::INDEX_YAML_PATH)
      platform_cfg = platform_cfg_for(platform_id)
      warn_prerequisites(platform_id, platform_cfg, false)

      base_path = resolve_install_base_path(platform_cfg, project_arg)

      # Skill-type platforms: check vendor skill file only
      if platform_cfg[:type] == 'skill'
        check_vendor_skill_present(platform_cfg, base_path)
      end

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
      missing = Ssot::Lib::Common.check_prerequisites(platform_cfg)
      return if missing.empty?
      Ssot::Lib::Common.log_warn "Platform #{platform_id} may require: #{missing.join(', ')}" unless quiet
      puts "  ⚠️  Platform #{platform_id} may require: #{missing.join(', ')}" unless quiet
    end

    def resolve_install_base_path(platform_cfg, project_arg)
      project_root = Ssot::Lib::Common.project_root_for(platform_cfg, project_arg)
      if project_root
        project_root
      else
        Pathname.new(Ssot::Lib::Common.expand_user_path(platform_cfg[:base_path]))
      end
    end

    def filter_targets_for_platform(pkgdata, platform_id)
      pkgdata[:targets]&.select { |t| t[:platform] == platform_id } || []
    end

    def should_install_or_upgrade?(pkgname, pkgdata, platform_id, index, force_mode, dry_run, quiet)
      pkg_index = index[:packages][pkgname] || { installed: [] }
      existing_records = (pkg_index[:installed] || []).select { |r| r[:platform] == platform_id }
      return true if existing_records.empty?

      existing = existing_records.first
      cmp = Ssot::Lib::Common.compare_versions(
        { pkgver: pkgdata[:pkgver], pkgrel: pkgdata[:pkgrel], epoch: pkgdata[:epoch] },
        { pkgver: existing[:version], pkgrel: existing[:pkgrel], epoch: existing[:epoch] }
      )

      case cmp
      when 0
        Ssot::Lib::Common.log "  ↺ #{pkgname} already installed (#{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])})" unless quiet
        false
      when 1
        Ssot::Lib::Common.log "  🔄 Upgrading #{pkgname} #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])} → #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}" unless quiet
        uninstall_single_package_from_index!(index, pkgname, platform_id) unless dry_run
        true
      else
        handle_downgrade(pkgname, pkgdata, existing, force_mode, dry_run, quiet)
      end
    end

    def handle_downgrade(pkgname, pkgdata, existing, force_mode, dry_run, quiet)
      if force_mode
        Ssot::Lib::Common.log_warn "Downgrade forced for #{pkgname}: #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])} → #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}" unless quiet
        uninstall_single_package_from_index!(index, pkgname, platform_id) unless dry_run
        true
      else
        Ssot::Lib::Common.log_error "Downgrade detected for #{pkgname}: installed #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])}, candidate #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}" unless quiet
        Ssot::Lib::Common.log_error "Use --force to allow downgrade" unless quiet
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
        Ssot::Lib::Common.log_error "Vendor skill missing: #{vendor_path}"
        puts "  ❌ Vendor skill missing: #{vendor_path}"
        raise "Vendor skill missing"
      end
      Ssot::Lib::Common.log "  ✓ Vendor skill present: #{vendor_path}"
      puts "  ✅ Vendor skill present and readable"
      exit 0
    end

    def verify_package_on_disk(pkgname, pkgdata, inst, platform_id, platform_cfg, base_path)
      expected_output = inst[:output]
      expected_checksum = inst[:checksum]
      target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
      format_type = target ? target[:format] : 'directory'
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
          Ssot::Lib::Common.log "  ✓ Skill-bundle manifest: #{manifest['sub_skills'].size} sub-skill(s), #{total_files} file(s) verified"
          nil
        else
          Ssot::Lib::Common.log_warn "Skill-bundle manifest: #{mismatches.size} issue(s)"
          mismatches.each { |m| Ssot::Lib::Common.log_warn "    • #{m}" }
          mismatches.map { |m| "#{pkgname}: #{m}" }.join("; ")
        end
      rescue => e
        Ssot::Lib::Common.log_warn "Failed to read skill-bundle manifest: #{e.message}"
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
        Ssot::Lib::Common.log '✅ All installed packages are valid'
        puts "\n✅ All installed packages are valid"
        exit 0
      else
        Ssot::Lib::Common.log_error "#{errors.size} error(s) found"
        puts "\n❌ #{errors.size} error(s) found:"
        errors.each { |e| puts "  • #{e}" }
        exit 1
      end
    end

    # ─── Install a single target ─────────────────────────────────────────────────

    def install_single_target(index, build_index, pkgname, pkgdata, target,
                               platform_cfg, base_path, project_root, platform_id,
                               installed_this_run,
                               dry_run: false, select_list: nil, quiet: false)
      format = target[:format]

      case format
      when 'skill-bundle'
        return unless install_skill_bundle(pkgname, pkgdata, target, platform_cfg, base_path,
                                           platform_id, index, installed_this_run,
                                           dry_run: dry_run, select_list: select_list, quiet: quiet)
      else
        install_file_or_skill(pkgname, pkgdata, target, platform_cfg, base_path, project_root,
                              platform_id, index, installed_this_run,
                              dry_run: dry_run, quiet: quiet)
      end
    end

    # ─── Skill-bundle install (selective directory copy) ───────────────────────────

    def install_skill_bundle(pkgname, pkgdata, target, platform_cfg, base_path,
                             platform_id, index, installed_this_run,
                             dry_run: false, select_list: nil, quiet: false)
      install_cfg = target[:install] || {}
      Ssot::Lib::Common.log "  ⤷ #{pkgname} (skill-bundle) → #{install_cfg[:target_dir]} [copy]" unless quiet

      build_src_dir = Ssot::Lib::Common::BUILD_DIR.join(platform_id, pkgname.to_s)
      unless build_src_dir.exist? && build_src_dir.directory?
        Ssot::Lib::Common.log_error "Skill-bundle build directory missing: #{build_src_dir}"
        return false
      end

      manifest = load_skill_bundle_manifest(build_src_dir)
      sub_skills = manifest&.dig('sub_skills') || []
      warn_large_bundle(build_src_dir, sub_skills) unless select_list

      selected = select_sub_skills(sub_skills, select_list, pkgname)
      return false unless selected

      dest_dir = base_path.join(platform_cfg[:skills_dir]).join(install_cfg[:target_dir])

      if dry_run
        selected.each { |ss| Ssot::Lib::Common.log "    [DRY-RUN] Would copy sub-skill: #{ss['path']} → #{dest_dir.join(ss['path'])}" unless quiet }
      else
        return false unless copy_sub_skills(build_src_dir, dest_dir, selected, pkgname, quiet: quiet)
        write_selected_manifest(dest_dir, manifest, pkgname, platform_id, selected)
      end

      record_installation(index, pkgname, platform_id, pkgdata, '.', nil) unless dry_run
      Ssot::Lib::Common.log "  ✓ Installed: #{pkgname}" unless quiet
      installed_this_run << pkgname
      true
    end

    def load_skill_bundle_manifest(build_src_dir)
      manifest_path = build_src_dir.join('manifest.json')
      manifest_path.exist? ? JSON.parse(manifest_path.read) : nil
    rescue JSON::ParserError => e
      Ssot::Lib::Common.log_warn "  ⚠ Invalid manifest.json: #{e.message}"
      nil
    end

    def warn_large_bundle(build_src_dir, sub_skills)
      manifest_path = build_src_dir.join('manifest.json')
      return unless manifest_path.exist?
      m = JSON.parse(manifest_path.read)
      sub_count = m['sub_skills']&.size.to_i
      Ssot::Lib::Common.log_warn "  ⚠ Large bundle: #{sub_count} sub-skills. Use --select <names> to install only specific ones." if sub_count > 50
    rescue JSON::ParserError
      # ignore
    end

    def select_sub_skills(sub_skills, select_list, pkgname)
      if select_list && !select_list.empty?
        selected = sub_skills.select { |ss| select_list.include?(ss['name']) }
        if selected.empty?
          Ssot::Lib::Common.log_warn "  ⚠ No matching sub-skills for --select #{select_list.join(',')} in #{pkgname}, skipping"
          return nil
        end
        selected
      elsif STDIN.isatty && sub_skills.size > 1
        prompt_sub_skill_selection(sub_skills, pkgname)
      else
        sub_skills
      end
    end

    def copy_sub_skills(build_src_dir, dest_dir, selected, pkgname, quiet: false)
      if dest_dir.exist?
        FileUtils.rm_rf(dest_dir)
        Ssot::Lib::Common.log "    ✓ Removed existing: #{dest_dir}" unless quiet
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
          Ssot::Lib::Common.log "    ✓ Copied sub-skill: . (#{ss['files'].size} file(s))" unless quiet
        else
          src_sub = build_src_dir.join(ss['path'])
          dst_sub = dest_dir.join(ss['path'])
          FileUtils.cp_r(src_sub, dst_sub)
          Ssot::Lib::Common.log "    ✓ Copied sub-skill: #{ss['path']}" unless quiet
        end
      end
      true
    rescue => e
      Ssot::Lib::Common.log_error "Failed to install skill-bundle: #{e.message}"
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

    def install_file_or_skill(pkgname, pkgdata, target, platform_cfg, base_path, project_root,
                              platform_id, index, installed_this_run,
                              dry_run: false, quiet: false)
      output = target[:output]
      built_path = Ssot::Lib::Common::BUILD_DIR.join(platform_id, output)
      unless built_path.exist?
        Ssot::Lib::Common.log_error "Built artifact missing: #{built_path}. Run `ruby ssot/build.rb` first."
        return
      end

      content = built_path.read
      content_sha256 = Digest::SHA256.hexdigest(content)

      # Skill-type platforms: record only, aggregation handles file install
      if platform_cfg[:type] == 'skill'
        record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256) unless dry_run
        Ssot::Lib::Common.log "  ✓ Installed: #{pkgname}" unless quiet
        installed_this_run << pkgname
        return
      end

      install_cfg = target[:install] || {}
      format = target[:format]
      install_type = install_cfg[:type] || platform_cfg[:"#{format}_install"]&.[](:type) || 'copy'
      install_path = resolve_install_path_for_target(platform_cfg, target, base_path, project_root)

      unless dry_run
        install_path.parent.mkpath
      end

      Ssot::Lib::Common.log "  ⤷ #{pkgname} (#{output}) → #{install_path} [#{install_type}]" unless quiet
      perform_file_install(built_path, install_path, content, content_sha256, install_type, platform_cfg, output, dry_run, quiet)

      record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256) unless dry_run
      Ssot::Lib::Common.log "  ✓ Installed: #{pkgname}" unless quiet
      installed_this_run << pkgname
    end

    def perform_file_install(built_path, install_path, content, content_sha256, install_type, platform_cfg, output, dry_run, quiet)
      case install_type
      when 'symlink'
        if dry_run
          Ssot::Lib::Common.log "    [DRY-RUN] Would symlink: #{built_path} → #{install_path}" unless quiet
        else
          do_symlink(built_path, install_path)
        end
      when 'copy'
        if dry_run
          Ssot::Lib::Common.log "    [DRY-RUN] Would copy: #{built_path} → #{install_path}" unless quiet
        else
          do_copy(built_path, install_path, content_sha256)
        end
      when 'inject', 'append'
        if dry_run
          Ssot::Lib::Common.log "    [DRY-RUN] Would #{install_type}: #{output} → #{install_path}" unless quiet
        else
          do_inject_append(install_path, content, install_type, platform_cfg, output)
        end
      else
        Ssot::Lib::Common.log_error "Unknown install type: #{install_type}. Valid types: symlink, copy, inject, append."
      end
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

    # ─── Install type handlers ───────────────────────────────────────────────────

    def do_symlink(built_path, install_path)
      if install_path.symlink?
        if install_path.readlink == built_path.relative_path_from(install_path.parent)
          Ssot::Lib::Common.log "    ↺ Already symlinked"
        else
          FileUtils.rm(install_path)
          FileUtils.ln_s(built_path.relative_path_from(install_path.parent), install_path)
          Ssot::Lib::Common.log "    ✓ Replaced symlink"
        end
      elsif install_path.exist?
        Ssot::Lib::Common.log_warn "    ⚠ Target exists and is not a symlink, skipping: #{install_path}"
      else
        FileUtils.ln_s(built_path.relative_path_from(install_path.parent), install_path)
        Ssot::Lib::Common.log "    ✓ Symlinked"
      end
    rescue => e
      Ssot::Lib::Common.log_error "Symlink failed: #{e.message}"
    end

    def do_copy(built_path, install_path, content_sha256)
      if install_path.exist?
        existing_sha = Digest::SHA256.hexdigest(install_path.read)
        if existing_sha == content_sha256
          Ssot::Lib::Common.log "    ↺ Already up-to-date"
        else
          FileUtils.cp(built_path, install_path)
          Ssot::Lib::Common.log "    ✓ Updated"
        end
      else
        FileUtils.cp(built_path, install_path)
        Ssot::Lib::Common.log "    ✓ Copied"
      end
    rescue => e
      Ssot::Lib::Common.log_error "Copy failed: #{e.message}"
    end

    def do_inject_append(install_path, content, install_type, platform_cfg, output)
      if install_type == 'append'
        if content_already_present?(install_path, content)
          Ssot::Lib::Common.log "    ↺ Already present (skipping duplicate append)"
        else
          Ssot::Lib::Common.atomic_append(install_path, content)
          Ssot::Lib::Common.log "    ✓ Appended"
        end
      elsif install_type == 'inject'
        directive = platform_cfg[:rule_install]&.[](:directive) || '@import'
        import_line = "#{directive} \"#{output}\"\n"
        unless install_path.exist?
          Ssot::Lib::Common.atomic_write(install_path, import_line)
          Ssot::Lib::Common.log "    ✓ Injected (created config)"
        else
          existing = install_path.read
          if existing.start_with?(import_line)
            Ssot::Lib::Common.log "    ↺ Already injected"
          else
            Ssot::Lib::Common.atomic_write(install_path, import_line + existing)
            Ssot::Lib::Common.log "    ✓ Injected"
          end
        end
      end
    rescue => e
      Ssot::Lib::Common.log_error "Install failed (#{install_type}): #{e.message}"
    end

    # ─── Vendor skill aggregation ────────────────────────────────────────────────

    def aggregate_vendor_skills(platform_id, platform_cfg, base_path)
      Ssot::Lib::Common.log "  🧱 Aggregating vendor skills for #{platform_id}..."
      puts "\n  🧱 Aggregating vendor skills for #{platform_id}..."
      aggregate_script = Ssot::Lib::Common::SSOT_ROOT.join('aggregate-skills.rb')
      system('ruby', aggregate_script.to_s, platform_id.to_s)
      if $?.success?
        Ssot::Lib::Common.log "    ✓ Vendor skill aggregated"
        puts "    ✓ Vendor skill aggregated"
        vendor_file = Ssot::Lib::Common::BUILD_DIR.join(platform_id, 'skills', 'vendor', "#{platform_id}.md")
        if vendor_file.exist?
          install_path = base_path.join(platform_cfg[:skill_file])
          install_path.parent.mkpath
          FileUtils.cp(vendor_file, install_path)
          Ssot::Lib::Common.log "  ✓ Installed vendor skill to #{install_path}"
          puts "  ✓ Installed vendor skill to #{install_path}"
        else
          Ssot::Lib::Common.log_error "Vendor skill not generated: #{vendor_file}"
        end
      else
        Ssot::Lib::Common.log_error "Vendor skill aggregation failed"
      end
    end

    # ─── Helpers ────────────────────────────────────────────────────────────────

    def content_already_present?(path, new_content)
      return false unless path.exist?
      existing = path.read
      existing.include?(new_content)
    end

    def uninstall_single_package_from_index!(index, pkgname, platform_id, project_root: nil)
      Ssot::Lib::Common.uninstall_packages(index, platform_id, dry_run: false,
                                           project_root: project_root,
                                           specific_packages: [pkgname]).include?(pkgname)
    end

    def platform_cfg_for(platform_id)
      registry = Ssot::Lib::Common.load_platform_registry
      Ssot::Lib::Common.platform_config(platform_id, registry)
    rescue => e
      warn "PLATFORM_CFG_ERROR: #{e.message}"
      log_error e.message
      exit 1
    end

    def project_root_for(platform_id, platform_cfg, project_arg)
      Ssot::Lib::Common.project_root_for(platform_cfg, project_arg)
    end

    def resolve_install_path_for_target(platform_cfg, target, base_path, project_root)
      install_cfg = target[:install] || {}
      output = target[:output]

      if install_cfg[:target_dir]
        target_subdir = Ssot::Lib::Common.expand_user_path(install_cfg[:target_dir])
        if platform_cfg[:type] == 'directory'
          base_subdir = (target[:format] == 'skill' || target[:format] == 'skill-bundle') ?
                        platform_cfg[:skills_dir] : platform_cfg[:rules_dir]
          if Pathname.new(target_subdir).absolute?
            Pathname.new(target_subdir).join(output)
          else
            base_path.join(base_subdir, target_subdir, output)
          end
        else
          if Pathname.new(target_subdir).absolute?
            Pathname.new(target_subdir).join(output)
          else
            base_path.join(target_subdir, output)
          end
        end
      else
        Ssot::Lib::Common.resolve_install_path(platform_cfg, target, project_root)
      end
    end

    # Interactive sub-skill selection menu (pacman-style)
    # Returns array of selected sub-skills, or nil to skip
    def prompt_sub_skill_selection(sub_skills, pkgname)
      puts "\n📦 #{pkgname} contains #{sub_skills.size} sub-skills."
      puts "Select sub-skills to install:"
      sub_skills.each_with_index do |ss, i|
        puts "  #{i + 1}) #{ss['name']}"
      end
      print "\nEnter numbers (e.g. 1,2,3, 5-10, or 'all'): "
      input = STDIN.gets&.strip || ''
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
      indices.select! { |i| i >= 1 && i <= sub_skills.size }
      return sub_skills if indices.empty?
      selected = indices.map { |i| sub_skills[i - 1] }
      puts "  → Selected #{selected.size} sub-skill(s)\n\n"
      selected
    end

    def resolve_check_path(platform_cfg, target, base_path, project_root)
      install_cfg = target[:install] || {}
      output = target[:output]
      if install_cfg[:target_dir]
        target_subdir = Ssot::Lib::Common.expand_user_path(install_cfg[:target_dir])
        resolved = if platform_cfg[:type] == 'directory'
                     base_subdir = (target[:format] == 'skill' || target[:format] == 'skill-bundle') ?
                                   platform_cfg[:skills_dir] : platform_cfg[:rules_dir]
                     if Pathname.new(target_subdir).absolute?
                       Pathname.new(target_subdir)
                     else
                       base_path.join(base_subdir, target_subdir)
                     end
                   else
                     if Pathname.new(target_subdir).absolute?
                       Pathname.new(target_subdir)
                     else
                       base_path.join(target_subdir)
                     end
                   end
        resolved = resolved.join(output) unless target[:format] == 'skill-bundle'
        resolved
      else
        Ssot::Lib::Common.resolve_install_path(platform_cfg, target, project_root)
      end
    end

  end
end
