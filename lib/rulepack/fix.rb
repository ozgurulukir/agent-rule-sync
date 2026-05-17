#!/usr/bin/env ruby
# frozen_string_literal: true

# Fix drift between Rulepack index and disk
# Runs verify, then repairs missing/checksum errors via reinstall.
#
# Usage:
#   ruby lib/rulepack/fix.rb [package_name] --target <platform|all> [--project PATH] [--dry-run] [--auto]
#   ruby lib/rulepack/fix.rb [package_name] -t <platform|all> [-p PATH] [--dry-run] [--auto]
#
# Kısayol (Pacman Mimicry):
#   ruby lib/rulepack/fix.rb -F [package_name] --target <platform|all>

require 'pathname'
require 'fileutils'
require 'set'
require 'stringio'
require_relative 'common'
require_relative 'installer'

# Gracefully shift pacman -F flag if passed as first argument
ARGV.shift if ARGV.first == '-F'

# ─── Parse arguments ────────────────────────────────────────────────────────────

dry_run = ARGV.include?('--dry-run')
auto_mode = ARGV.include?('--auto')

positional_args = []
project_arg = nil
target_arg = nil

i = 0
while i < ARGV.length
  arg = ARGV[i]
  case arg
  when '--dry-run', '--auto'
    i += 1 # already parsed
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
  abort "❌ Error: Too many positional arguments. Usage: ruby fix.rb [package_name] --target <platform|all>"
end

package_arg = positional_args.first

# ─── Load master index and platform registry ───────────────────────────────────

unless Rulepack::Common::BUILD_INDEX_PATH.exist?
  abort '❌ Error: Build index not found. Run `ruby lib/rulepack/build.rb` first.'
end

unless Rulepack::Common::INDEX_YAML_PATH.exist?
  abort "❌ Error: Installed index not found at #{Rulepack::Common::INDEX_YAML_PATH}. Nothing is installed."
end

index = Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
packages = index[:packages] || {}
registry = Rulepack::Common.load_platform_registry

# ─── Exact package validation ──────────────────────────────────────────────────

target_package = nil
if package_arg
  unless packages.key?(package_arg) || packages.key?(package_arg.to_sym)
    abort "❌ Error: Package '#{package_arg}' is not registered as installed in index."
  end
  target_package = packages.keys.find { |k| k.to_s == package_arg }.to_s
end

# ─── Target platform checks (MANDATORY) ────────────────────────────────────────

unless target_arg
  abort "❌ Error: Please specify target platform(s) with --target <platform> (or --target all)."
end

targets_to_fix = []
if target_arg.downcase == 'all'
  if target_package
    pkg_idx = packages[target_package.to_sym] || packages[target_package.to_s] || {}
    targets_to_fix = (pkg_idx[:installed] || []).map { |i| i[:platform] }.uniq
  else
    platforms = Set.new
    packages.each_value do |pkg|
      (pkg[:installed] || []).each { |i| platforms << i[:platform] }
    end
    targets_to_fix = platforms.to_a
  end
else
  targets_to_fix = target_arg.split(',').map(&:strip).reject(&:empty?)
end

if targets_to_fix.empty?
  puts "  No targets to fix."
  exit 0
end

# Validate targets
targets_to_fix.each do |p|
  unless registry.key?(p.to_sym) || registry.key?(p.to_s)
    abort "❌ Error: Unknown target platform '#{p}'."
  end

  cfg = registry[p.to_sym] || registry[p.to_s]
  if cfg[:scope] == 'project' && !project_arg
    abort "❌ Error: Platform '#{cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>."
  end
end

# ─── Execution Helpers ─────────────────────────────────────────────────────────

def run_verify(platform_id, package_arg, project_arg)
  verify_path = Rulepack::Common::RULEPACK_ROOT.join('lib/rulepack/verify.rb')
  old_argv = ARGV.dup
  new_argv = ["--target", platform_id]
  new_argv << package_arg if package_arg
  new_argv << "--project" << project_arg if project_arg
  ARGV.replace(new_argv)
  out = StringIO.new
  $stdout = out
  load verify_path.to_s
  out.string
rescue SystemExit
  out.string
ensure
  $stdout = STDOUT
  ARGV.replace(old_argv)
end

def fix_platform(platform_id, package_arg, project_arg, dry_run, auto_mode)
  puts "\n── #{platform_id} ──"

  cmd_out = run_verify(platform_id, package_arg, project_arg)
  # Re-print relevant lines
  cmd_out.each_line { |l| puts l if l =~ /[✓⚠?]/ }
  has_drift = cmd_out.include?('⚠')
  orphans = cmd_out.scan(/^\s*\?\s+ORPHAN:\s+(.+)$/).flatten

  unless has_drift || orphans.any?
    puts '  ✓ No drift detected.'
    return false
  end

  fixed_drift = false
  if has_drift
    fixed_drift = fix_drift(platform_id, package_arg, project_arg, dry_run)
  end

  fixed_orphans = false
  if orphans.any? && package_arg.nil? # Only clean orphans if verifying entire platform
    fixed_orphans = fix_orphans(orphans, dry_run, auto_mode)
  end

  fixed_drift || fixed_orphans
end

def fix_drift(platform_id, package_arg, project_arg, dry_run)
  if dry_run
    puts "  [DRY-RUN] Would reinstall packages on #{platform_id}"
    return false
  end

  index = Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
  broken = find_broken_packages(platform_id, package_arg, project_arg, index)
  
  if broken.empty?
    puts '  ✓ No broken packages matched.'
    return false
  end

  broken.each do |pkgname|
    clear_installed_record(index, pkgname, platform_id)
    puts "  Cleared index record for #{pkgname}"
  end
  
  index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  Rulepack::Common.write_yaml_atomic(Rulepack::Common::INDEX_YAML_PATH, index)
  
  puts "  Reinstalling #{broken.size} package(s) on #{platform_id}..."
  install_path = Rulepack::Common::RULEPACK_ROOT.join('lib/rulepack/install.rb')
  old_argv = ARGV.dup
  
  broken.each do |pkgname|
    new_argv = [pkgname, "--target", platform_id]
    new_argv << "--project" << project_arg if project_arg
    ARGV.replace(new_argv)
    begin
      load install_path.to_s
    rescue SystemExit => e
      if e.status != 0
        puts "  ⚠ Reinstall failed for #{pkgname}"
      end
    end
  end
  
  ARGV.replace(old_argv)
  puts '  ✓ Reinstall complete'
  true
end

def fix_orphans(orphans, dry_run, auto_mode)
  return false unless orphans.any?

  puts "\n  #{orphans.size} orphan(s) found:"
  orphans.each { |f| puts "    #{f}" }
  if dry_run
    puts '  [DRY-RUN] Would not remove orphans'
    false
  elsif auto_mode
    puts "  Removing #{orphans.size} orphan(s)..."
    orphans.each { |f| FileUtils.rm_rf(f) }
    puts '  ✓ Orphans removed'
    true
  else
    puts '  Skipping orphan removal (use --auto to remove)'
    false
  end
end

def clear_installed_record(index, pkgname, platform_id)
  pkgdata = index[:packages][pkgname.to_sym] || index[:packages][pkgname.to_s]
  return unless pkgdata
  return unless pkgdata[:installed].is_a?(Array)

  pkgdata[:installed].reject! { |r| r[:platform] == platform_id }
end

def find_broken_packages(platform_id, package_arg, project_arg, index)
  platform_cfg = Rulepack::Common.platform_config(platform_id, Rulepack::Common.load_platform_registry)
  return [] unless platform_cfg

  project_root = project_arg ? Pathname.new(project_arg).expand_path : nil
  base_path = project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
  broken = []

  (index[:packages] || {}).each do |pkgname, pkgdata|
    next if package_arg && pkgname.to_s != package_arg
    inst = pkgdata[:installed].is_a?(Array) && pkgdata[:installed].find { |i| i[:platform] == platform_id }
    next unless inst

    target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
    format_type = target ? target[:format] : 'directory'

    is_broken = if format_type == 'skill-bundle'
                  bundle_path = resolve_install_path(platform_cfg, target, base_path)
                  !bundle_path.exist?
                elsif format_type == 'skill' && platform_cfg[:type] == 'skill'
                  !Rulepack::Common::BUILD_DIR.join(platform_id, inst[:output]).exist?
                else
                  installed_path = resolve_install_path(platform_cfg, target, base_path)
                  !installed_path.exist? || !Rulepack::Common.verify_checksum(installed_path, inst[:checksum], pkgname.to_s)
                end

    broken << pkgname.to_s if is_broken
  end

  broken
end

def resolve_install_path(platform_cfg, target, base_path)
  if target
    Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
  else
    base_path
  end
end

# ─── Main loop ─────────────────────────────────────────────────────────────────

fixed_anything = false
targets_to_fix.each do |platform_id|
  fixed_anything |= fix_platform(platform_id, target_package, project_arg, dry_run, auto_mode)
end

if fixed_anything
  puts "\n✅ Fix applied. Run `ruby lib/rulepack/verify.rb` to confirm."
else
  puts "\nℹ No fixes needed."
end
exit 0
