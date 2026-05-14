#!/usr/bin/env ruby
# frozen_string_literal: true

# Uninstall packages from a platform
# Usage: ruby ssot/uninstall.rb <platform> [--dry-run]

require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require_relative 'lib/common'

SSOT_ROOT = Pathname.new(__dir__).expand_path
BUILD_DIR = SSOT_ROOT.join('build')
INDEX_YAML_PATH = SSOT_ROOT.join('index.yaml')
LOG_PATH = BUILD_DIR.join('uninstall.log')

def log(msg)
  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
  line = "[#{timestamp}] #{msg}"
  puts line
  FileUtils.mkpath(BUILD_DIR)
  File.open(LOG_PATH, 'a') { |f| f.puts(line) }
end

def log_error(msg)
  warn "❌ #{msg}"
  log("ERROR: #{msg}")
end

def project_root_for(platform_id, platform_cfg, project_arg)
  scope = platform_cfg[:scope] || 'user'
  if scope == 'project'
    if project_arg
      Pathname.new(project_arg).expand_path
    else
      Pathname.pwd
    end
  else
    nil
  end
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
  puts "Usage: ruby ssot/uninstall.rb <platform> [--dry-run] [--project PATH]"
  puts "  <platform>  Target platform (opencode, cursor, etc.)"
  puts "  --dry-run   Show what would be removed, don't modify filesystem"
  puts "  --project   Project root (required for project-level platforms)"
  exit 1
end

platform_id = platform_arg
log "🧹 Uninstalling packages from platform: #{platform_id} #{dry_run ? '(dry-run)' : ''}"
puts "🧹 Uninstalling packages from platform: #{platform_id} #{dry_run ? '(dry-run)' : ''}"

# Load index
unless INDEX_YAML_PATH.exist?
  log_error "Index not found: #{INDEX_YAML_PATH}. Run build first."
  exit 1
end

 index = Ssot::Lib::Common.load_yaml(INDEX_YAML_PATH)
 # Migrate old index records to include pkgrel/epoch if missing
 (index[:packages] || {}).each_value { |pkg_idx| Ssot::Lib::Common.migrate_installed_records(pkg_idx) }
 platform_cfg = Ssot::Lib::Common.platform_config(platform_id, Ssot::Lib::Common.load_platform_registry)

project_root = project_root_for(platform_id, platform_cfg, project_arg)
base_path = if project_root
              project_root
            else
              Pathname.new(Ssot::Lib::Common.expand_user_path(platform_cfg[:base_path]))
            end

log "📁 Base path: #{base_path}"
log "  Platform type: #{platform_cfg[:type]}"

# Special handling for skill-based platforms: remove aggregated vendor skill
if platform_cfg[:type] == 'skill'
  log "  🎯 Skill platform: removing vendor skill"
  vendor_path = base_path.join(platform_cfg[:skill_file])
  if vendor_path.exist?
    if dry_run
      log "    [DRY-RUN] Would remove vendor skill: #{vendor_path}"
    else
      FileUtils.rm(vendor_path)
      log "    ✓ Removed vendor skill"
    end
  else
    log "    ℹ Vendor skill not found (already removed?)"
  end

  # Clean installed records for this platform from index
  unless dry_run
    index = Ssot::Lib::Common.load_yaml(INDEX_YAML_PATH)
    index[:packages].each do |pkgname, pkgdata|
      if pkgdata[:installed]&.any? { |i| i[:platform] == platform_id }
        pkgdata[:installed].reject! { |i| i[:platform] == platform_id }
      end
    end
    Ssot::Lib::Common.write_yaml_atomic(INDEX_YAML_PATH, index)
    log "📝 Index cleaned for #{platform_id}"
  end
  exit 0
end

# Find all installed packages for this platform
installed_pkgs = index[:packages].select { |_, pkg| pkg[:installed]&.any? { |i| i[:platform] == platform_id } }

if installed_pkgs.empty?
  log "  No packages installed on #{platform_id}."
  puts "  No packages installed on #{platform_id}."
  exit 0
end

# Uninstall all packages using common function
uninstalled = Ssot::Lib::Common.uninstall_packages(index, platform_id, dry_run: dry_run, project_root: project_root)

# For skill-based platforms: re-aggregate vendor skills after removals
if platform_cfg[:type] == 'skill' && !dry_run
  log "  🧱 Re-aggregating vendor skills for #{platform_id}..."
  puts "\n  🧱 Re-aggregating vendor skills for #{platform_id}..."
  system("ruby", "ssot/aggregate-skills.rb", platform_id.to_s)
  if $?.success?
    log "    ✓ Vendor skill regenerated"
    puts "    ✓ Vendor skill regenerated"
  else
    log_error "Vendor skill aggregation failed"
  end
end

# Write updated index
unless dry_run
  begin
    index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    Ssot::Lib::Common.write_yaml_atomic(INDEX_YAML_PATH, index)
    log "📝 Index updated: #{INDEX_YAML_PATH}"
    puts "\n📝 Index updated: #{INDEX_YAML_PATH}"
  rescue => e
    log_error "Failed to write index: #{e.message}"
    exit 1
  end
else
  log "[DRY-RUN] Index write skipped"
  puts "\n[DRY-RUN] Index write skipped"
end

if uninstalled.empty?
  log "  No packages were uninstalled."
else
  log "✅ Uninstall complete. #{uninstalled.size} package(s):"
  uninstalled.uniq.each { |p| log "   • #{p}" }
end

# End of file
