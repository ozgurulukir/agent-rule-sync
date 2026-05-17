#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify index vs disk state
# Compares Rulepack index (what should be installed) against actual files on disk.
# Reports: OK packages, drift (missing/modified), orphans (not in index).
# Exit code 0 = no drift, 1 = drift found.

require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require_relative 'common'
require_relative 'installer'



def main
  platform_arg = ARGV.first

  abort 'index.yaml not found. Run `rulepack install <platform>` first to create it.' unless Rulepack::Common::INDEX_YAML_PATH.exist?

  index = Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
  packages = index[:packages] || {}

  # Determine which platforms to verify
  platforms_to_verify = if platform_arg
                          [platform_arg]
                        else
                          # All platforms that have installed packages
                          platforms_with_installed(packages)
                        end

  if platforms_to_verify.empty?
    puts 'No installed packages found. Nothing to verify.'
    exit 0
  end

  total_drifts = 0
  total_orphans = 0
  total_ok = 0
  total_platforms = 0

  platforms_to_verify.each do |platform_id|
    platform_cfg = Rulepack::Common.platform_config(platform_id, Rulepack::Common.load_platform_registry)
    unless platform_cfg
      puts "Unknown platform: #{platform_id}"
      next
    end

    total_platforms += 1
    puts "\n── #{platform_id} (#{platform_cfg[:display_name]}) ──"

    base_path = resolve_base_path(platform_cfg)
    platform_pkgs = select_platform_packages(packages, platform_id)

    if platform_pkgs.empty?
      puts '  No packages installed.'
      next
    end

    platform_ok, platform_drifts = verify_platform_packages(platform_id, platform_cfg, platform_pkgs, base_path)
    orphans = scan_orphans(platform_id, platform_cfg, base_path, packages)

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
end

def platforms_with_installed(packages)
  platforms = Set.new
  packages.each_value do |pkg|
    (pkg[:installed] || []).each { |i| platforms << i[:platform] }
  end
  platforms.to_a
end

def select_platform_packages(packages, platform_id)
  packages.select do |_, pkg|
    pkg[:installed].is_a?(Array) && pkg[:installed].any? { |i| i[:platform] == platform_id }
  end
end

def verify_platform_packages(platform_id, platform_cfg, platform_pkgs, base_path)
  ok = 0
  drifts = 0
  platform_pkgs.each do |pkgname, pkgdata|
    inst = pkgdata[:installed].find { |i| i[:platform] == platform_id }
    result = verify_package(platform_id, platform_cfg, pkgname, pkgdata, inst, base_path)
    if result == :ok
      ok += 1
    else
      drifts += 1
    end
  end
  [ok, drifts]
end

def resolve_base_path(platform_cfg)
  project_root = Rulepack::Common.project_root_for(platform_cfg, nil)
  return project_root if project_root

  Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
end

def verify_package(platform_id, platform_cfg, pkgname, pkgdata, inst, base_path)
  expected_output = inst[:output]
  expected_checksum = inst[:checksum]
  target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
  format_type = target ? target[:format] : 'directory'

  if format_type == 'skill' && platform_cfg[:type] == 'skill'
    return verify_skill_build_artifact(platform_id, pkgname, expected_output, expected_checksum)
  end

  installed_path = Rulepack::Install.resolve_check_path(platform_cfg, target,
                                                        base_path, base_path)

  case format_type
  when 'skill-bundle'
    verify_skill_bundle_on_disk(installed_path, pkgname)
  else
    verify_single_file_on_disk(installed_path, expected_checksum, pkgname, expected_output)
  end
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

def verify_single_file_on_disk(path, expected_checksum, pkgname, expected_output)
  unless path.exist?
    puts "  ⚠ MISSING: #{pkgname} (#{expected_output}) at #{path}"
    return :drift
  end
  actual_sha = Digest::SHA256.hexdigest(path.read)
  if actual_sha == expected_checksum
    puts "  ✓ #{pkgname} (#{expected_output})"
    return :ok
  end
  puts "  ⚠ CHECKSUM mismatch: #{pkgname} (#{expected_output})"
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

      p = Rulepack::Install.resolve_check_path(platform_cfg, target, base_path,
                                              base_path)
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

  orphans.each do |orphan|
    puts "  ? ORPHAN: #{orphan}"
  end
  orphans
end

main
