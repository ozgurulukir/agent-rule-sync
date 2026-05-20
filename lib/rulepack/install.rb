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
require_relative 'cli_parser'

# Gracefully shift pacman -S flag if passed as first argument
ARGV.shift if ARGV.first == '-S'

# ─── Parse arguments (via CliParser) ────────────────────────────────────────────────────────────────────────────────────────

begin
  _opts = Rulepack::CliParser.parse(ARGV)
rescue StandardError => e
  abort "❌ Error: #{e.message}"
end

package_arg    = _opts[:package_name]
target_arg     = _opts[:target]
project_arg    = _opts[:project_path]
dry_run        = _opts[:dry_run]
check_mode     = _opts[:check_mode]
force_mode     = _opts[:force]
verbose_mode   = _opts[:verbose]
needed_mode    = _opts[:needed]
select_list    = _opts[:select]
targets_mode   = _opts[:targets_mode]
collision_strategy = _opts[:on_collision] || "stop"

# Check positional count
if _opts[:positional]&.size.to_i > 1
  abort "❌ Error: Too many positional arguments. Usage: ruby install.rb [package_name] --target <platform|all>"
end

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
  index = if Rulepack::Common.index_yaml_path.exist?
            Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
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

