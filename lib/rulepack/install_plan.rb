# frozen_string_literal: true

# Install Plan — Decision-making and pre-execution logic for package installation.
#
# Extracted from installer.rb (P-A: split 822 LOC installer into focused modules).
# Responsibilities:
#   - Per-package install vs skip decision (version comparison, --needed, --select)
#   - Index record management (ensure_package_in_index, EXCLUDE_KEYS)
#   - Platform/path resolution helpers
#   - Vendor-skill presence check

require 'pathname'
require_relative 'common'

module Rulepack
  module InstallPlan
    module_function

    # ─── Platform / path resolution ────────────────────────────────────────────────

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

    # ─── Version comparison and install decision ───────────────────────────────────

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
          uninstall_single_package_from_index!(ctx.index, pkgname, ctx.platform_id, project_root: ctx.project_root, ctx: ctx) unless ctx.dry_run
          true
        elsif !ctx.select_list && has_skill_bundle
          ver = Rulepack::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])
          Rulepack::Common.log "  🔄 Restoring #{pkgname} #{ver} all sub-skills"
          uninstall_single_package_from_index!(ctx.index, pkgname, ctx.platform_id, project_root: ctx.project_root, ctx: ctx) unless ctx.dry_run
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
        uninstall_single_package_from_index!(ctx.index, pkgname, ctx.platform_id, project_root: ctx.project_root, ctx: ctx) unless ctx.dry_run
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
        uninstall_single_package_from_index!(ctx.index, pkgname, ctx.platform_id, project_root: ctx.project_root, ctx: ctx) unless ctx.dry_run
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

    # ─── Index management ─────────────────────────────────────────────────────────

    EXCLUDE_KEYS = [:installed, :source_dir, :source_sha256].freeze

    def ensure_package_in_index(index, pkgname, pkgdata, dry_run: false)
      return if dry_run
      pkg_index = index[:packages][pkgname] ||= {}
      pkg_index[:installed] ||= []
      pkg_index.merge!(pkgdata.reject { |k, _| EXCLUDE_KEYS.include?(k) })
    end

    # ─── Vendor skill presence check ──────────────────────────────────────────────

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

    # ─── Uninstall helper ─────────────────────────────────────────────────────────

    def uninstall_single_package_from_index!(index, pkgname, platform_id, project_root: nil, ctx: nil)
      Rulepack::InstallHelpers.uninstall_packages(index, platform_id, dry_run: false,
                                                                   project_root: project_root,
                                                                   specific_packages: [pkgname],
                                                                   ctx: ctx).include?(pkgname)
    end

    # ─── Platform config helper ───────────────────────────────────────────────────

    def platform_cfg_for(platform_id)
      registry = Rulepack::Common.load_platform_registry
      Rulepack::Common.platform_config(platform_id, registry)
    rescue StandardError => e
      raise ArgumentError, "Unknown or misconfigured platform: #{platform_id} (#{e.class}: #{e.message})"
    end

    # ─── Project root helper ──────────────────────────────────────────────────────

    def project_root_for(platform_cfg, project_arg)
      Rulepack::Common.project_root_for(platform_cfg, project_arg)
    end
  end
end
