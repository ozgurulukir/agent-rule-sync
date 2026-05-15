#!/usr/bin/env ruby
# frozen_string_literal: true

# Uninstall packages from a platform
# Usage: ruby lib/rulepack/uninstall.rb <platform> [--dry-run]

require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require_relative 'common'

RULEPACK_ROOT = Pathname.new(__dir__).parent.parent.expand_path
BUILD_DIR = RULEPACK_ROOT.join('build')
INDEX_YAML_PATH = RULEPACK_ROOT.join('data', 'index.yaml')
LOG_PATH = BUILD_DIR.join('uninstall.log')
Rulepack::Common.set_log_file(LOG_PATH)

def project_root_for(platform_id, platform_cfg, project_arg)
  Rulepack::Common.project_root_for(platform_cfg, project_arg)
end

# Parse args
dry_run = false
platform_arg = nil
project_arg = nil

i = 0
while i < ARGV.length
  arg = ARGV[i]
  case arg
  when '--dry-run'
    dry_run = true
    i += 1
  when '--project'
    if i + 1 >= ARGV.length
      raise "Missing path for --project"
    end
    project_arg = ARGV[i + 1]
    i += 2
  else
    platform_arg = arg
    i += 1
  end
end

unless platform_arg
  puts "Usage: ruby lib/rulepack/uninstall.rb <platform> [--dry-run] [--project PATH]"
  puts "  <platform>  Target platform (opencode, cursor, etc.)"
  puts "  --dry-run   Show what would be removed, don't modify filesystem"
  puts "  --project   Project root (required for project-level platforms)"
  exit 1
end

platform_id = platform_arg
Rulepack::Common.log "🧹 Uninstalling packages from platform: #{platform_id} #{dry_run ? '(dry-run)' : ''}"
puts "🧹 Uninstalling packages from platform: #{platform_id} #{dry_run ? '(dry-run)' : ''}"

# Load index
unless INDEX_YAML_PATH.exist?
  Rulepack::Common.log_error "Index not found: #{INDEX_YAML_PATH}. Run `ruby lib/rulepack/build.rb` first."
  exit 1
end

 index = Rulepack::Common.load_yaml(INDEX_YAML_PATH)
 # Migrate old index records to include pkgrel/epoch if missing
 (index[:packages] || {}).each_value { |pkg_idx| Rulepack::Common.migrate_installed_records(pkg_idx) }
 platform_cfg = Rulepack::Common.platform_config(platform_id, Rulepack::Common.load_platform_registry)

project_root = project_root_for(platform_id, platform_cfg, project_arg)
base_path = if project_root
              project_root
            else
              Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
            end

Rulepack::Common.log "📁 Base path: #{base_path}"
Rulepack::Common.log "  Platform type: #{platform_cfg[:type]}"

# Special handling for skill-based platforms: remove aggregated vendor skill
if platform_cfg[:type] == 'skill'
  Rulepack::Common.log "  🎯 Skill platform: removing vendor skill"
  vendor_path = base_path.join(platform_cfg[:skill_file])
  if vendor_path.exist?
    if dry_run
      Rulepack::Common.log "    [DRY-RUN] Would remove vendor skill: #{vendor_path}"
    else
      FileUtils.rm(vendor_path)
      Rulepack::Common.log "    ✓ Removed vendor skill"
    end
  else
    Rulepack::Common.log "    ℹ Vendor skill not found (already removed?)"
  end
end

# Find all installed packages for this platform
installed_pkgs = index[:packages].select { |_, pkg| pkg[:installed]&.any? { |i| i[:platform] == platform_id } }

if installed_pkgs.empty?
  Rulepack::Common.log "  No packages installed on #{platform_id}."
  puts "  No packages installed on #{platform_id}."
  exit 0
end

# Uninstall all packages using common function
uninstalled = Rulepack::Common.uninstall_packages(index, platform_id, dry_run: dry_run, project_root: project_root)

# For skill-based platforms: re-aggregate vendor skills after removals
if platform_cfg[:type] == 'skill' && !dry_run
  Rulepack::Common.log "  🧱 Re-aggregating vendor skills for #{platform_id}..."
  puts "\n  🧱 Re-aggregating vendor skills for #{platform_id}..."
  system("ruby", "lib/rulepack/aggregate.rb", platform_id.to_s)
  if $?.success?
    Rulepack::Common.log "    ✓ Vendor skill regenerated"
    puts "    ✓ Vendor skill regenerated"
  else
    Rulepack::Common.log_error "Vendor skill aggregation failed"
  end
end

# Write updated index
unless dry_run
  begin
    index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    Rulepack::Common.write_yaml_atomic(INDEX_YAML_PATH, index)
    Rulepack::Common.log "📝 Index updated: #{INDEX_YAML_PATH}"
    puts "\n📝 Index updated: #{INDEX_YAML_PATH}"
  rescue => e
    Rulepack::Common.log_error "Failed to write index: #{e.message}"
    exit 1
  end
else
  Rulepack::Common.log "[DRY-RUN] Index write skipped"
  puts "\n[DRY-RUN] Index write skipped"
end

if uninstalled.empty?
  Rulepack::Common.log "  No packages were uninstalled."
else
  Rulepack::Common.log "✅ Uninstall complete. #{uninstalled.size} package(s):"
  uninstalled.uniq.each { |p| Rulepack::Common.log "   • #{p}" }
end
