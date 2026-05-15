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
        log_error "Build index not found at #{Ssot::Lib::Common::BUILD_INDEX_PATH}. Run `ruby ssot/build.rb` first."
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
        log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      begin
        install_platform(index, build_index, platform_id,
                         dry_run: dry_run, force_mode: force_mode,
                         select_list: select_list, project_arg: project_arg)

        # Write index after successful install
        unless dry_run
          index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          Ssot::Lib::Common.write_yaml_atomic(Ssot::Lib::Common::INDEX_YAML_PATH, index)
          log "📝 Index written: #{Ssot::Lib::Common::INDEX_YAML_PATH}"
          puts "\n📝 Index written: #{Ssot::Lib::Common::INDEX_YAML_PATH}"
        else
          log "[DRY-RUN] Index write skipped"
          puts "\n[DRY-RUN] Index write skipped"
        end
      rescue => e
        if backup_path && Ssot::Lib::Common.restore_index(backup_path)
          log_error "Transaction failed (#{e.message}). Index restored from backup."
          puts "  ❌ Transaction failed. Index restored from backup: #{backup_path.basename}"
        else
          log_error "Transaction failed (#{e.message}). No backup available."
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

      log "🚀 Installing ALL platforms (#{platforms.size} platforms)#{dry_run ? ' (dry-run)' : ''}"
      puts "🚀 Installing ALL platforms (#{platforms.size} platforms)#{dry_run ? ' (dry-run)' : ''}"

      unless Ssot::Lib::Common::BUILD_INDEX_PATH.exist?
        log_error "Build index not found at #{Ssot::Lib::Common::BUILD_INDEX_PATH}. Run `ruby ssot/build.rb` first."
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
        log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
      end

      all_installed = Set.new
      begin
        platforms.each do |platform_id|
          log "\n📦 Platform: #{platform_id}"
          begin
            installed = install_platform(index, build_index, platform_id,
                                         dry_run: dry_run, force_mode: force_mode,
                                         select_list: select_list, project_arg: project_arg,
                                         quiet: true)
            all_installed.merge(installed)
          rescue => e
            log_warn "Failed to install platform #{platform_id}: #{e.message}"
            puts "  ⚠️  #{platform_id}: #{e.message}"
          end
        end
      rescue => e
        if backup_path && Ssot::Lib::Common.restore_index(backup_path)
          log_error "Transaction failed (#{e.message}). Index restored from backup."
          puts "\n❌ Transaction failed. Index restored from backup: #{backup_path.basename}"
        else
          log_error "Transaction failed (#{e.message}). No backup available."
          puts "\n❌ Transaction failed: #{e.message}"
        end
        exit 1
      ensure
        Ssot::Lib::Common.cleanup_backups rescue nil
      end

      unless dry_run
        index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        Ssot::Lib::Common.write_yaml_atomic(Ssot::Lib::Common::INDEX_YAML_PATH, index)
        log "\n📝 Index written: #{Ssot::Lib::Common::INDEX_YAML_PATH}"
        puts "\n📝 Index written: #{Ssot::Lib::Common::INDEX_YAML_PATH}"
      else
        log "\n[DRY-RUN] Index write skipped"
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
      platform_id = platform_id.to_s  # normalize: YAML stores platform as string

      platform_cfg = platform_cfg_for(platform_id)
      missing = Ssot::Lib::Common.check_prerequisites(platform_cfg)
      unless missing.empty?
        log_warn "Platform #{platform_id} may require: #{missing.join(', ')}" unless quiet
        puts "  ⚠️  Platform #{platform_id} may require: #{missing.join(', ')}" unless quiet
      end

      project_root = project_root_for(platform_id, platform_cfg, project_arg)
      base_path = if project_root
                    project_root
                  else
                    Pathname.new(Ssot::Lib::Common.expand_user_path(platform_cfg[:base_path]))
                  end

      log "📁 Base path: #{base_path}" unless quiet
      log "  Platform type: #{platform_cfg[:type]}" unless quiet

      build_index[:packages].each do |pkgname, pkgdata|
        targets = pkgdata[:targets]&.select { |t| t[:platform] == platform_id }
        if targets.nil? || targets.empty?
          log "  ⊘ #{pkgname}: no target for #{platform_id}, skipping" unless quiet
          next
        end
        pkg_index = index[:packages][pkgname] || { installed: [] }
        existing_records = (pkg_index[:installed] || []).select { |r| r[:platform] == platform_id }

        if existing_records.any?
          existing = existing_records.first
          cmp = Ssot::Lib::Common.compare_versions(
            pkgdata[:pkgver], existing[:version],
            pkgrel1: pkgdata[:pkgrel], pkgrel2: existing[:pkgrel],
            epoch1: pkgdata[:epoch], epoch2: existing[:epoch]
          )

          if cmp == 0
            log "  ↺ #{pkgname} already installed (#{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])})" unless quiet
            next
          elsif cmp > 0
            log "  🔄 Upgrading #{pkgname} #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])} → #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}" unless quiet
            unless dry_run
              uninstall_single_package_from_index!(index, pkgname, platform_id, project_root: project_root) || next
            end
          else
            if force_mode
              log_warn "Downgrade forced for #{pkgname}: #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])} → #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}" unless quiet
              unless dry_run
                uninstall_single_package_from_index!(index, pkgname, platform_id, project_root: project_root) || next
              end
            else
              log_error "Downgrade detected for #{pkgname}: installed #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])}, candidate #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}" unless quiet
              log_error "Use --force to allow downgrade" unless quiet
              next
            end
          end
        end

        # Ensure package entry exists in index
        pkg_index = index[:packages][pkgname] ||= {}
        pkg_index[:installed] ||= []
        pkg_index.merge!(pkgdata.reject { |k, _| k == :installed })

        # Install each target for this platform
        targets.each do |target|
          install_single_target(index, build_index, pkgname, pkgdata, target,
                                platform_cfg, base_path, project_root, platform_id,
                                installed_this_run,
                                dry_run: dry_run, select_list: select_list, quiet: quiet)
        end
      end

      # Vendor skill aggregation for skill-type platforms
      if platform_cfg[:type] == 'skill' && !dry_run
        aggregate_vendor_skills(platform_id, platform_cfg, base_path)
      end

      installed_this_run
    end

    # ─── Check platform ──────────────────────────────────────────────────────────

    def check_platform(platform_id, project_arg: nil)
      platform_id = platform_id.to_s
      log "🔍 Checking installed state for platform: #{platform_id}"
      puts "🔍 Checking installed state for platform: #{platform_id}"

      unless Ssot::Lib::Common::INDEX_YAML_PATH.exist?
        log_error "index.yaml not found. Run build first."
        raise "index.yaml not found"
      end

      index = Ssot::Lib::Common.load_yaml(Ssot::Lib::Common::INDEX_YAML_PATH)
      platform_cfg = platform_cfg_for(platform_id)

      missing = Ssot::Lib::Common.check_prerequisites(platform_cfg)
      unless missing.empty?
        log_warn "Platform #{platform_id} may require: #{missing.join(', ')}"
        puts "  ⚠️  Platform #{platform_id} may require: #{missing.join(', ')}"
      end

      project_root = project_root_for(platform_id, platform_cfg, project_arg)
      base_path = if project_root
                    project_root
                  else
                    Pathname.new(Ssot::Lib::Common.expand_user_path(platform_cfg[:base_path]))
                  end

      if platform_cfg[:type] == 'skill'
        vendor_path = base_path.join(platform_cfg[:skill_file])
        unless vendor_path.exist?
          log_error "Vendor skill missing: #{vendor_path}"
          puts "  ❌ Vendor skill missing: #{vendor_path}"
          raise "Vendor skill missing"
        end
        log "  ✓ Vendor skill present: #{vendor_path}"
        puts "  ✅ Vendor skill present and readable"
        exit 0
      end

      errors = []
      index[:packages].each do |pkgname, pkgdata|
        inst = pkgdata[:installed].find { |i| i[:platform] == platform_id }
        next unless inst

        expected_output = inst[:output]
        expected_checksum = inst[:checksum]
        target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
        format_type = target ? target[:format] : 'directory'
        _install_cfg = target[:install] || {}

        installed_path = resolve_check_path(platform_cfg, target, base_path, project_root)

        if format_type == 'skill-bundle'
          unless installed_path.directory?
            errors << "Skill-bundle directory missing: #{installed_path}"
          else
            manifest_path = Pathname.new(installed_path).join('manifest.json')
            if manifest_path.exist?
              begin
                manifest = JSON.parse(manifest_path.read)
                mismatches = []
                total_files = 0
                manifest['sub_skills'].each do |sub_skill|
                  sub_skill['files'].each do |rel_path, expected_sha|
                    total_files += 1
                    file_path = Pathname.new(installed_path).join(rel_path)
                    unless file_path.exist?
                      mismatches << "missing: #{rel_path}"
                    else
                      actual_sha = Digest::SHA256.hexdigest(file_path.read)
                      unless actual_sha == expected_sha
                        mismatches << "checksum mismatch: #{rel_path}"
                      end
                    end
                  end
                end
                if mismatches.empty?
                  log "  ✓ Skill-bundle manifest: #{manifest['sub_skills'].size} sub-skill(s), #{total_files} file(s) verified"
                else
                  log_warn "Skill-bundle manifest: #{mismatches.size} issue(s)"
                  mismatches.each { |m| log_warn "    • #{m}" }
                  errors.concat(mismatches.map { |m| "#{pkgname}: #{m}" })
                end
              rescue => e
                log_warn "Failed to read skill-bundle manifest: #{e.message}"
                errors << "#{pkgname}: manifest unreadable"
              end
            else
              errors << "#{pkgname}: no manifest"
            end
          end
        else
          unless installed_path.exist?
            errors << "Missing: #{pkgname} (#{expected_output}) at #{installed_path}"
            next
          end
          actual_sha = Digest::SHA256.hexdigest(installed_path.read)
          if actual_sha != expected_checksum
            errors << "Checksum mismatch: #{pkgname} (#{expected_output})"
          end
        end
      end

      if errors.empty?
        log '✅ All installed packages are valid'
        puts "\n✅ All installed packages are valid"
        exit 0
      else
        log_error "#{errors.size} error(s) found"
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
      output = target[:output]
      install_cfg = target[:install] || {}
      install_type = install_cfg[:type] || platform_cfg[:"#{format}_install"]&.[](:type) || 'copy'

      # skill-bundle: selective directory copy
      if format == 'skill-bundle'
        log "  ⤷ #{pkgname} (skill-bundle) → #{install_cfg[:target_dir]} [copy]" unless quiet

        # Warn about large bundles without --select
        manifest_path = Ssot::Lib::Common::BUILD_DIR.join(platform_id, pkgname.to_s, 'manifest.json')
        unless select_list
          if manifest_path.exist?
            m = JSON.parse(manifest_path.read)
            sub_count = m['sub_skills']&.size.to_i
            if sub_count > 50
              log_warn "  ⚠ Large bundle: #{sub_count} sub-skills. Use --select <names> to install only specific ones."
            end
          end
        end

        build_src_dir = Ssot::Lib::Common::BUILD_DIR.join(platform_id, pkgname.to_s)
        unless build_src_dir.exist? && build_src_dir.directory?
          log_error "Skill-bundle build directory missing: #{build_src_dir}"
          return
        end

        dest_dir = base_path.join(platform_cfg[:skills_dir]).join(install_cfg[:target_dir])
        manifest_path = build_src_dir.join('manifest.json')
        manifest = manifest_path.exist? ? JSON.parse(manifest_path.read) : nil
        sub_skills = manifest&.dig('sub_skills') || []

        if select_list && !select_list.empty?
          selected = sub_skills.select { |ss| select_list.include?(ss['name']) }
          if selected.empty?
            log_warn "  ⚠ No matching sub-skills for --select #{select_list.join(',')} in #{pkgname}, skipping"
            return
          end
          log "    🔍 Selecting sub-skills: #{selected.map { |ss| ss['name'] }.join(', ')}" unless quiet
        elsif STDIN.isatty && sub_skills.size > 1
          selected = prompt_sub_skill_selection(sub_skills, pkgname)
          return unless selected
        else
          selected = sub_skills
        end

        if dry_run
          selected.each do |ss|
            log "    [DRY-RUN] Would copy sub-skill: #{ss['path']} → #{dest_dir.join(ss['path'])}" unless quiet
          end
        else
          begin
            if dest_dir.exist?
              FileUtils.rm_rf(dest_dir)
              log "    ✓ Removed existing: #{dest_dir}" unless quiet
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
                log "    ✓ Copied sub-skill: . (#{ss['files'].size} file(s))" unless quiet
              else
                src_sub = build_src_dir.join(ss['path'])
                dst_sub = dest_dir.join(ss['path'])
                FileUtils.cp_r(src_sub, dst_sub)
                log "    ✓ Copied sub-skill: #{ss['path']}" unless quiet
              end
            end
            selected_manifest = {
              generated_at: manifest&.dig('generated_at') || Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
              pkgname: pkgname.to_s,
              platform: platform_id.to_s,
              sub_skills: selected
            }
            manifest_dest = dest_dir.join('manifest.json')
            manifest_dest.write(JSON.pretty_generate(selected_manifest))
            log "    ✓ Installed skill-bundle (#{selected.size} sub-skill(s))" unless quiet
          rescue => e
            log_error "Failed to install skill-bundle: #{e.message}"
            return
          end
        end

        unless dry_run
          pkg_index = index[:packages][pkgname] || { installed: [] }
          pkg_index[:installed] ||= []
          installed_record = {
            platform: platform_id,
            version: pkgdata[:pkgver],
            pkgrel: pkgdata[:pkgrel],
            epoch: pkgdata[:epoch],
            output: '.',
            checksum: nil,
            installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          }
          pkg_index[:installed].reject! { |r| r[:platform] == platform_id }
          pkg_index[:installed] << installed_record
        end

        log "  ✓ Installed: #{pkgname}" unless quiet
        installed_this_run << pkgname
        return
      end

      # Single-file formats (directory, import, skill)
      built_path = Ssot::Lib::Common::BUILD_DIR.join(platform_id, output)
      unless built_path.exist?
        log_error "Built artifact missing: #{built_path}. Run `ruby ssot/build.rb` first."
        return
      end

      content = built_path.read
      content_sha256 = Digest::SHA256.hexdigest(content)

      # Skill-type platforms: skip individual file install; aggregation handles it
      if platform_cfg[:type] == 'skill'
        unless dry_run
          pkg_index = index[:packages][pkgname] || { installed: [] }
          pkg_index[:installed] ||= []
          installed_record = {
            platform: platform_id,
            version: pkgdata[:pkgver],
            pkgrel: pkgdata[:pkgrel],
            epoch: pkgdata[:epoch],
            output: output,
            checksum: content_sha256,
            installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          }
          pkg_index[:installed].reject! { |r| r[:platform] == platform_id && r[:output] == output }
          pkg_index[:installed] << installed_record
        end
        log "  ✓ Installed: #{pkgname}" unless quiet
        installed_this_run << pkgname
        return
      end

      # Resolve install path
      install_path = resolve_install_path_for_target(platform_cfg, target, base_path, project_root)

      unless dry_run
        install_path.parent.mkpath
      end

      log "  ⤷ #{pkgname} (#{output}) → #{install_path} [#{install_type}]" unless quiet

      # Perform install based on type
      case install_type
      when 'symlink'
        if dry_run
          log "    [DRY-RUN] Would symlink: #{built_path} → #{install_path}" unless quiet
        else
          do_symlink(built_path, install_path)
        end
      when 'copy'
        if dry_run
          log "    [DRY-RUN] Would copy: #{built_path} → #{install_path}" unless quiet
        else
          do_copy(built_path, install_path, content_sha256)
        end
      when 'inject', 'append'
        if dry_run
          log "    [DRY-RUN] Would #{install_type}: #{output} → #{install_path}" unless quiet
        else
          do_inject_append(install_path, content, install_type, platform_cfg, output)
        end
      else
        log_error "Unknown install type: #{install_type} for #{pkgname}. Valid types: symlink, copy, inject, append."
        return
      end

      # Record installation
      unless dry_run
        pkg_index = index[:packages][pkgname] || { installed: [] }
        pkg_index[:installed] ||= []
        installed_record = {
          platform: platform_id,
          version: pkgdata[:pkgver],
          pkgrel: pkgdata[:pkgrel],
          epoch: pkgdata[:epoch],
          output: output,
          checksum: content_sha256,
          installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        }
        pkg_index[:installed].reject! { |r| r[:platform] == platform_id && r[:output] == output }
        pkg_index[:installed] << installed_record
      end

      log "  ✓ Installed: #{pkgname}" unless quiet
      installed_this_run << pkgname
    end

    # ─── Install type handlers ───────────────────────────────────────────────────

    def do_symlink(built_path, install_path)
      if install_path.symlink?
        if install_path.readlink == built_path.relative_path_from(install_path.parent)
          log "    ↺ Already symlinked"
        else
          FileUtils.rm(install_path)
          FileUtils.ln_s(built_path.relative_path_from(install_path.parent), install_path)
          log "    ✓ Replaced symlink"
        end
      elsif install_path.exist?
        log_warn "    ⚠ Target exists and is not a symlink, skipping: #{install_path}"
      else
        FileUtils.ln_s(built_path.relative_path_from(install_path.parent), install_path)
        log "    ✓ Symlinked"
      end
    rescue => e
      log_error "Symlink failed: #{e.message}"
    end

    def do_copy(built_path, install_path, content_sha256)
      if install_path.exist?
        existing_sha = Digest::SHA256.hexdigest(install_path.read)
        if existing_sha == content_sha256
          log "    ↺ Already up-to-date"
        else
          FileUtils.cp(built_path, install_path)
          log "    ✓ Updated"
        end
      else
        FileUtils.cp(built_path, install_path)
        log "    ✓ Copied"
      end
    rescue => e
      log_error "Copy failed: #{e.message}"
    end

    def do_inject_append(install_path, content, install_type, platform_cfg, output)
      if install_type == 'append'
        if content_already_present?(install_path, content)
          log "    ↺ Already present (skipping duplicate append)"
        else
          Ssot::Lib::Common.atomic_append(install_path, content)
          log "    ✓ Appended"
        end
      elsif install_type == 'inject'
        directive = platform_cfg[:rule_install]&.[](:directive) || '@import'
        import_line = "#{directive} \"#{output}\"\n"
        unless install_path.exist?
          Ssot::Lib::Common.atomic_write(install_path, import_line)
          log "    ✓ Injected (created config)"
        else
          existing = install_path.read
          if existing.start_with?(import_line)
            log "    ↺ Already injected"
          else
            Ssot::Lib::Common.atomic_write(install_path, import_line + existing)
            log "    ✓ Injected"
          end
        end
      end
    rescue => e
      log_error "Install failed (#{install_type}): #{e.message}"
    end

    # ─── Vendor skill aggregation ────────────────────────────────────────────────

    def aggregate_vendor_skills(platform_id, platform_cfg, base_path)
      log "  🧱 Aggregating vendor skills for #{platform_id}..."
      puts "\n  🧱 Aggregating vendor skills for #{platform_id}..."
      aggregate_script = Ssot::Lib::Common::SSOT_ROOT.join('aggregate-skills.rb')
      system('ruby', aggregate_script.to_s, platform_id.to_s)
      if $?.success?
        log "    ✓ Vendor skill aggregated"
        puts "    ✓ Vendor skill aggregated"
        vendor_file = Ssot::Lib::Common::BUILD_DIR.join(platform_id, 'skills', 'vendor', "#{platform_id}.md")
        if vendor_file.exist?
          install_path = base_path.join(platform_cfg[:skill_file])
          install_path.parent.mkpath
          FileUtils.cp(vendor_file, install_path)
          log "  ✓ Installed vendor skill to #{install_path}"
          puts "  ✓ Installed vendor skill to #{install_path}"
        else
          log_error "Vendor skill not generated: #{vendor_file}"
        end
      else
        log_error "Vendor skill aggregation failed"
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
      if install_cfg[:target_dir]
        target_subdir = Ssot::Lib::Common.expand_user_path(install_cfg[:target_dir])
        if platform_cfg[:type] == 'directory'
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
      else
        Ssot::Lib::Common.resolve_install_path(platform_cfg, target, project_root)
      end
    end

    # ─── Logging ────────────────────────────────────────────────────────────────

    def log(msg, level: :info)
      Ssot::Lib::Common.log(msg, level: level, log_file: Ssot::Lib::Common::LOG_PATH)
    end

    def log_error(msg)
      Ssot::Lib::Common.log_error(msg, log_file: Ssot::Lib::Common::LOG_PATH)
    end

    def log_warn(msg)
      Ssot::Lib::Common.log_warn(msg, log_file: Ssot::Lib::Common::LOG_PATH)
    end

    def log_debug(msg)
      Ssot::Lib::Common.log_debug(msg, log_file: Ssot::Lib::Common::LOG_PATH)
    end
  end
end
