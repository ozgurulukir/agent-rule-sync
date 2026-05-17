#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify index vs disk state
# Compares Rulepack index (what should be installed) against actual files on disk.
# Reports: OK packages, drift (missing/modified), orphans (not in index).
# Exit code 0 = no drift, 1 = drift found.
#
# Usage:
#   ruby lib/rulepack/verify.rb [package_name] --target <platform|all> [--project PATH]
#   ruby lib/rulepack/verify.rb [package_name] -t <platform|all> [-p PATH]
#
# Kısayol (Pacman Mimicry):
#   ruby lib/rulepack/verify.rb -Qk [package_name] --target <platform|all>

require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require_relative 'common'
require_relative 'installer'

# Gracefully shift pacman -Qk flag if passed as first argument
ARGV.shift if ARGV.first == '-Qk'

# ─── Parse arguments ────────────────────────────────────────────────────────────

positional_args = []
project_arg = nil
target_arg = nil

i = 0
while i < ARGV.length
  arg = ARGV[i]
  case arg
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
  abort "❌ Error: Too many positional arguments. Usage: ruby verify.rb [package_name] --target <platform|all>"
end

package_arg = positional_args.first

# ─── Load master index and platform registry ───────────────────────────────────

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

targets_to_verify = []
if target_arg.downcase == 'all'
  if target_package
    pkg_idx = packages[target_package.to_sym] || packages[target_package.to_s] || {}
    targets_to_verify = (pkg_idx[:installed] || []).map { |i| i[:platform] }.uniq
  else
    platforms = Set.new
    packages.each_value do |pkg|
      (pkg[:installed] || []).each { |i| platforms << i[:platform] }
    end
    targets_to_verify = platforms.to_a
  end
else
  targets_to_verify = target_arg.split(',').map(&:strip).reject(&:empty?)
end

if targets_to_verify.empty?
  puts "  No targets to verify."
  exit 0
end

# Validate targets
targets_to_verify.each do |p|
  unless registry.key?(p.to_sym) || registry.key?(p.to_s)
    abort "❌ Error: Unknown target platform '#{p}'."
  end

  cfg = registry[p.to_sym] || registry[p.to_s]
  if cfg[:scope] == 'project' && !project_arg
    abort "❌ Error: Platform '#{cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>."
  end
end

# ─── Helper verification functions ─────────────────────────────────────────────

def resolve_base_path(platform_cfg, project_arg)
  project_root = Rulepack::Common.project_root_for(platform_cfg, project_arg)
  project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
end

def verify_single_file_on_disk(path, expected_checksum, pkgname, expected_output)
  unless path.exist?
    puts "  ⚠ MISSING: #{pkgname} (#{expected_output}) at #{path}"
    return :drift
  end
  if Rulepack::Common.verify_checksum(path, expected_checksum, pkgname)
    puts "  ✓ #{pkgname} (#{expected_output})"
    return :ok
  end
  puts "  ⚠ CHECKSUM mismatch: #{pkgname} (#{expected_output})"
  :drift
end

def verify_skill_build_artifact(platform_id, pkgname, expected_output, expected_checksum)
  build_artifact = Rulepack::Common::BUILD_DIR.join(platform_id, expected_output)
  unless build_artifact.exist?
    puts "  ⚠ MISSING build artifact: #{pkgname} (#{build_artifact})"
    return :drift
  end
  actual_sha = Digest::SHA256.hexdigest(build_artifact.read)
  if actual_sha == expected_checksum
    puts "  ✓ #{pkgname} (#{expected_output}) — build artifact OK"
    return :ok
  end
  puts "  ⚠ CHECKSUM mismatch (build artifact): #{pkgname}"
  :drift
end

def verify_skill_bundle_on_disk(bundle_path, pkgname)
  manifest_path = bundle_path.join('manifest.json')
  unless manifest_path.exist?
    puts "  ⚠ MISSING manifest: #{pkgname} at #{manifest_path}"
    return :drift
  end
  manifest = JSON.parse(manifest_path.read)
  all_ok = true
  (manifest['files'] || {}).each do |rel_path, expected_sha|
    file_path = bundle_path.join(rel_path)
    unless file_path.exist?
      puts "  ⚠ MISSING: #{pkgname}/#{rel_path}"
      all_ok = false
      next
    end
    actual_sha = Digest::SHA256.hexdigest(file_path.read)
    next if actual_sha == expected_sha

    puts "  ⚠ CHECKSUM mismatch: #{pkgname}/#{rel_path}"
    all_ok = false
  end
  if all_ok
    puts "  ✓ #{pkgname} (skill-bundle, #{manifest['files']&.size || 0} file(s))"
    return :ok
  end
  :drift
end

def scan_orphans(platform_id, platform_cfg, base_path, packages)
  orphans = []
  return orphans unless platform_cfg[:type] == 'directory'

  rules_dir = base_path.join(platform_cfg[:rules_dir] || '')
  skills_dir = base_path.join(platform_cfg[:skills_dir] || '')

  expected_top = Set.new
  packages.each_value do |pkgdata|
    (pkgdata[:installed] || []).each do |inst|
      next unless inst[:platform] == platform_id

      target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
      next unless target

      p = Rulepack::Install.resolve_check_path(platform_cfg, target, base_path, base_path)
      expected_top << p.to_s
    end
  end

  [rules_dir, skills_dir].each do |dir|
    next unless dir.exist?

    Dir.entries(dir).each do |entry|
      full = File.join(dir, entry)
      next if ['.', '..'].include?(entry)
      next if expected_top.include?(full)
      next if entry.start_with?('.')
      next if entry == 'manifest.json'
      next if File.directory?(full) && expected_top.any? { |e| e.start_with?("#{full}/") || e == full }

      orphans << full
    end
  end

  orphans.each { |orphan| puts "  ? ORPHAN: #{orphan}" }
  orphans
end

# ─── Execution ─────────────────────────────────────────────────────────────────

total_drifts = 0
total_orphans = 0
total_ok = 0
total_platforms = 0

targets_to_verify.each do |platform_id|
  platform_cfg = registry[platform_id.to_sym] || registry[platform_id.to_s]
  total_platforms += 1
  puts "\n── #{platform_id} (#{platform_cfg[:display_name]}) ──"

  base_path = resolve_base_path(platform_cfg, project_arg)
  
  # Select packages for this platform, optionally filtering by target_package
  platform_pkgs = packages.select do |name, pkg|
    next false if target_package && name.to_s != target_package
    pkg[:installed].is_a?(Array) && pkg[:installed].any? { |i| i[:platform] == platform_id }
  end

  if platform_pkgs.empty?
    puts '  No packages matched or installed.'
    next
  end

  platform_ok = 0
  platform_drifts = 0

  platform_pkgs.each do |pkgname, pkgdata|
    inst = pkgdata[:installed].find { |i| i[:platform] == platform_id }
    target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
    format_type = target ? target[:format] : 'directory'

    result = if format_type == 'skill' && platform_cfg[:type] == 'skill'
               verify_skill_build_artifact(platform_id, pkgname, inst[:output], inst[:checksum])
             else
               installed_path = Rulepack::Install.resolve_check_path(platform_cfg, target, base_path, base_path)
               if format_type == 'skill-bundle'
                 verify_skill_bundle_on_disk(installed_path, pkgname)
               else
                 verify_single_file_on_disk(installed_path, inst[:checksum], pkgname, inst[:output])
               end
             end

    if result == :ok
      platform_ok += 1
    else
      platform_drifts += 1
    end
  end

  # Scan orphans only if verifying the entire platform (not a specific package)
  orphans = []
  if target_package.nil?
    orphans = scan_orphans(platform_id, platform_cfg, base_path, packages)
  end

  if platform_ok.positive? || platform_drifts.positive? || orphans.any?
    puts "  #{platform_ok} OK | #{platform_drifts} drift(s) | #{orphans.size} orphan(s)"
  end
  total_drifts += platform_drifts
  total_orphans += orphans.size
  total_ok += platform_ok
end

puts "\n── Summary (#{total_platforms} platform(s)) ──"
puts "  #{total_ok} package(s) OK"
puts "  #{total_drifts} drift(s)" if total_drifts.positive?
puts "  #{total_orphans} orphan(s)" if total_orphans.positive?

exit 1 if total_drifts.positive?
exit 0
