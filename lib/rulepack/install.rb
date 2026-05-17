#!/usr/bin/env ruby
# frozen_string_literal: true

# Install CLI entry point
# Delegates to Rulepack::Install for all logic.
#
# Usage:
#   ruby lib/rulepack/install.rb <platform|package> [--target <platform>] [--needed] [--dry-run|-p] [--force|-f] [--select SKILLS] [--project PATH] [--verbose]
#   ruby lib/rulepack/install.rb --all [--needed] [--dry-run|-p] [--force|-f] [--select SKILLS]
#   ruby lib/rulepack/install.rb --targets <package>
#   ruby lib/rulepack/install.rb --check <platform> [--project PATH]

require 'pathname'
require_relative 'installer'
require_relative 'common'



# ─── Parse arguments ────────────────────────────────────────────────────────────

dry_run = false
check_mode = false
force_mode = false
verbose_mode = false
needed_mode = false
select_list = nil
platform_arg = nil
project_arg = nil
all_mode = false
targets_mode = false
target_platform = nil
collision_strategy = 'stop'

i = 0
while i < ARGV.length
  arg = ARGV[i]
  case arg
  when '--dry-run', '-p'
    dry_run = true
    i += 1
  when '--check'
    check_mode = true
    i += 1
  when '--force', '-f'
    force_mode = true
    i += 1
  when '--needed'
    needed_mode = true
    i += 1
  when '--target'
    raise 'Missing value for --target' if i + 1 >= ARGV.length

    target_platform = ARGV[i + 1].downcase
    i += 2
  when '--project'
    raise 'Missing path for --project' if i + 1 >= ARGV.length

    project_arg = ARGV[i + 1]
    i += 2
  when '--select'
    if i + 1 >= ARGV.length || ARGV[i + 1].start_with?('-')
      select_list = :interactive
      i += 1
    else
      select_list = ARGV[i + 1].split(',').map(&:strip).reject(&:empty?)
      i += 2
    end
  when '-v', '--verbose'
    verbose_mode = true
    i += 1
  when '--all'
    all_mode = true
    i += 1
  when '--targets'
    targets_mode = true
    i += 1
  when '--on-collision'
    raise 'Missing value for --on-collision' if i + 1 >= ARGV.length

    collision_strategy = ARGV[i + 1].downcase
    unless %w[stop ignore overwrite append].include?(collision_strategy)
      raise "Invalid collision strategy: #{collision_strategy}. Valid: stop, ignore, overwrite, append"
    end
    i += 2
  else
    platform_arg = arg
    i += 1
  end
end

# ─── Targets mode: show which platforms a package targets ───────────────────────

if targets_mode
  unless platform_arg
    puts 'Usage: ruby lib/rulepack/install.rb --targets <package>'
    puts 'Shows which platforms a package has targets for.'
    exit 1
  end

  pkgname = platform_arg
  index = if Rulepack::Common::INDEX_YAML_PATH.exist?
            Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
          else
            { version: 3.0, packages: {} }
          end

  pkg = index[:packages]&.find { |name, _| name.to_s == pkgname || name.to_s == pkgname.to_sym }
  unless pkg
    puts "❌ Package not found: #{pkgname}"
    exit 1
  end

  pkg_data = pkg[1]
  targets = pkg_data[:targets] || []
  available = pkg_data[:available_targets] || []

  puts "📦 #{pkgname} (#{Rulepack::Common.format_version(pkg_data[:epoch] || 0, pkg_data[:pkgver],
                                                         pkg_data[:pkgrel] || 1)})"
  puts ''
  puts "Targets (#{targets.size}):"
  targets.each do |t|
    status = available.include?(t[:platform]) ? '✓ built' : '✗ not built'
    puts "  • #{t[:platform]} (#{t[:format]}, #{t[:output]}) [#{status}]"
  end
  puts ''
  puts 'Installed on:'
  installed = pkg_data[:installed] || []
  if installed.empty?
    puts '  (none)'
  else
    installed.each do |rec|
      puts "  • #{rec[:platform]} (#{Rulepack::Common.format_version(rec[:epoch] || 0, rec[:version],
                                                                     rec[:pkgrel] || 1)}) — #{rec[:output]}"
    end
  end
  exit 0
end

# ─── All mode: install to all platforms ────────────────────────────────────────

if all_mode
  Rulepack::Install.install_all(
    dry_run: dry_run,
    force_mode: force_mode,
    needed_mode: needed_mode,
    verbose_mode: verbose_mode,
    select_list: select_list,
    project_arg: project_arg,
    collision_strategy: collision_strategy
  )
  exit 0
end

# ─── Single platform mode ───────────────────────────────────────────────────────

unless platform_arg || check_mode
  puts 'Usage: ruby lib/rulepack/install.rb <platform|package> [--target <platform>] [--needed] [--dry-run|-p] [--force|-f] [--select SKILLS] [--project PATH]'
  puts '       ruby lib/rulepack/install.rb --all [--needed] [--dry-run|-p] [--force|-f] [--select SKILLS]'
  puts '       ruby lib/rulepack/install.rb --targets <package>'
  puts '       ruby lib/rulepack/install.rb --check <platform> [--project PATH]'
  puts ''
  puts 'Platforms: opencode, oh-my-pi, crush, goose, droid, gemini-cli, qwen-code,'
  puts '            cursor, windsurf, github-copilot, claude-code, codex, agents'
  puts ''
  puts 'Options:'
  puts '  --all             Install to all platforms'
  puts '  --targets PKG     Show target platforms for a package'
  puts '  --target PLATFORM Install package to specific platform (with package name)'
  puts '  --needed          Skip packages that are already installed and current'
  puts '  --dry-run, -p     Preview without changes'
  puts '  --force, -f       Allow downgrades'
  puts '  --select SKILLS   Comma-separated sub-skill names (skill-bundle only)'
  puts '  --project PATH    Project root (for project-level platforms)'
  puts '  --verbose         Debug logging'
  exit 1
end

# ─── Resolve: is the argument a package or a platform? ──────────────────────────

actual_platform = platform_arg
target_package = nil

if platform_arg && !check_mode && !targets_mode
  build_idx = if Rulepack::Common::BUILD_INDEX_PATH.exist?
                Rulepack::Common.load_yaml(Rulepack::Common::BUILD_INDEX_PATH)
              end
  if build_idx && build_idx[:packages]
    arg = platform_arg.downcase
    match = build_idx[:packages].keys.find { |k| k.to_s.downcase == arg }
    match ||= build_idx[:packages].keys.find { |k| k.to_s.downcase.start_with?(arg) && k.to_s.length >= arg.length * 2 }
    if match
      target_package = match.to_s
      actual_platform = nil
    end
  end
end

# ─── Dispatch ──────────────────────────────────────────────────────────────────

if check_mode
  Rulepack::Install.check_platform(actual_platform || platform_arg, project_arg: project_arg)

elsif target_package
  # Single package install
  pkgdata = build_idx[:packages][target_package.to_sym]
  targets = (pkgdata[:targets] || []).map { |t| t[:platform] }

  registry = Rulepack::Common.load_platform_registry
  platforms_to_install = []

  if target_platform
    unless targets.include?(target_platform)
      puts "❌ #{target_package} does not target '#{target_platform}'. Available: #{targets.join(', ')}"
      exit 1
    end
    platforms_to_install = [target_platform]
  else
    platforms_to_install = targets.select do |t|
      cfg = registry[t.to_sym] || registry[t.to_s]
      cfg && (cfg[:scope] == 'user' || !cfg.key?(:scope))
    end
    if platforms_to_install.empty?
      puts "❌ #{target_package} has no user-scoped targets. Please specify a project-scoped platform using --target <platform> and --project <path>."
      exit 1
    end
  end

  platforms_to_install.each do |pkg_platform|
    Rulepack::Common.log "📦 Installing #{target_package} → #{pkg_platform}"
    Rulepack::Install.run(pkg_platform,
                          dry_run: dry_run, force_mode: force_mode,
                          needed_mode: needed_mode,
                          verbose_mode: verbose_mode, select_list: select_list,
                          project_arg: project_arg, specific_package: target_package,
                          collision_strategy: collision_strategy)
  end

else
  Rulepack::Install.run(actual_platform,
                        dry_run: dry_run, force_mode: force_mode,
                        needed_mode: needed_mode,
                        verbose_mode: verbose_mode, select_list: select_list,
                        project_arg: project_arg,
                        collision_strategy: collision_strategy)
end
