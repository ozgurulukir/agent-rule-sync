#!/usr/bin/env ruby
# frozen_string_literal: true

# Query tool for Rulepack package database
# P-E split: COMMANDS dispatch table + cmd_* per-command methods
# Can be used as script: ruby lib/rulepack/query.rb <command>
# Or as module: require "lib/rulepack/query"; Rulepack::Query.run(["list-packages"])

require_relative 'encoding_defaults'
require 'yaml'
require 'json'
require 'pathname'
require_relative 'common'
require_relative 'install_plan'

module Rulepack
  module Query
    module_function

    # ─── Entry point ───────────────────────────────────────────────────────────────

    def run(argv = ARGV, format: :text)
      argv = argv.dup
      argv.shift if argv.first == '-Q'
      command = argv.shift || 'help'

      result = dispatch(command, argv)
      Rulepack::Reporter.print(result, format: format)
      result.failure? ? 1 : 0
    rescue StandardError => e
      warn "Error: #{e.message}"
      1
    end

    def dispatch(command, argv)
      meth = COMMANDS[command]
      if meth
        send(meth, argv)
      else
        Rulepack::Result.new(
          status: :failure,
          errors: ["Unknown command: #{command}"],
          messages: [print_help_text]
        )
      end
    end

    # ─── Data-returning public API ────────────────────────────────────────────────

    def packages
      index = load_index
      pkgs = (index[:packages] || {}).transform_values do |pkg|
        installed = Array(pkg[:installed]).map { |r| r[:platform] }.uniq
        pkg.merge(installed_platforms: installed)
      end

      Rulepack::Result.new(
        status: :success,
        data: { packages: pkgs },
        messages: ["📦 Packages (#{pkgs.size}):"]
      )
    end

    def platforms
      registry = Rulepack::Common.load_platform_registry
      Rulepack::Result.new(
        status: :success,
        data: { platforms: registry },
        messages: ["🎯 Platforms (#{registry.size}):"]
      )
    end

    def installed(platform_id = 'opencode', project_root: nil)
      platform_id = platform_id.to_s
      registry = Rulepack::Common.load_platform_registry
      platform_cfg = registry[platform_id.to_sym] || registry[platform_id]
      unless platform_cfg
        return Rulepack::Result.new(
          status: :failure,
          errors: ["Unknown platform: #{platform_id}"]
        )
      end

      platform_cfg = platform_cfg.merge(id: platform_id)
      base_path = Rulepack::InstallPlan.resolve_install_base_path(platform_cfg, project_root)
      index = load_index

      Rulepack::PlatformScanner.scan_platform(
        platform_id: platform_id,
        platform_cfg: platform_cfg,
        base_path: base_path,
        packages: index[:packages] || {},
        verify: false
      )
    end

    def show(pkgname)
      raise ArgumentError, 'Missing package name' unless pkgname

      index = load_index
      pkg = index[:packages][pkgname.to_sym] || index[:packages][pkgname]
      unless pkg
        return Rulepack::Result.new(
          status: :failure,
          errors: ["Package not found: #{pkgname}"]
        )
      end

      installed = Array(pkg[:installed]).map { |r| r[:platform] }.uniq
      data = pkg.merge(installed_platforms: installed)

      Rulepack::Result.new(
        status: :success,
        data: { package: data },
        messages: ["📦 #{pkgname}"]
      )
    end

    def search(keyword)
      raise ArgumentError, 'Missing search keyword' unless keyword

      index = load_index
      pkgs = index[:packages] || {}
      results = pkgs.select do |name, pkg|
        name.to_s.include?(keyword) ||
          pkg[:pkgdesc].to_s.include?(keyword) ||
          Array(pkg[:tags]).any? { |t| t.include?(keyword) }
      end

      Rulepack::Result.new(
        status: results.empty? ? :success : :success,
        data: { keyword: keyword, results: results },
        messages: results.empty? ? ["No packages found matching: #{keyword}"] : ["🔍 Search results for '#{keyword}':"]
      )
    end

    def orphans
      index = load_index
      pkgs = index[:packages] || {}
      orphan_records = []

      pkgs.each do |name, pkg|
        Array(pkg[:installed]).each do |rec|
          platform = rec[:platform]
          unless Array(pkg[:available_targets]).include?(platform)
            orphan_records << { name: name, platform: platform, output: rec[:output] }
          end
        end
      end

      status = orphan_records.empty? ? :success : :partial
      Rulepack::Result.new(
        status: status,
        data: { orphans: orphan_records },
        messages: orphan_records.empty? ? ['✅ No orphaned packages.'] : ["⚠️  Orphaned packages (#{orphan_records.size}):"]
      )
    end

    def depends(pkgname)
      raise ArgumentError, 'Missing package name' unless pkgname

      index = load_index
      pkg = index[:packages][pkgname.to_sym] || index[:packages][pkgname]
      unless pkg
        return Rulepack::Result.new(
          status: :failure,
          errors: ["Package not found: #{pkgname}"]
        )
      end

      deps = Array(pkg[:dependencies])
      Rulepack::Result.new(
        status: :success,
        data: { pkgname: pkgname, dependencies: deps },
        messages: deps.empty? ? ["#{pkgname} has no dependencies."] : ["#{pkgname} depends on:"]
      )
    end

    def provides(capability)
      index = load_index
      pkgs = index[:packages] || {}
      providers = pkgs.filter_map do |name, pkg|
        [name, pkg] if Array(pkg[:provides]).include?(capability)
      end.to_h

      Rulepack::Result.new(
        status: :success,
        data: { capability: capability, providers: providers },
        messages: providers.empty? ? ["No packages provide: #{capability}"] : ["Packages providing '#{capability}':"]
      )
    end

    def check
      index = load_index
      pkgs = index[:packages] || {}
      build_root = Rulepack::Common.build_dir
      build_index = begin
        Rulepack::Common.load_yaml(build_root.join('index.yaml'))
      rescue StandardError
        nil
      end

      issues = []
      pkgs.each do |name, pkg|
        Array(pkg[:installed]).each do |rec|
          platform = rec[:platform]

          unless Array(pkg[:available_targets]).include?(platform)
            issues << "#{name} installed on #{platform} but no target defined"
          end

          next unless build_index

          built = build_index[:packages]&.[](name.to_sym)
          built_checksums = built&.dig(:checksums, :built)
          checksum = built_checksums&.[](platform.to_s)
          issues << "#{name} checksum mismatch on #{platform}" if checksum && rec[:checksum] != checksum
        end
      end

      status = issues.empty? ? :success : :failure
      Rulepack::Result.new(
        status: status,
        data: { issues: issues },
        messages: issues.empty? ? ['✅ Database consistency check passed.'] : ['❌ Consistency issues found:']
      )
    end

    # ─── Per-command wrappers (used by CLI dispatch) ─────────────────────────────

    def cmd_list_packages(_argv)
      result = packages
      result
    end

    def cmd_list_platforms(_argv)
      platforms
    end

    def cmd_installed(argv)
      platform = argv.shift || 'opencode'
      installed(platform)
    end

    def cmd_show(argv)
      pkgname = argv.shift
      show(pkgname)
    end

    def cmd_search(argv)
      keyword = argv.shift
      search(keyword)
    end

    def cmd_check(_argv)
      check
    end

    def cmd_orphans(_argv)
      orphans
    end

    def cmd_depends(argv)
      pkgname = argv.shift
      depends(pkgname)
    end

    def cmd_provides(argv)
      capability = argv.shift
      provides(capability)
    end

    def cmd_help(_argv)
      Rulepack::Result.new(
        status: :success,
        data: {},
        messages: [print_help_text]
      )
    end

    # ─── Help ─────────────────────────────────────────────────────────────────────

    def print_help_text
      <<~HELP
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

    # Backward-compatible alias used by tests and external callers.
    def print_help
      puts print_help_text
    end

    # ─── Shared helpers ──────────────────────────────────────────────────────────

    def load_index
      root = Pathname.new(__dir__).parent.parent.expand_path
      yaml_path = root.join('data', 'index.yaml')
      build_path = root.join('build', 'index.yaml')

      installed = if yaml_path.exist?
                    data = Rulepack::Common.load_yaml(yaml_path)
                    data[:packages] || {}
                  else
                    {}
                  end

      build = if build_path.exist?
                Rulepack::Common.load_yaml(build_path)
              else
                {}
              end

      build[:packages] ||= {}
      build[:packages].each_key do |name|
        if installed[name]
          build[:packages][name][:installed] = installed[name][:installed]
          build[:packages][name][:installed] ||= []
        end
        build[:packages][name][:installed] ||= []
      end

      installed.each do |name, pkg|
        next if build[:packages][name]

        build[:packages][name] = pkg
      end

      build
    end

    # ─── Dispatch table ───────────────────────────────────────────────────────────

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
      'help'           => :cmd_help,
      'h'              => :cmd_help,
    }.freeze

    # ─── Backward-compatible public aliases ───────────────────────────────────────
    # Tests and external callers may still use the original method names directly.

    def list_packages(*args)
      raise ArgumentError, "list_packages takes no arguments (got #{args.size})" unless args.empty?

      packages
    end

    def list_platforms(*args)
      raise ArgumentError, "list_platforms takes no arguments (got #{args.size})" unless args.empty?

      platforms
    end

    # show, search, depends, provides aliases already return Result via public methods above.
    # Keep the legacy `check` and `orphans` aliases for external callers.

    def check_consistency(*args)
      raise ArgumentError, "check takes no arguments (got #{args.size})" unless args.empty?

      check
    end

    def list_orphans(*args)
      raise ArgumentError, "orphans takes no arguments (got #{args.size})" unless args.empty?

      orphans
    end

    def show_provides(capability)
      provides(capability)
    end
  end
end

# Run as script
exit Rulepack::Query.run(ARGV) if __FILE__ == $PROGRAM_NAME
