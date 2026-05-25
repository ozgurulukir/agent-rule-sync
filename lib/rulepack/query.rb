#!/usr/bin/env ruby
# frozen_string_literal: true

# Query tool for Rulepack package database
# P-E split: COMMANDS dispatch table + cmd_* per-command methods
# Can be used as script: ruby lib/rulepack/query.rb <command>
# Or as module: require "lib/rulepack/query"; Rulepack::Query.run(["list-packages"])

require 'yaml'
require 'json'
require 'pathname'
require_relative 'common'

module Rulepack
  module Query
    module_function

    # ─── Entry point ───────────────────────────────────────────────────────────────

    def run(argv = ARGV)
      argv = argv.dup
      argv.shift if argv.first == '-Q'
      command = argv.shift || 'help'

      meth = COMMANDS[command]
      if meth
        send(meth, argv)
      else
        warn "Unknown command: #{command}"
        print_help
        exit 1
      end
      0
    rescue StandardError => e
      warn "Error: #{e.message}"
      exit 1
    end

    # ─── Per-command methods ──────────────────────────────────────────────────────

    def cmd_list_packages(_argv)
      index = load_index
      pkgs = index[:packages] || {}
      puts "📦 Packages (#{pkgs.size}):"
      pkgs.each do |name, pkg|
        installed = Array(pkg[:installed]).map { |r| r[:platform] }.uniq
        puts "  #{name} (#{Rulepack::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver],
                                                           pkg[:pkgrel] || 1)}) [#{pkg[:status] || 'stable'}]"
        puts "    Targets: #{Array(pkg[:available_targets]).join(', ')}"
        puts "    Installed: #{installed.empty? ? 'none' : installed.join(', ')}"
        puts "    Tags: #{Array(pkg[:tags]).join(', ')}"
        puts
      end
    end

    def cmd_list_platforms(_argv)
      registry = Rulepack::Common.load_platform_registry
      puts "🎯 Platforms (#{registry.size}):"
      registry.each do |id, cfg|
        puts "  #{id} (#{cfg[:display_name] || id})"
        puts "    Type: #{cfg[:type]} | Scope: #{cfg[:scope] || 'user'}"
        puts "    Base: #{cfg[:base_path]}"
        puts
      end
    end

    def cmd_installed(argv)
      platform = argv.shift || 'opencode'
      list_installed_impl(platform)
    end

    def cmd_show(argv)
      pkgname = argv.shift
      show_package_impl(pkgname)
    end

    def cmd_search(argv)
      keyword = argv.shift
      search_impl(keyword)
    end

    def cmd_check(_argv)
      check_consistency_impl
    end

    def cmd_orphans(_argv)
      list_orphans_impl
    end

    def cmd_depends(argv)
      pkgname = argv.shift
      show_depends_impl(pkgname)
    end

    def cmd_provides(argv)
      capability = argv.shift
      show_provides_impl(capability)
    end

    # ─── Help ─────────────────────────────────────────────────────────────────────

    def print_help(_argv = [])
      puts <<~HELP
        Rulepack Database Query Tool

        Usage: ruby lib/rulepack/query.rb <command> [options]
        Or:    rulepack query <command> [options]

        Commands:
          list-packages, ls        List all packages with metadata
          list-platforms, lp       List all target platforms
          installed, i [platform]  Show installed packages (default: opencode)
          show, info <package>     Show detailed package info
          search, s <keyword>      Search packages by name/description/tags
          check, c                 Check database consistency
          orphans, o               List orphaned packages (installed but no target)
          depends, d <package>     Show package dependencies
          provides, p <capability> Show packages providing a capability
          help, h                  Show this help

        Examples:
          ruby lib/rulepack/query.rb ls
          ruby lib/rulepack/query.rb installed --platform crush
          ruby lib/rulepack/query.rb show memory
          ruby lib/rulepack/query.rb search security
      HELP
    end

    # ─── Shared helpers ──────────────────────────────────────────────────────────

    def load_index
      root = Pathname.new(__dir__).parent.parent.expand_path
      yaml_path = root.join('data', 'index.yaml')
      build_path = root.join('build', 'index.yaml')

      # Load installed records from data/index.yaml (written by install)
      installed = if yaml_path.exist?
                    data = Rulepack::Common.load_yaml(yaml_path)
                    data[:packages] || {}
                  else
                    {}
                  end

      # Load package metadata from build/index.yaml (written by build)
      build = if build_path.exist?
                Rulepack::Common.load_yaml(build_path)
              else
                {}
              end

      # Merge: build metadata + installed records
      build[:packages] ||= {}
      build[:packages].each_key do |name|
        if installed[name]
          build[:packages][name][:installed] = installed[name][:installed]
          build[:packages][name][:installed] ||= []
        end
        build[:packages][name][:installed] ||= []
      end

      # Add installed-only packages (e.g. from restored backups)
      installed.each do |name, pkg|
        next if build[:packages][name]

        build[:packages][name] = pkg
      end

      build
    end

    def list_installed_impl(platform)
      index = load_index
      pkgs = index[:packages] || {}
      installed = pkgs.filter_map do |name, pkg|
        rec = Array(pkg[:installed]).find { |r| r[:platform] == platform }
        [name, rec] if rec
      end

      if installed.empty?
        puts "📥 No packages installed on #{platform}."
      else
        puts "📥 Installed packages on #{platform}:"
        installed.each do |name, rec|
          puts "  ✓ #{name} (#{Rulepack::Common.format_version(rec[:epoch] || 0, rec[:version],
                                                               rec[:pkgrel] || 1)})"
          puts "    Output: #{rec[:output]}"
          puts "    Checksum: #{rec[:checksum]&.slice(0, 16)}..."
          puts "    Installed: #{rec[:installed_at]}"
        end
        puts "  Total: #{installed.size} package(s)"
      end
    end

    def show_package_impl(pkgname)
      index = load_index
      pkg = index[:packages][pkgname.to_sym] || index[:packages][pkgname]
      unless pkg
        warn "Package not found: #{pkgname}"
        exit 1
      end
      puts "📦 #{pkgname}"
      puts "  Version: #{Rulepack::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver],
                                                         pkg[:pkgrel] || 1)}"
      puts "  Description: #{pkg[:pkgdesc]}"
      puts "  Status: #{pkg[:status] || 'stable'}"
      puts "  Targets: #{Array(pkg[:available_targets]).join(', ')}"
      installed = Array(pkg[:installed]).map { |r| r[:platform] }.uniq
      puts "  Installed: #{installed.empty? ? 'none' : installed.join(', ')}"
      puts "  Tags: #{Array(pkg[:tags]).join(', ')}"
      puts "  Dependencies: #{Array(pkg[:dependencies]).join(', ') || 'none'}"
      puts "  Conflicts: #{Array(pkg[:conflicts]).join(', ') || 'none'}"
      puts "  Provides: #{Array(pkg[:provides]).join(', ') || 'none'}"
    end

    def search_impl(keyword)
      index = load_index
      pkgs = index[:packages] || {}
      results = pkgs.select do |name, pkg|
        name.to_s.include?(keyword) ||
          pkg[:pkgdesc].to_s.include?(keyword) ||
          Array(pkg[:tags]).any? { |t| t.include?(keyword) }
      end
      if results.empty?
        puts "No packages found matching: #{keyword}"
      else
        puts "🔍 Search results for '#{keyword}':"
        results.each do |name, pkg|
          puts "  #{name} (#{Rulepack::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver],
                                                             pkg[:pkgrel] || 1)}): #{pkg[:pkgdesc]}"
        end
      end
    end

    def list_orphans_impl
      index = load_index
      pkgs = index[:packages] || {}
      orphans = []

      pkgs.each do |name, pkg|
        Array(pkg[:installed]).each do |rec|
          platform = rec[:platform]
          unless Array(pkg[:available_targets]).include?(platform)
            orphans << { name: name, platform: platform, output: rec[:output] }
          end
        end
      end

      if orphans.empty?
        puts '✅ No orphaned packages.'
      else
        puts "⚠️  Orphaned packages (#{orphans.size}):"
        orphans.each do |o|
          puts "  • #{o[:name]} on #{o[:platform]} (output: #{o[:output]})"
        end
      end
    end

    def show_depends_impl(pkgname)
      index = load_index
      pkg = index[:packages][pkgname.to_sym] || index[:packages][pkgname]
      unless pkg
        warn "Package not found: #{pkgname}"
        exit 1
      end

      deps = Array(pkg[:dependencies])
      if deps.empty?
        puts "#{pkgname} has no dependencies."
      else
        puts "#{pkgname} depends on:"
        deps.each { |d| puts "  • #{d}" }
      end
    end

    def show_provides_impl(capability)
      index = load_index
      pkgs = index[:packages] || {}
      providers = pkgs.filter_map do |name, pkg|
        [name, pkg] if Array(pkg[:provides]).include?(capability)
      end

      if providers.empty?
        puts "No packages provide: #{capability}"
      else
        puts "Packages providing '#{capability}':"
        providers.each do |name, pkg|
          puts "  • #{name} (#{Rulepack::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver],
                                                               pkg[:pkgrel] || 1)})"
        end
      end
    end

    def check_consistency_impl
      index = load_index
      pkgs = index[:packages] || {}
      build_root = Pathname.new(__dir__).parent.parent.expand_path.join('build')
      build_index = begin
        Rulepack::Common.load_yaml(build_root.join('index.yaml'))
      rescue StandardError
        nil
      end

      issues = []
      pkgs.each do |name, pkg|
        Array(pkg[:installed]).each do |rec|
          platform = rec[:platform]
          _output = rec[:output]

          # Check if package has target for this platform
          unless Array(pkg[:available_targets]).include?(platform)
            issues << "#{name} installed on #{platform} but no target defined"
          end

          # Check if build artifact exists
          next unless build_index

          built = build_index[:packages]&.[](name.to_sym)
          built_checksums = built&.dig(:checksums, :built)
          checksum = built_checksums&.[](platform.to_s)
          issues << "#{name} checksum mismatch on #{platform}" if checksum && rec[:checksum] != checksum
        end
      end

      if issues.empty?
        puts '✅ Database consistency check passed.'
      else
        puts '❌ Consistency issues found:'
        issues.each { |i| puts "  - #{i}" }
        exit 1
      end
    end

    # ─── Dispatch table (defined after all cmd_* methods) ─────────────────────────

    COMMANDS = {
      'list-packages'  => :cmd_list_packages,
      'ls'             => :cmd_list_packages,
      'list-platforms' => :cmd_list_platforms,
      'lp'             => :cmd_list_platforms,
      'installed'      => :cmd_installed,
      'i'              => :cmd_installed,
      'show'           => :cmd_show,
      'info'           => :cmd_show,
      'search'         => :cmd_search,
      's'              => :cmd_search,
      'check'          => :cmd_check,
      'c'              => :cmd_check,
      'orphans'        => :cmd_orphans,
      'o'              => :cmd_orphans,
      'depends'        => :cmd_depends,
      'd'              => :cmd_depends,
      'provides'       => :cmd_provides,
      'p'              => :cmd_provides,
      'help'           => :print_help,
      'h'              => :print_help,
    }.freeze

    # ─── Backward-compatible public aliases ────────────────────────────────────────
    # Tests and external callers may still use the original method names directly.
    # Each alias delegates to its cmd_* counterpart.

    module_function

    def list_packages(*_args)
      cmd_list_packages([])
    end

    def list_platforms(*_args)
      cmd_list_platforms([])
    end

    def installed(platform = 'opencode')
      list_installed_impl(platform)
    end

    def show(pkgname)
      show_package_impl(pkgname)
    end

    def search(*args)
      cmd_search(args)
    end

    def check(*_args)
      cmd_check([])
    end

    def orphans(*_args)
      cmd_orphans([])
    end

    def depends(pkgname)
      show_depends_impl(pkgname)
    end

    def provides(capability)
      show_provides_impl(capability)
    end

    def show_provides(capability)
      show_provides_impl(capability)
    end
  end
end

# Run as script
exit Rulepack::Query.run(ARGV) if __FILE__ == $PROGRAM_NAME
