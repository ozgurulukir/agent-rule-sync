# frozen_string_literal: true

require_relative 'encoding_defaults'
require 'yaml'
require 'pathname'
require 'json'
require 'time'
require_relative 'common'
require_relative 'validation'
require_relative 'models/package'
require_relative 'cli_parser'
require_relative 'build_loader'

module Rulepack
  module Audit
    module_function

    # options: the CliParser result (uses :strict and :target). Rendering is
    # the CLI's job (TextRenderer.render_audit / JsonRenderer); this method
    # only returns the structured Result.
    def run(options = {}, paths: nil, ui: nil)
      if ui
        Rulepack::Common.with_ui(ui) { run(options, paths: paths) }
      elsif paths
        Rulepack::Common.with_paths(paths) { run_unscoped(options) }
      else
        run_unscoped(options)
      end
    end

    def run_unscoped(options = {})
      strict = options.fetch(:strict, false)
      target_filter = options[:target]

      # Load system platforms
      begin
        platforms_registry = Rulepack::Common.load_platform_registry
        all_platforms = platforms_registry.keys.map(&:to_s)
      rescue StandardError => e
        $stderr.puts "❌ Error loading platforms registry: #{e.message}"
        return Rulepack::Result.new(status: :failure, errors: [e.message])
      end

      if target_filter && !all_platforms.include?(target_filter)
        $stderr.puts "❌ Error: Unknown platform '#{target_filter}' specified in --target. Supported: #{all_platforms.join(', ')}"
        return Rulepack::Result.new(status: :failure, errors: ["Unknown platform '#{target_filter}'"])
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
          data = Rulepack::IO.load_yaml(pkgbuild_path)
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
        validation_res = Rulepack::Validation.validate_pkgbuild(data, pkg_dir)
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
        # A hybrid package without explicit targets is invalid ? report it
        # instead of crashing the whole audit.
        begin
          expanded_pkg = Rulepack::BuildLoader.expand_targets(Rulepack::Package.from_hash(data), platforms_registry)
        rescue ArgumentError => e
          pkg_result[:valid] = false
          pkg_result[:errors] << e.message
          audit_results[:packages] << pkg_result
          all_valid = false
          next
        end
        targeted_platforms = expanded_pkg.targets.map(&:platform).uniq

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

      # Structured result ? the report itself is rendered by the CLI
      # (TextRenderer.render_audit for text; json/yaml via Reporter envelope).
      data = { audit: audit_results }
      if all_valid
        Rulepack::Result.new(status: :success, data: data, view: :audit)
      else
        Rulepack::Result.new(status: :failure, data: data, view: :audit)
      end
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

