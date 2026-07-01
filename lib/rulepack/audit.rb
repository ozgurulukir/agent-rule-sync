# frozen_string_literal: true

require_relative 'encoding_defaults'
require 'yaml'
require 'pathname'
require 'json'
require 'time'
require_relative 'common'
require_relative 'validation'
require_relative 'build_loader'
require_relative 'build_loader'

module Rulepack
  module Audit
    module_function

    def run(argv)
      opts = Rulepack::CliParser.parse(argv)
      strict = opts.fetch(:strict, false)
      target_filter = opts[:target]
      format = opts.fetch(:format, :text)

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

      all_valid = true

      Rulepack::PackageResolver.each_pkgbuild(namespaces: :all) do |pkgbuild_path, namespace|
        pkg_dir = pkgbuild_path.dirname
        pkgname = pkg_dir.basename.to_s

        pkg_result = {
          name: pkgname,
          namespace: namespace,
          valid: true,
          errors: [],
          warnings: [],
          details: nil
        }

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
        # Apply auto-expansion (same logic as build engine) for strict audit
        # expand_targets mutates data[:targets] in-place and returns the expanded array
        expanded_targets = Rulepack::BuildLoader.expand_targets(data.dup, platforms_registry) || []
        targeted_platforms = expanded_targets.map { |t| t[:platform] }.uniq

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

        # Strict check: all 14 platforms must be targeted (after auto-expansion)
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
        ns_label = pkg[:namespace] ? " (#{pkg[:namespace]})" : ''
        puts "\n\e[1m📦 Package: #{pkg[:name]}#{ns_label}\e[0m [#{status_color}]"

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
