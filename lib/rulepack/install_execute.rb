# frozen_string_literal: true

# Install Execute — Low-level install execution, verification, and vendor aggregation.
#
# Extracted from installer.rb (P-A: split 822 LOC installer into focused modules).
# Requires install_plan.rb for plan-level delegates (InstallPlan.*).

require 'English'
require 'digest'
require 'json'
require_relative 'common'
require_relative 'install_plan'
require_relative 'lib/transaction'
require_relative 'lib/install_handlers'
require_relative 'lib/skill_bundle'
require_relative 'aggregate'

module Rulepack
  module InstallExecute
    module_function

    # ─── Install a single platform ────────────────────────────────────────────────
    # Returns Set of installed package names for this run.

    def install_platform(ctx, specific_package: nil)
      ctx.platform_id = ctx.platform_id.to_s
      ctx.platform_cfg = InstallPlan.platform_cfg_for(ctx.platform_id)
      InstallPlan.warn_prerequisites(ctx.platform_id, ctx.platform_cfg, ctx.quiet)

      ctx.base_path = InstallPlan.resolve_install_base_path(ctx.platform_cfg, ctx.project_root)
      Rulepack::Common.log "📁 Base path: #{ctx.base_path}" unless ctx.quiet
      Rulepack::Common.log "  Platform type: #{ctx.platform_cfg[:type]}" unless ctx.quiet

      ctx.build_index[:packages].each do |pkgname, pkgdata|
        next if specific_package && pkgname.to_s != specific_package.to_s

        targets = InstallPlan.filter_targets_for_platform(pkgdata, ctx.platform_id)
        if targets.empty?
          Rulepack::Common.log "  ⊘ package '#{pkgname}': no target for #{ctx.platform_id}, skipping" unless ctx.quiet
          next
        end

        next unless InstallPlan.should_install_or_upgrade?(pkgname, pkgdata, ctx)

        InstallPlan.ensure_package_in_index(ctx.index, pkgname, pkgdata)

        targets.each do |target|
          install_single_target(pkgname, pkgdata, target, ctx)
        end
      end

      if ctx.platform_cfg[:type] == 'skill' && !ctx.dry_run
        aggregate_vendor_skills(ctx.platform_id, ctx.platform_cfg, ctx.base_path, ctx)
      end

      ctx.installed_this_run
    end

    # ─── Platform check ───────────────────────────────────────────────────────────

    def check_platform(platform_id, project_arg: nil)
      platform_id = platform_id.to_s
      Rulepack::Common.log "🔍 Checking installed state for platform: #{platform_id}"
      puts "🔍 Checking installed state for platform: #{platform_id}"

      unless Rulepack::Common.index_yaml_path.exist?
        Rulepack::Common.log_error 'index.yaml not found. Run build first.'
        raise 'index.yaml not found'
      end

      index = Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
      platform_cfg = InstallPlan.platform_cfg_for(platform_id)
      InstallPlan.warn_prerequisites(platform_id, platform_cfg, false)

      base_path = InstallPlan.resolve_install_base_path(platform_cfg, project_arg)

      # Skill-type platforms: check vendor skill file only
      InstallPlan.check_vendor_skill_present(platform_cfg, base_path) if platform_cfg[:type] == 'skill'

      errors = []
      index[:packages].each do |pkgname, pkgdata|
        inst = pkgdata[:installed].find { |i| i[:platform] == platform_id }
        next unless inst

        error = verify_package_on_disk(pkgname, pkgdata, inst, platform_id, platform_cfg, base_path)
        errors << error if error
      end

      report_check_results(errors)
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
      built_path = Rulepack::Common.build_dir.join(platform_id, pkgname.to_s, output)
      unless built_path.exist?
        Rulepack::Common.log_error "Built artifact missing: #{built_path}. Run `ruby lib/rulepack/build.rb` first."
        return
      end

      # Agent format: built_path is a directory, compute sha256 from manifest or skip
      if built_path.directory?
        content = nil
        content_sha256 = Digest::SHA256.hexdigest(built_path.to_s)
      else
        content = built_path.read
        content_sha256 = Digest::SHA256.hexdigest(content)
      end

      # Skill-type platforms: record only, aggregation handles file install
      if platform_cfg[:type] == 'skill'
        record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256, format: 'skill') unless dry_run
        Rulepack::Common.log "  ✓ Installed: #{pkgname}" unless quiet
        installed_this_run << pkgname
        return
      end

      install_cfg = target[:install] || {}
      format = target[:format]

      # format: agent → install to agents_dir (skip if platform doesn't support agents)
      if format == 'agent'
        agents_dir = platform_cfg[:agents_dir]
        if agents_dir.nil?
          Rulepack::Common.log "  ⊘ package '#{pkgname}': no agent support on #{platform_id}, skipping" unless quiet
          return
        end
        target_dir = install_cfg&.[](:target_dir) || pkgname.to_s
        install_path = base_path.join(agents_dir, target_dir)
        unless dry_run
          install_path.mkpath
          FileUtils.cp_r(built_path.to_s + '/.', install_path.to_s, preserve: false)
        end
        Rulepack::Common.log "  ⤷ #{pkgname} (agent) → #{install_path} [copy]" unless quiet
        record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256, format: 'agent') unless dry_run
        Rulepack::Common.log "  ✓ Installed agent: #{pkgname}" unless quiet
        installed_this_run << pkgname
        return
      end

      default_install_cfg = if %w[skill skill-bundle].include?(format)
                              platform_cfg[:skill_install]
                            else
                              platform_cfg[:rule_install]
                            end
      # --rules-to rules_file: redirect rules to platform's rules_file via append
      if ctx.rules_to == 'rules_file' && !%w[skill skill-bundle].include?(format) && platform_cfg[:rules_file]
        install_type = 'append'
        install_path = base_path.join(platform_cfg[:rules_file])
      else
        install_type = install_cfg[:type] || default_install_cfg&.[](:type) || 'copy'
        install_path = Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
      end

      install_path.parent.mkpath unless dry_run

      Rulepack::Common.log "  ⤷ #{pkgname} (#{output}) → #{install_path} [#{install_type}]" unless quiet
      Rulepack::InstallHandlers.perform_file_install(
        built_path, install_path, content, content_sha256, install_type,
        platform_cfg, output, pkgname, ctx
      )

      record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256, format: format, install_path: install_path) unless dry_run
      Rulepack::Common.log "  ✓ Installed: #{pkgname}" unless quiet
      installed_this_run << pkgname
    end

    # ─── Record installation in index ─────────────────────────────────────────────

    def record_installation(index, pkgname, platform_id, pkgdata, output, checksum, format: nil, install_path: nil)
      pkg_index = index[:packages][pkgname] || { installed: [] }
      pkg_index[:installed] ||= []
      record = {
        platform: platform_id,
        version: pkgdata[:pkgver],
        pkgrel: pkgdata[:pkgrel],
        epoch: pkgdata[:epoch],
        output: output,
        checksum: checksum,
        format: format,
        target_path: install_path ? install_path.to_s : nil,
        installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      }
      if output == '.'
        pkg_index[:installed].reject! { |r| r[:platform] == platform_id }
      else
        pkg_index[:installed].reject! { |r| r[:platform] == platform_id && r[:output] == output }
      end
      pkg_index[:installed] << record
    end

    # ─── Verify on-disk state ────────────────────────────────────────────────────

    def verify_package_on_disk(pkgname, pkgdata, inst, platform_id, platform_cfg, base_path)
      expected_output = inst[:output]
      expected_checksum = inst[:checksum]
      target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
      format_type = inst[:format] || (target ? target[:format] : 'directory')

      if format_type == 'skill' && platform_cfg[:type] == 'skill'
        build_artifact = Rulepack::Common.build_dir.join(platform_id, pkgname.to_s, expected_output)
        return "Build artifact missing: #{pkgname} (#{build_artifact})" unless build_artifact.exist?

        actual_sha = Digest::SHA256.hexdigest(build_artifact.read)
        return nil if actual_sha == expected_checksum

        return "Build artifact checksum mismatch: #{pkgname}"
      elsif format_type == 'agent'
        agents_dir = platform_cfg[:agents_dir]
        return nil unless agents_dir
        target_dir = (target[:install] && target[:install][:target_dir]) || expected_output || pkgname.to_s
        agent_path = base_path.join(agents_dir, target_dir)
        return "Missing agent: #{pkgname} at #{agent_path}" unless agent_path.exist?
        Rulepack::Common.log "  ✓ #{pkgname} (agent)"
        return nil
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

    # ─── Vendor skill aggregation ─────────────────────────────────────────────────

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
        vendor_file = Rulepack::Common.build_dir.join(platform_id, 'skills', 'vendor',
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
  end
end
