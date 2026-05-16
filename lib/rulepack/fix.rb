#!/usr/bin/env ruby
# frozen_string_literal: true

# Fix drift between Rulepack index and disk
# Runs verify, then repairs missing/checksum errors via reinstall.
# Usage: ruby lib/rulepack/fix.rb [platform] [--dry-run] [--auto]

require 'English'
require 'pathname'
require 'fileutils'
require 'set'
require_relative 'common'
require_relative 'installer'



def main
  platform_arg = ARGV.first
  dry_run = ARGV.include?('--dry-run')
  auto_mode = ARGV.include?('--auto')

  unless Rulepack::Common::BUILD_INDEX_PATH.exist?
    abort 'Build index not found. Run `ruby lib/rulepack/build.rb` first.'
  end

  platforms = if platform_arg && !platform_arg.start_with?('--')
                [platform_arg]
              else
                all_platforms_from_index
              end

  if platforms.empty?
    puts 'No platforms to fix.'
    exit 0
  end

  fixed_anything = false

  platforms.each do |platform_id|
    fixed_anything |= fix_platform(platform_id, dry_run, auto_mode)
  end

  if fixed_anything
    puts "\n✅ Fix applied. Run `ruby lib/rulepack/verify.rb` to confirm."
  else
    puts "\nℹ No fixes needed."
  end
  exit 0
end

def run_verify(platform_id)
  verify_path = Rulepack::Common::RULEPACK_ROOT.join('lib/rulepack/verify.rb')
  old_argv = ARGV.dup
  ARGV.replace([platform_id])
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

def fix_platform(platform_id, dry_run, auto_mode)
  puts "\n── #{platform_id} ──"

  cmd_out = run_verify(platform_id)
  # Re-print relevant lines
  cmd_out.each_line { |l| puts l if l =~ /[✓⚠?]/ }
  has_drift = cmd_out.include?('⚠') || cmd_out.include?('?')
  orphans = cmd_out.scan(/^\s*\?\s+ORPHAN:\s+(.+)$/).flatten

  unless has_drift || orphans.any?
    puts '  ✓ No drift detected.'
    return false
  end

  fixed_drift = fix_drift(platform_id, dry_run) if has_drift
  fixed_orphans = fix_orphans(orphans, dry_run, auto_mode)

  fixed_drift || fixed_orphans
end

def fix_drift(platform_id, dry_run)
  if dry_run
    puts "  [DRY-RUN] Would reinstall packages on #{platform_id}"
    return false
  end

  index = load_index
  broken = find_broken_packages(platform_id, index)
  broken.each do |pkgname|
    clear_installed_record(index, pkgname, platform_id)
    puts "  Cleared index record for #{pkgname}"
  end
  write_index(index)
  puts "  Reinstalling #{broken.size} package(s) on #{platform_id}..."
  install_path = Rulepack::Common::RULEPACK_ROOT.join('lib/rulepack/install.rb')
  old_argv = ARGV.dup
  ARGV.replace([platform_id])
  load install_path.to_s
  ARGV.replace(old_argv)
  puts '  ✓ Reinstall complete'
  true
rescue SystemExit => e
  ARGV.replace(old_argv)
  if e.status == 0
    puts '  ✓ Reinstall complete'
    true
  else
    puts '  ⚠ Reinstall failed'
    false
  end
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

def load_index
  Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
end

def write_index(index)
  index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  Rulepack::Common.write_yaml_atomic(Rulepack::Common::INDEX_YAML_PATH, index)
end

def clear_installed_record(index, pkgname, platform_id)
  pkgdata = index[:packages][pkgname]
  return unless pkgdata

  pkgdata[:installed]&.reject! { |r| r[:platform] == platform_id }
end

def find_broken_packages(platform_id, index)
  platform_cfg = Rulepack::Common.platform_config(platform_id, Rulepack::Common.load_platform_registry)
  return [] unless platform_cfg

  base_path = resolve_base_path(platform_cfg)
  broken = []

  (index[:packages] || {}).each do |pkgname, pkgdata|
    inst = pkgdata[:installed]&.find { |i| i[:platform] == platform_id }
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
                  !installed_path.exist? || Digest::SHA256.hexdigest(installed_path.read) != inst[:checksum]
                end

    broken << pkgname if is_broken
  end

  broken
end

def resolve_base_path(platform_cfg)
  project_root = Rulepack::Common.project_root_for(platform_cfg, nil)
  return project_root if project_root

  Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
end

def resolve_install_path(platform_cfg, target, base_path)
  if target
    Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
  else
    base_path
  end
end

def all_platforms_from_index
  index_path = Rulepack::Common::INDEX_YAML_PATH
  return [] unless index_path.exist?

  index = Rulepack::Common.load_yaml(index_path)
  platforms = Set.new
  (index[:packages] || {}).each_value do |pkg|
    (pkg[:installed] || []).each { |i| platforms << i[:platform] }
  end
  platforms.to_a
end

main
