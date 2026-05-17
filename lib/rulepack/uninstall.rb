#!/usr/bin/env ruby
# frozen_string_literal: true

# Uninstall CLI entry point
# Enforces Zero Assumptions, Data-Driven Execution, and Clean Separation of Concerns.
#
# Usage:
#   ruby lib/rulepack/uninstall.rb [package_name] --target <platform|all> [--project PATH] [options]
#   ruby lib/rulepack/uninstall.rb [package_name] -t <platform|all> [-p PATH] [options]
#
# Kısayol (Pacman Mimicry):
#   ruby lib/rulepack/uninstall.rb -R [package_name] --target <platform|all>

require 'pathname'
require 'fileutils'
require_relative 'common'
require_relative 'uninstaller'

LOG_PATH = Rulepack::Common::BUILD_DIR.join('uninstall.log')
Rulepack::Common.log_file = LOG_PATH

# Gracefully shift pacman -R flag if passed as first argument
ARGV.shift if ARGV.first == '-R'

# ─── Parse arguments ────────────────────────────────────────────────────────────

dry_run = false
positional_args = []
project_arg = nil
target_arg = nil

i = 0
while i < ARGV.length
  arg = ARGV[i]
  case arg
  when '--dry-run', '-p'
    dry_run = true
    i += 1
  when '--target', '-t'
    raise 'Missing value for --target' if i + 1 >= ARGV.length
    target_arg = ARGV[i + 1]
    i += 2
  when '--project'
    raise 'Missing path for --project' if i + 1 >= ARGV.length
    project_arg = ARGV[i + 1]
    i += 2
  else
    positional_args << arg
    i += 1
  end
end

if positional_args.size > 1
  abort "❌ Error: Too many positional arguments. Usage: ruby uninstall.rb [package_name] --target <platform|all>"
end

package_arg = positional_args.first

# ─── Load master index and platform registry ───────────────────────────────────

unless Rulepack::Common::INDEX_YAML_PATH.exist?
  abort "❌ Error: Installed index not found at #{Rulepack::Common::INDEX_YAML_PATH}. Nothing is installed."
end

index = Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
registry = Rulepack::Common.load_platform_registry

# ─── Exact package validation ──────────────────────────────────────────────────

target_package = nil
if package_arg
  unless index[:packages] && (index[:packages].key?(package_arg) || index[:packages].key?(package_arg.to_sym))
    abort "❌ Error: Package '#{package_arg}' is not registered as installed in index."
  end
  target_package = index[:packages].keys.find { |k| k.to_s == package_arg }.to_s
end

# ─── Target platform checks (MANDATORY) ────────────────────────────────────────

unless target_arg
  abort "❌ Error: Please specify target platform(s) with --target <platform> (or --target all)."
end

targets_to_uninstall = []
if target_arg.downcase == 'all'
  if target_package
    pkg_idx = index[:packages][target_package.to_sym] || index[:packages][target_package.to_s] || {}
    targets_to_uninstall = (pkg_idx[:installed] || []).map { |i| i[:platform] }.uniq
  else
    # Uninstall everything from all platforms
    platforms = Set.new
    (index[:packages] || {}).each_value do |pkg|
      (pkg[:installed] || []).each { |i| platforms << i[:platform] }
    end
    targets_to_uninstall = platforms.to_a
  end
else
  targets_to_uninstall = target_arg.split(',').map(&:strip).reject(&:empty?)
end

if targets_to_uninstall.empty?
  puts "  No target platforms to uninstall."
  exit 0
end

# Validate targets
targets_to_uninstall.each do |p|
  unless registry.key?(p.to_sym) || registry.key?(p.to_s)
    abort "❌ Error: Unknown target platform '#{p}'."
  end

  cfg = registry[p.to_sym] || registry[p.to_s]
  if cfg[:scope] == 'project' && !project_arg
    abort "❌ Error: Platform '#{cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>."
  end
end

# ─── Dispatch Uninstallation ───────────────────────────────────────────────────

backup_path = nil
unless dry_run
  backup_path = Rulepack::Common.backup_index
end

begin
  uninstalled_total = []

  targets_to_uninstall.each do |platform_id|
    Rulepack::Common.log "🧹 Uninstalling from platform: #{platform_id} #{'(dry-run)' if dry_run}"
    puts "🧹 Uninstalling from platform: #{platform_id} #{'(dry-run)' if dry_run}"

    platform_cfg = registry[platform_id.to_sym] || registry[platform_id.to_s]
    project_root = project_arg ? Pathname.new(project_arg).expand_path : nil
    base_path = project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))

    # Special handling for skill-based platforms: remove aggregated vendor skill
    if platform_cfg[:type] == 'skill' && !target_package
      Rulepack::Common.log '  🎯 Skill platform: removing vendor skill'
      vendor_path = base_path.join(platform_cfg[:skill_file])
      if vendor_path.exist?
        if dry_run
          Rulepack::Common.log "    [DRY-RUN] Would remove vendor skill: #{vendor_path}"
        else
          FileUtils.rm(vendor_path)
          Rulepack::Common.log '    ✓ Removed vendor skill'
        end
      end
    end

    specific_list = target_package ? [target_package] : nil
    uninstalled = Rulepack::Common.uninstall_packages(index, platform_id,
                                                      dry_run: dry_run,
                                                      project_root: project_root,
                                                      specific_packages: specific_list)
    uninstalled_total.concat(uninstalled)

    # For skill-based platforms: re-aggregate vendor skills after removals if not dry-run
    if platform_cfg[:type] == 'skill' && !dry_run
      Rulepack::Common.log "  🧱 Re-aggregating vendor skills for #{platform_id}..."
      agg_ok = begin
        old_argv = ARGV.dup
        ARGV.replace([platform_id.to_s])
        load Rulepack::Common::RULEPACK_ROOT.join('lib/rulepack/aggregate.rb').to_s
        ARGV.replace(old_argv)
        true
      rescue SystemExit
        ARGV.replace(old_argv)
        false
      end
      if agg_ok
        Rulepack::Common.log '    ✓ Vendor skill regenerated'
      end
    end
  end

  # Save updated index
  if dry_run
    Rulepack::Common.log '[DRY-RUN] Index write skipped'
    puts "\n[DRY-RUN] Index write skipped"
  else
    index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    Rulepack::Common.write_yaml_atomic(Rulepack::Common::INDEX_YAML_PATH, index)
    Rulepack::Common.log "📝 Index updated: #{Rulepack::Common::INDEX_YAML_PATH}"
    puts "\n📝 Index updated: #{Rulepack::Common::INDEX_YAML_PATH}"
  end

  if uninstalled_total.empty?
    puts '  No packages were uninstalled.'
  else
    puts "\n✅ Uninstall complete. #{uninstalled_total.uniq.size} package(s):"
    uninstalled_total.uniq.each { |p| puts "   • #{p}" }
  end

rescue StandardError => e
  if backup_path && Rulepack::Common.restore_index(backup_path)
    Rulepack::Common.log_error "Uninstall failed (#{e.message}). Index restored from backup."
    abort "❌ Uninstall failed. Index restored from backup: #{backup_path.basename}"
  else
    Rulepack::Common.log_error "Uninstall failed (#{e.message})."
    abort "❌ Uninstall failed: #{e.message}"
  end
ensure
  Rulepack::Common.cleanup_backups rescue nil
end
