# frozen_string_literal: true

# Install Execute — Low-level install execution, verification, and vendor aggregation.
#
# Extracted from installer.rb (P-A: split 822 LOC installer into focused modules).
# Requires install_plan.rb for plan-level delegates (InstallPlan.*).

require 'English'
require 'digest'
require_relative 'common'
require_relative 'security'
require_relative 'install_plan'
require_relative 'installed_state'
require_relative 'models/installed_record'
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
      Rulepack::Emitter.emit(:progress, message: "📁 Base path: #{ctx.base_path}") unless ctx.quiet
      Rulepack::Emitter.emit(:progress, message: "  Platform type: #{ctx.platform_cfg[:type]}") unless ctx.quiet

      ctx.build_index[:packages].each do |pkgname, pkgdata|
        next if specific_package && pkgname.to_s != specific_package.to_s

        targets = InstallPlan.filter_targets_for_platform(pkgdata, ctx.platform_id)
        if targets.empty?
          Rulepack::Emitter.emit(:progress, message: "  ⊘ package '#{pkgname}': no target for #{ctx.platform_id}, skipping") unless ctx.quiet
          next
        end

        next unless InstallPlan.should_install_or_upgrade?(pkgname, pkgdata, ctx)

        InstallPlan.ensure_package_in_index(ctx.index, pkgname, pkgdata, dry_run: ctx.dry_run)

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
      Rulepack::Emitter.emit(:progress, message: "🔍 Checking installed state for platform: #{platform_id}")

      index = Rulepack::InstalledIndex.load
      platform_cfg = InstallPlan.platform_cfg_for(platform_id)
      InstallPlan.warn_prerequisites(platform_id, platform_cfg, false)

      base_path = InstallPlan.resolve_install_base_path(platform_cfg, project_arg)

      # Skill-type platforms: check vendor skill file only
      InstallPlan.check_vendor_skill_present(platform_cfg, base_path) if platform_cfg[:type] == 'skill'

      errors = []
      index[:packages].each do |pkgname, pkgdata|
        inst = pkgdata[:installed].find { |i| i[:platform] == platform_id }
        next unless inst

        verdict = InstalledState.check(
          installed: inst, target: pkgdata[:targets]&.find { |t| t[:platform] == platform_id },
          platform_cfg: platform_cfg, pkgname: pkgname.to_s, base_path: base_path
        )
        error = verdict.to_error_s(pkgname.to_s, output: inst[:output])
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

    # ─── Failure recording ───────────────────────────────────────────────────────

    # Record a requested-but-skipped package so it reaches the install Result
    # (data[:failed_packages]) instead of living only in stderr narration.
    # `package` may be nil for platform-level skips (vendor aggregation).
    def record_failure(ctx, package, reason, message)
      (ctx.failures ||= []) << { package: package, reason: reason, message: message }
    end

    # ─── Agent lazy materialization (source-centric build) ───────────────────────

    # ADR-2026-07-29: the build does not materialize agent-format targets —
    # like skill-bundles, their tree is materialized lazily at install time.
    # Unlike skill-bundles this is a verbatim copy: the eager-built agent path
    # never applied Schema Engine or wrote a manifest, so materialization must
    # not either. The copy comes from the fetched, version-pinned git-sources
    # snapshot; symlinks are stripped as for any untrusted build source.
    def agent_source_dir(pkgdata)
      source_dir = pkgdata[:source_dir]
      return nil if source_dir.nil? || source_dir.to_s.empty?

      dir = Pathname.new(source_dir)
      dir = Rulepack::Common.paths.root.join(dir) if !dir.absolute? && !dir.exist?
      dir.directory? ? dir : nil
    end

    # Returns true when install may proceed (artifact present or materialized,
    # or a dry-run with source material available). Records a
    # :missing_built_artifact failure and returns false when nothing can be
    # installed. Dry-run never writes.
    def ensure_agent_artifact(pkgname, pkgdata, platform_id, built_path, ctx, dry_run:)
      return true if built_path.directory?

      source_dir = agent_source_dir(pkgdata)
      unless source_dir && pkgdata[:source_sha256]
        msg = "Built agent artifact missing for #{pkgname}: #{built_path} — no source material to materialize from. Run `rulepack build` first."
        Rulepack::Common.log_error msg
        record_failure(ctx, pkgname.to_s, :missing_built_artifact, msg)
        return false
      end
      return true if dry_run

      built_path.mkpath
      FileUtils.cp_r(File.join(source_dir.to_s, '.'), built_path.to_s)
      Rulepack::Security.strip_symlinks_in_tree(built_path, log_prefix: '⚠')
      true
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
      agent_format = target[:format] == 'agent'
      # agent-format targets materialize lazily (see ensure_agent_artifact);
      # the generic built-artifact gate below does not apply to them.
      unless agent_format || built_path.exist?
        Rulepack::Common.log_error "Built artifact missing: #{built_path}. Run `rulepack build` first."
        record_failure(ctx, pkgname.to_s, :missing_built_artifact,
                       "Built artifact missing for #{pkgname}: #{built_path}. Run `rulepack build` first.")
        return
      end

      # Directory builds (skill-bundle, agent): checksum is not used downstream
      # (verify skips agents; fix handles agent as existence-only). Keep nil.
      if built_path.directory? || agent_format
        content = nil
        content_sha256 = nil
      else
        content = built_path.read
        content_sha256 = Digest::SHA256.hexdigest(content)
      end

      # Skill-type platforms: record only, aggregation handles file install
      if platform_cfg[:type] == 'skill'
        record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256, format: 'skill') unless dry_run
        Rulepack::Emitter.emit(:progress, message: "  ✓ Installed: #{pkgname}") unless quiet
        installed_this_run << pkgname
        return
      end

      install_cfg = target[:install] || {}
      format = target[:format]

      # format: agent → install to agents_dir (skip if platform doesn't support agents)
      if format == 'agent'
        agents_dir = platform_cfg[:agents_dir]
        if agents_dir.nil?
          Rulepack::Emitter.emit(:progress, message: "  ⊘ package '#{pkgname}': no agent support on #{platform_id}, skipping") unless quiet
          return
        end
        target_dir = install_cfg&.[](:target_dir) || pkgname.to_s
        install_path = base_path.join(agents_dir, target_dir)
        return unless ensure_agent_artifact(pkgname, pkgdata, platform_id, built_path, ctx, dry_run: dry_run)
        unless dry_run
          install_path.mkpath
          FileUtils.cp_r(built_path.to_s + '/.', install_path.to_s, preserve: false)
          # Security: strip symlinks planted by an untrusted build source so they
          # cannot be followed by downstream agent tooling on the user's host.
          Rulepack::Security.strip_symlinks_in_tree(install_path, log_prefix: '⚠')
        end
        Rulepack::Emitter.emit(:progress, message: "  ⤷ #{pkgname} (agent) → #{install_path} [copy]") unless quiet
        record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256, format: 'agent') unless dry_run
        Rulepack::Emitter.emit(:progress, message: "  ✓ Installed agent: #{pkgname}") unless quiet
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

      Rulepack::Emitter.emit(:progress, message: "  ⤷ #{pkgname} (#{output}) → #{install_path} [#{install_type}]") unless quiet
      performed = Rulepack::InstallHandlers.perform_file_install(
        built_path, install_path, content, content_sha256, install_type,
        platform_cfg, output, pkgname, ctx
      )
      return if performed == false

      record_installation(index, pkgname, platform_id, pkgdata, output, content_sha256, format: format, install_path: install_path) unless dry_run
      Rulepack::Emitter.emit(:progress, message: "  ✓ Installed: #{pkgname}") unless quiet
      installed_this_run << pkgname
    end

    # ─── Record installation in index ─────────────────────────────────────────────

    def record_installation(index, pkgname, platform_id, pkgdata, output, checksum, format: nil, install_path: nil)
      pkg_index = index[:packages][pkgname] || { installed: [] }
      pkg_index[:installed] ||= []
      # InstalledRecord owns the installed-record schema (models/installed_record.rb).
      record = Rulepack::InstalledRecord.new(
        platform: platform_id,
        version: pkgdata[:pkgver],
        pkgrel: pkgdata[:pkgrel],
        epoch: pkgdata[:epoch],
        output: output,
        checksum: checksum,
        format: format,
        target_path: install_path ? install_path.to_s : nil,
        installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      ).to_h
      if output == '.'
        pkg_index[:installed].reject! { |r| r[:platform] == platform_id }
      else
        pkg_index[:installed].reject! { |r| r[:platform] == platform_id && r[:output] == output }
      end
      pkg_index[:installed] << record
    end

    def report_check_results(errors)
      if errors.empty?
        Rulepack::Emitter.emit(:progress, message: "\n✅ All installed packages are valid")
        Rulepack::Result.new(status: :success, data: { errors_count: 0 })
      else
        Rulepack::Common.log_error "#{errors.size} error(s) found"
        Rulepack::Emitter.emit(:progress, message: "\n❌ #{errors.size} error(s) found:")
        errors.each { |e| Rulepack::Emitter.emit(:progress, message: "  • #{e}") }
        Rulepack::Result.new(status: :failure, data: { errors_count: errors.size }, errors: errors)
      end
    end

    # ─── Vendor skill aggregation ─────────────────────────────────────────────────

    def aggregate_vendor_skills(platform_id, platform_cfg, base_path, ctx)
      collision_strategy = ctx.collision_strategy || 'interactive'
      Rulepack::Emitter.emit(:progress, message: "\n  🧱 Aggregating vendor skills for #{platform_id}...")
      agg_ok = begin
                 Rulepack::Aggregate.run({ target: platform_id })
                 true
               rescue StandardError => e
                 Rulepack::Common.log_error "Aggregation error: #{e.message}"
                 false
               end
      if agg_ok
        Rulepack::Emitter.emit(:progress, message: '    ✓ Vendor skill aggregated')
        vendor_file = Rulepack::Common.build_dir.join(platform_id, 'skills', 'vendor',
                                                       "#{platform_id}.md")
        if vendor_file.exist?
          install_path = base_path.join(platform_cfg[:skill_file])
          install_path.parent.mkpath

          if install_path.exist?
            effective_strategy = collision_strategy
            if effective_strategy == 'interactive'
              effective_strategy = Rulepack::Common.interactive_collision_prompt(install_path)
            end
            case effective_strategy
            when 'append'
              backup_path = Rulepack::Common.backup_file(install_path)
              Rulepack::Transaction.record_journal(ctx, { action: :modify_file, path: install_path, backup: backup_path })
              result = Rulepack::IO.update_marked_content(install_path, "#{platform_id}_vendor", vendor_file.read)
              Rulepack::Emitter.emit(:progress, message: "  ✓ #{result.capitalize} vendor skill to #{install_path} (with backup)")
            when 'overwrite'
              backup_path = Rulepack::Common.backup_file(install_path)
              Rulepack::Transaction.record_journal(ctx, { action: :replace_file, path: install_path, backup: backup_path })
              FileUtils.cp(vendor_file, install_path)
              Rulepack::Emitter.emit(:progress, message: "  ✓ Overwrote vendor skill to #{install_path} (with backup)")
            when 'ignore'
              Rulepack::Emitter.emit(:progress, message: "  ⚠ Collision: #{install_path} exists, skipping vendor skill install")
              record_failure(ctx, nil, :vendor_collision_skipped,
                             "Collision at #{install_path}; vendor skill skipped (--on-collision ignore)")
            else # stop
              Rulepack::Common.log_error "Collision detected: #{install_path} exists. Use --on-collision to proceed."
              Rulepack::Emitter.emit(:progress, message: "  ❌ Collision: #{install_path} exists. Use --on-collision to proceed.")
              raise Rulepack::StateError, "Collision at #{install_path}"
            end
          else
            Rulepack::Transaction.record_journal(ctx, { action: :create_file, path: install_path })
            FileUtils.cp(vendor_file, install_path)
            Rulepack::Emitter.emit(:progress, message: "  ✓ Installed vendor skill to #{install_path}")
          end
        else
          Rulepack::Common.log_error "Vendor skill not generated: #{vendor_file}"
          record_failure(ctx, nil, :vendor_skill_not_generated,
                         "Vendor skill not generated: #{vendor_file}")
        end
      else
        Rulepack::Common.log_error 'Vendor skill aggregation failed'
        record_failure(ctx, nil, :vendor_aggregation_failed, 'Vendor skill aggregation failed')
      end
    end
  end
end
