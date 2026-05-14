#!/usr/bin/env ruby
# frozen_string_literal: true

# Query tool for SSoT package database
# Can be used as script: ruby ssot/query.rb <command>
# Or as module: require "ssot/query"; Ssot::Query.run(["list-packages"])

require 'yaml'
require 'json'
require 'pathname'
require_relative 'lib/common'

module Ssot
  module Query
    module_function

    def run(argv = ARGV)
      command = argv.shift || "help"
      case command
      when "list-packages", "ls"
        list_packages
      when "list-platforms", "lp"
        list_platforms
      when "installed", "i"
        platform = argv.shift || "opencode"
        list_installed(platform)
      when "show", "info"
        pkgname = argv.shift
        show_package(pkgname)
      when "search", "s"
        keyword = argv.shift
        search(keyword)
      when "check", "c"
        check_consistency
      when "orphans", "o"
        list_orphans
      when "depends", "d"
        pkgname = argv.shift
        show_depends(pkgname)
      when "provides", "p"
        capability = argv.shift
        show_provides(capability)
      when "help", "h"
        print_help
      else
        warn "Unknown command: #{command}"
        print_help
        exit 1
      end
      0
    rescue => e
      warn "Error: #{e.message}"
      exit 1
    end

    def print_help
      puts <<~HELP
        SSoT Database Query Tool

        Usage: ruby ssot/query.rb <command> [options]
        Or:    ssot query <command> [options]

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
          ruby ssot/query.rb ls
          ruby ssot/query.rb installed --platform crush
          ruby ssot/query.rb show memory
          ruby ssot/query.rb search security
      HELP
    end

    def load_index
      root = Pathname.new(__dir__).expand_path
      yaml_path = root.join("index.yaml")
      json_path = root.join("index.json")
      
      if yaml_path.exist?
        Ssot::Lib::Common.load_yaml(yaml_path)
      elsif json_path.exist?
        JSON.parse(json_path.read, symbolize_names: true)
      else
        abort "❌ Index not found: #{yaml_path} or #{json_path}. Run `ruby ssot/build.rb` first."
      end
    end

    def list_packages
      index = load_index
      pkgs = index[:packages] || {}
      puts "📦 Packages (#{pkgs.size}):"
      pkgs.each do |name, pkg|
        installed = Array(pkg[:installed]).map { |r| r[:platform] }.uniq
        puts "  #{name} (#{Ssot::Lib::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver], pkg[:pkgrel] || 1)}) [#{pkg[:status] || 'stable'}]"
        puts "    Targets: #{Array(pkg[:available_targets]).join(', ')}"
        puts "    Installed: #{installed.empty? ? 'none' : installed.join(', ')}"
        puts "    Tags: #{Array(pkg[:tags]).join(', ')}"
        puts
      end
    end

    def list_platforms
      registry = Ssot::Lib::Common.load_platform_registry
      puts "🎯 Platforms (#{registry.size}):"
      registry.each do |id, cfg|
        puts "  #{id} (#{cfg[:display_name] || id})"
        puts "    Type: #{cfg[:type]} | Scope: #{cfg[:scope] || 'user'}"
        puts "    Base: #{cfg[:base_path]}"
        puts
      end
    end

    def list_installed(platform)
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
          puts "  ✓ #{name} (#{Ssot::Lib::Common.format_version(rec[:epoch] || 0, rec[:version], rec[:pkgrel] || 1)})"
          puts "    Output: #{rec[:output]}"
          puts "    Checksum: #{rec[:checksum]&.slice(0, 16)}..."
          puts "    Installed: #{rec[:installed_at]}"
        end
        puts "  Total: #{installed.size} package(s)"
      end
    end

    def show_package(pkgname)
      index = load_index
      pkg = index[:packages][pkgname.to_sym] || index[:packages][pkgname]
      unless pkg
        warn "Package not found: #{pkgname}"
        exit 1
      end
      puts "📦 #{pkgname}"
      puts "  Version: #{Ssot::Lib::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver], pkg[:pkgrel] || 1)}"
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

    def search(keyword)
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
          puts "  #{name} (#{Ssot::Lib::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver], pkg[:pkgrel] || 1)}): #{pkg[:pkgdesc]}"
        end
      end
    end

    def list_orphans
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
        puts "✅ No orphaned packages."
      else
        puts "⚠️  Orphaned packages (#{orphans.size}):"
        orphans.each do |o|
          puts "  • #{o[:name]} on #{o[:platform]} (output: #{o[:output]})"
        end
      end
    end

    def show_depends(pkgname)
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

    def show_provides(capability)
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
          puts "  • #{name} (#{Ssot::Lib::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver], pkg[:pkgrel] || 1)})"
        end
      end
    end

    def check_consistency
      index = load_index
      pkgs = index[:packages] || {}
      build_index = begin
        Ssot::Lib::Common.load_yaml(Pathname.new(__dir__).expand_path.join("build", "index.yaml"))
      rescue
        nil
      end
      
      issues = []
      pkgs.each do |name, pkg|
        Array(pkg[:installed]).each do |rec|
          platform = rec[:platform]
          output = rec[:output]
          
          # Check if package has target for this platform
          unless Array(pkg[:available_targets]).include?(platform)
            issues << "#{name} installed on #{platform} but no target defined"
          end
          
          # Check if build artifact exists
          if build_index
            built = build_index[:packages]&.[](name.to_sym)
            checksum = built&.[](:checksums)&.[](:built)&.[](platform.to_sym)
            if checksum && rec[:checksum] != checksum
              issues << "#{name} checksum mismatch on #{platform}"
            end
          end
        end
      end
      
      if issues.empty?
        puts "✅ Database consistency check passed."
      else
        puts "❌ Consistency issues found:"
        issues.each { |i| puts "  - #{i}" }
        exit 1
      end
    end
  end
end

# Run as script
if __FILE__ == $PROGRAM_NAME
  exit Ssot::Query.run(ARGV)
end
