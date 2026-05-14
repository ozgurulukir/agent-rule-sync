#!/usr/bin/env ruby
# frozen_string_literal: true

# ssot/install.rb — Platform installer (CLI entry point)
# Delegates to Ssot::Install for all logic.
#
# Usage:
#   ruby ssot/install.rb <platform> [--dry-run] [--force] [--select SKILLS] [--project PATH] [--verbose]
#   ruby ssot/install.rb --all [--dry-run] [--force] [--select SKILLS]
#   ruby ssot/install.rb --targets <package>
#   ruby ssot/install.rb --check <platform> [--project PATH]

require 'pathname'
require_relative 'lib/install'
require_relative 'lib/common'

SSOT_ROOT = Pathname.new(__dir__).expand_path

# ─── Parse arguments ────────────────────────────────────────────────────────────

dry_run = false
check_mode = false
force_mode = false
verbose_mode = false
select_list = nil
platform_arg = nil
project_arg = nil
all_mode = false
targets_mode = false

i = 0
while i < ARGV.length
  arg = ARGV[i]
  case arg
  when '--dry-run'
    dry_run = true
    i += 1
  when '--check'
    check_mode = true
    i += 1
  when '--force'
    force_mode = true
    i += 1
  when '--project'
    if i + 1 >= ARGV.length
      raise "Missing path for --project"
    end
    project_arg = ARGV[i + 1]
    i += 2
  when '--select'
    if i + 1 >= ARGV.length
      raise "Missing value for --select"
    end
    select_list = ARGV[i + 1].split(',').map(&:strip).reject(&:empty?)
    i += 2
  when '-v', '--verbose'
    verbose_mode = true
    i += 1
  when '--all'
    all_mode = true
    i += 1
  when '--targets'
    targets_mode = true
    i += 1
  else
    platform_arg = arg
    i += 1
  end
end

# ─── Targets mode: show which platforms a package targets ───────────────────────

if targets_mode
  unless platform_arg
    puts "Usage: ruby ssot/install.rb --targets <package>"
    puts "Shows which platforms a package has targets for."
    exit 1
  end

  pkgname = platform_arg
  index = if SSOT_ROOT.join('index.yaml').exist?
            Ssot::Lib::Common.load_yaml(SSOT_ROOT.join('index.yaml'))
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

  puts "📦 #{pkgname} (#{Ssot::Lib::Common.format_version(pkg_data[:epoch] || 0, pkg_data[:pkgver], pkg_data[:pkgrel] || 1)})"
  puts ""
  puts "Targets (#{targets.size}):"
  targets.each do |t|
    status = available.include?(t[:platform]) ? '✓ built' : '✗ not built'
    puts "  • #{t[:platform]} (#{t[:format]}, #{t[:output]}) [#{status}]"
  end
  puts ""
  puts "Installed on:"
  installed = pkg_data[:installed] || []
  if installed.empty?
    puts "  (none)"
  else
    installed.each do |rec|
      puts "  • #{rec[:platform]} (#{Ssot::Lib::Common.format_version(rec[:epoch] || 0, rec[:version], rec[:pkgrel] || 1)}) — #{rec[:output]}"
    end
  end
  exit 0
end

# ─── All mode: install to all platforms ────────────────────────────────────────

if all_mode
  Ssot::Install.install_all(
    dry_run: dry_run,
    force_mode: force_mode,
    verbose_mode: verbose_mode,
    select_list: select_list,
    project_arg: project_arg
  )
  exit 0
end

# ─── Single platform mode ───────────────────────────────────────────────────────

unless platform_arg || check_mode
  puts "Usage: ruby ssot/install.rb <platform> [--dry-run] [--force] [--select SKILLS] [--project PATH]"
  puts "       ruby ssot/install.rb --all [--dry-run] [--force] [--select SKILLS]"
  puts "       ruby ssot/install.rb --targets <package>"
  puts "       ruby ssot/install.rb --check <platform> [--project PATH]"
  puts ""
  puts "Platforms: opencode, oh-my-pi, crush, goose, droid, gemini-cli, qwen-code,"
  puts "            cursor, windsurf, github-copilot, claude-code, codex, agents"
  puts ""
  puts "Options:"
  puts "  --all             Install to all platforms"
  puts "  --targets PKG     Show target platforms for a package"
  puts "  --dry-run         Preview without changes"
  puts "  --force           Allow downgrades"
  puts "  --select SKILLS   Comma-separated sub-skill names (skill-bundle only)"
  puts "  --project PATH    Project root (for project-level platforms)"
  puts "  --verbose         Debug logging"
  exit 1
end

# ─── Dispatch ──────────────────────────────────────────────────────────────────

if check_mode
  Ssot::Install.check_platform(platform_arg, project_arg: project_arg)
else
  Ssot::Install.run(platform_arg,
    dry_run: dry_run,
    force_mode: force_mode,
    verbose_mode: verbose_mode,
    select_list: select_list,
    project_arg: project_arg
  )
end
