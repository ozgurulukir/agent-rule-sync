#!/usr/bin/env ruby
# frozen_string_literal: true

# Install CLI entry point
# Enforces Zero Assumptions, Data-Driven Execution, and Clean Separation of Concerns.
#
# Usage:
#   ruby lib/rulepack/install.rb [package_name] --target <platform|all> [--project PATH] [options]
#   ruby lib/rulepack/install.rb [package_name] -t <platform|all> [-p PATH] [options]
#
# Kısayol (Pacman Mimicry):
#   ruby lib/rulepack/install.rb -S [package_name] --target <platform|all>

require 'pathname'
require_relative 'installer'
require_relative 'common'

# Gracefully shift pacman -S flag if passed as first argument
ARGV.shift if ARGV.first == '-S'

# ─── Parse arguments ────────────────────────────────────────────────────────────

dry_run = false
check_mode = false
force_mode = false
verbose_mode = false
needed_mode = false
select_list = nil
positional_args = []
project_arg = nil
targets_mode = false
target_arg = nil
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
  when '--target', '-t'
    raise 'Missing value for --target' if i + 1 >= ARGV.length
    target_arg = ARGV[i + 1]
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
    positional_args << arg
    i += 1
  end
end

# Check positional count
if positional_args.size > 1
  abort "❌ Error: Too many positional arguments. Usage: ruby install.rb [package_name] --target <platform|all>"
end

package_arg = positional_args.first

# ─── Load platforms registry and build index ───────────────────────────────────

registry = Rulepack::Common.load_platform_registry
build_idx = if Rulepack::Common::BUILD_INDEX_PATH.exist?
              Rulepack::Common.load_yaml(Rulepack::Common::BUILD_INDEX_PATH)
            end

# ─── Exact package validation ──────────────────────────────────────────────────

target_package = nil
if package_arg
  unless build_idx && build_idx[:packages] && (build_idx[:packages].key?(package_arg) || build_idx[:packages].key?(package_arg.to_sym))
    abort "❌ Error: Package '#{package_arg}' not found in build index."
  end
  # Ensure exact casing/symbol match
  target_package = build_idx[:packages].keys.find { |k| k.to_s == package_arg }.to_s
end

# ─── Target platform checks (MANDATORY) ────────────────────────────────────────

if !check_mode && !targets_mode
  unless target_arg
    abort "❌ Error: Please specify target platform(s) with --target <platform> (or --target all)."
  end

  # Resolve targets
  targets_to_install = []
  if target_arg.downcase == 'all'
    if target_package
      # Install only targeted platforms of this package
      pkgdata = build_idx[:packages][target_package.to_sym]
      targets_to_install = (pkgdata[:targets] || []).map { |t| t[:platform] }
    else
      # Install all user-scoped platforms (global sync)
      targets_to_install = registry.keys.select { |p| registry[p][:scope] == 'user' || !registry[p].key?(:scope) }
    end
  else
    targets_to_install = target_arg.split(',').map(&:strip).reject(&:empty?)
  end

  if targets_to_install.empty?
    abort "❌ Error: No target platforms matched."
  end

  # Validate targets against registry
  targets_to_install.each do |p|
    unless registry.key?(p.to_sym) || registry.key?(p.to_s)
      abort "❌ Error: Unknown target platform '#{p}'."
    end

    # Enforce --project path for project-scoped platforms
    cfg = registry[p.to_sym] || registry[p.to_s]
    if cfg[:scope] == 'project' && !project_arg
      abort "❌ Error: Platform '#{cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>."
    end
  end
end

# ─── Targets mode: show which platforms a package targets ───────────────────────

if targets_mode
  unless package_arg
    abort "Usage: ruby lib/rulepack/install.rb <package> --targets"
  end

  pkg_data = build_idx[:packages][target_package.to_sym]
  targets = pkg_data[:targets] || []
  available = pkg_data[:available_targets] || []

  puts "📦 #{target_package} (#{Rulepack::Common.format_version(pkg_data[:epoch] || 0, pkg_data[:pkgver], pkg_data[:pkgrel] || 1)})"
  puts ''
  puts "Targets (#{targets.size}):"
  targets.each do |t|
    status = available.include?(t[:platform]) ? '✓ built' : '✗ not built'
    puts "  • #{t[:platform]} (#{t[:format]}, #{t[:output]}) [#{status}]"
  end
  puts ''
  puts 'Installed on:'
  # Load master index
  index = if Rulepack::Common::INDEX_YAML_PATH.exist?
            Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
          else
            { version: 3.0, packages: {} }
          end
  pkg_idx = index[:packages]&.[](target_package.to_sym) || index[:packages]&.[](target_package.to_s) || {}
  installed = pkg_idx[:installed] || []
  if installed.empty?
    puts '  (none)'
  else
    installed.each do |rec|
      puts "  • #{rec[:platform]} (#{Rulepack::Common.format_version(rec[:epoch] || 0, rec[:version], rec[:pkgrel] || 1)}) — #{rec[:output]}"
    end
  end
  exit 0
end

# ─── Check mode ────────────────────────────────────────────────────────────────

if check_mode
  unless target_arg
    abort "❌ Error: Please specify platform for check mode with --target <platform>."
  end
  Rulepack::Install.check_platform(target_arg, project_arg: project_arg)
  exit 0
end

# ─── Dispatch ──────────────────────────────────────────────────────────────────

# If target_arg is 'all' and no target_package was specified, we run install_all
if target_arg.downcase == 'all' && !target_package
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

# Otherwise, install specific platform(s)
targets_to_install.each do |pkg_platform|
  if target_package
    Rulepack::Common.log "📦 Installing #{target_package} → #{pkg_platform}"
    puts "📦 Installing #{target_package} → #{pkg_platform}"
  else
    Rulepack::Common.log "📦 Installing all packages → #{pkg_platform}"
    puts "📦 Installing all packages → #{pkg_platform}"
  end

  Rulepack::Install.run(pkg_platform,
                        dry_run: dry_run, force_mode: force_mode,
                        needed_mode: needed_mode,
                        verbose_mode: verbose_mode, select_list: select_list,
                        project_arg: project_arg, specific_package: target_package,
                        collision_strategy: collision_strategy)
end
