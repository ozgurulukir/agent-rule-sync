# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'json'
require 'time'
require_relative 'common'
require_relative 'validation'

module Rulepack
  module Audit
    module_function

    def run(argv)
      strict = false
      target_filter = nil
      format = :text
      
      # Parse arguments
      args = argv.dup
      while (arg = args.shift)
        case arg
        when '--strict', '-s'
          strict = true
        when '--target', '-t'
          target_filter = args.shift
          unless target_filter
            $stderr.puts "❌ Error: --target requires a platform name."
            exit 1
          end
        when '--format'
          fmt_val = args.shift
          if fmt_val == 'json'
            format = :json
          elsif fmt_val == 'text'
            format = :text
          else
            $stderr.puts "❌ Error: --format must be 'text' or 'json'."
            exit 1
          end
        when '--help', '-h'
          print_help
          return 0
        else
          $stderr.puts "❌ Error: Unknown argument '#{arg}'. Run 'rulepack audit --help' for usage."
          exit 1
        end
      end

      # Locate root and directories
      root = Rulepack::Common::RULEPACK_ROOT
      packages_dir = root.join('data', 'packages')
      
      # Load system platforms
      begin
        platforms_registry = Rulepack::Common.load_platform_registry
        all_platforms = platforms_registry.keys.map(&:to_s)
      rescue StandardError => e
        $stderr.puts "❌ Error loading platforms registry: #{e.message}"
        exit 1
      end

      if target_filter && !all_platforms.include?(target_filter)
        $stderr.puts "❌ Error: Unknown platform '#{target_filter}' specified in --target. Supported: #{all_platforms.join(', ')}"
        exit 1
      end

      audit_results = {
        meta: {
          timestamp: Time.now.iso8601,
          total_platforms: all_platforms.size,
          strict_mode: strict,
          target_filter: target_filter
        },
        packages: []
      }

      package_dirs = packages_dir.children.select(&:directory?).sort
      all_valid = true

      package_dirs.each do |pkg_dir|
        pkgname = pkg_dir.basename.to_s
        pkgbuild_path = pkg_dir.join('PKGBUILD')
        
        pkg_result = {
          name: pkgname,
          valid: true,
          errors: [],
          warnings: [],
          details: nil
        }

        unless pkgbuild_path.exist?
          pkg_result[:valid] = false
          pkg_result[:errors] << "Missing PKGBUILD file at #{pkgbuild_path}"
          audit_results[:packages] << pkg_result
          all_valid = false
          next
        end

        # 1. Parse YAML
        begin
          data = Rulepack::Common.load_yaml(pkgbuild_path)
          pkg_result[:details] = {
            version: "#{data[:epoch] || 0}:#{data[:pkgver]}-#{data[:pkgrel] || 1}",
            description: data[:pkgdesc]
          }
        rescue StandardError => e
          pkg_result[:valid] = false
          pkg_result[:errors] << "YAML Parse Error: #{e.message}"
          audit_results[:packages] << pkg_result
          all_valid = false
          next
        end

        # 2. Schema Validation
        validation_res = Rulepack::Common.validate_pkgbuild(data, pkg_dir)
        if validation_res != true
          pkg_result[:valid] = false
          pkg_result[:errors] << "Schema Validation: #{validation_res}"
          all_valid = false
        end

        # 3. Source Existence check (for local sources)
        (data[:source] || []).each do |src|
          if src[:type] == 'local'
            src_path = pkg_dir.join(src[:path])
            unless src_path.exist?
              pkg_result[:valid] = false
              pkg_result[:errors] << "Local source file not found: #{src[:path]}"
              all_valid = false
            end
          end
        end

        # 4. Target Platforms Check
        targets = data[:targets] || []
        targeted_platforms = targets.map { |t| t[:platform] }.uniq
        
        # Check for unknown platforms in targets
        unknown_platforms = targeted_platforms - all_platforms
        unless unknown_platforms.empty?
          pkg_result[:valid] = false
          pkg_result[:errors] << "Targets defined for unknown platforms: #{unknown_platforms.join(', ')}"
          all_valid = false
        end

        # Apply target filter if specified
        if target_filter
          has_target = targeted_platforms.include?(target_filter)
          unless has_target
            pkg_result[:warnings] << "Platform '#{target_filter}' is not targeted by this package."
          end
        end

        # Strict check: all 14 platforms must be targeted
        if strict
          missing_platforms = all_platforms - targeted_platforms
          unless missing_platforms.empty?
            msg = "Missing targets for platform(s): #{missing_platforms.join(', ')}"
            if strict
              pkg_result[:valid] = false
              pkg_result[:errors] << msg
              all_valid = false
            else
              pkg_result[:warnings] << msg
            end
          end
        end

        audit_results[:packages] << pkg_result
      end

      # Render results
      if format == :json
        puts JSON.pretty_generate(audit_results)
      else
        print_text_report(audit_results)
      end

      # Exit code
      all_valid ? 0 : 1
    end

    def print_text_report(results)
      puts "\e[1m==================================================\e[0m"
      puts "\e[1;36m🔍 Rulepack PKGBUILD Audit Report\e[0m"
      puts "\e[1m==================================================\e[0m"
      puts "Strict Mode: #{results[:meta][:strict_mode] ? "\e[1;32mON\e[0m" : "\e[1;33mOFF\e[0m"}"
      puts "Target Filter: #{results[:meta][:target_filter] || 'None'}"
      puts "Total packages: #{results[:packages].size}"
      puts "--------------------------------------------------"

      failures = 0
      results[:packages].each do |pkg|
        status_color = pkg[:valid] ? "\e[1;32m✓ VALID\e[0m" : "\e[1;31m❌ INVALID\e[0m"
        puts "\n\e[1m📦 Package: #{pkg[:name]}\e[0m [#{status_color}]"
        
        if pkg[:details]
          puts "  Version: #{pkg[:details][:version]}"
          puts "  Desc:    #{pkg[:details][:description]}"
        end

        pkg[:errors].each do |err|
          puts "  \e[31mError: #{err}\e[0m"
          failures += 1
        end

        pkg[:warnings].each do |warn|
          puts "  \e[33mWarning: #{warn}\e[0m"
        end
        
        if pkg[:errors].empty? && pkg[:warnings].empty?
          puts "  \e[32m✓ All checks passed perfectly.\e[0m"
        end
      end

      puts "\e[1m--------------------------------------------------\e[0m"
      puts "\e[1m📊 Audit Summary:\e[0m"
      if failures == 0
        puts "\e[1;32m🎉 Success! All PKGBUILD files conform perfectly to specifications.\e[0m"
      else
        puts "\e[1;31m❌ Failure! Found #{failures} total error(s) across packages.\e[0m"
      end
      puts "\e[1m==================================================\e[0m"
    end

    def print_help
      puts <<~HELP
        Rulepack Audit Tool — Verify integrity of all declarative package descriptors

        Usage: rulepack audit [options]

        Options:
          -s, --strict           Enforce strict compliance (e.g. all 14 platforms targeted)
          -t, --target PLAT      Filter audit checks/warnings to specific platform
          --format <text|json>   Choose output format (default: text)
          -h, --help             Show this help screen
      HELP
    end
  end
end

exit Rulepack::Audit.run(ARGV) if __FILE__ == $PROGRAM_NAME
