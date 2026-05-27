# frozen_string_literal: true

# Build orchestrator — thin coordinator
#
# P-B split: 430 LOC → ~150 LOC orchestrator.
#   build_loader.rb  — PKGBUILD discovery, load & validate, pkg_index init
#   build_per_pkg.rb  — source fetching, per-target pipeline, checksum recording
#   build_writer.rb   — build index write, catalog generation

require 'yaml'
require 'json'
require 'pathname'
require 'fileutils'
require 'digest'
require 'open3'
require_relative 'common'
require_relative 'schema_engine'
require_relative 'build_pipeline'
require_relative 'cli_parser'
require_relative 'build_loader'
require_relative 'build_per_pkg'
require_relative 'build_writer'

module Rulepack
  module Build
    module_function

    def run(options = {})
      Rulepack::Logging.log_level = options[:verbose] ? :debug : Rulepack::Config.log_level
      log_path = Rulepack::Common.build_dir.join('build.log')
      Rulepack::Logging.log_file = log_path

      # ─── Clean Build Directory ──────────────────────────────────────────────────────
      if Rulepack::Common.build_dir.exist?
        puts "🧹 Cleaning stale build directory: #{Rulepack::Common.build_dir.relative_path_from(Rulepack::Common::RULEPACK_ROOT)}"
        FileUtils.rm_rf(Rulepack::Common.build_dir)
      end
      Rulepack::Common.build_dir.mkdir

      Rulepack::Common.log '🔧 Loading platform registry...'
      platforms = Rulepack::Common.load_platform_registry

      # ─── Auto-generate build schema from PKGBUILD targets ──────────────────────────
      # SchemaGenerator scans all PKGBUILD files and derives the (platform, format)
      # → {translate, transformer} defaults for data/build_schema.yaml.  This keeps
      # the schema in sync with actual PKGBUILD targets on every build.
      begin
        require_relative 'schema_generator'
        Rulepack::SchemaGenerator.generate!
      rescue StandardError => e
        Rulepack::Common.log_warn "SchemaGenerator: pre-build step failed (#{e.class}: #{e.message}); continuing with existing schema"
      end

      index_data = {
        version: 3.0,
        generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        packages: {}
      }

      # ─── Discover PKGBUILDs ────────────────────────────────────────────────────────

      pkgbuilds = BuildLoader.discover_pkgbuilds
      Rulepack::Common.log "📦 Found #{pkgbuilds.size} package(s)"
      puts "📦 Found #{pkgbuilds.size} package(s)\n\n"

      # ─── Build each package ─────────────────────────────────────────────────────────

      pkgbuilds.each do |pkgbuild_path|
        # Load and validate
        result = BuildLoader.load_and_validate_pkgbuild(pkgbuild_path)
        next unless result

        pkg, pkgname = result

        BuildLoader.expand_targets(pkg, platforms)

        Rulepack::Common.log "Building: #{pkgname} (#{Rulepack::Common.format_version(pkg[:epoch], pkg[:pkgver],
                                                                                      pkg[:pkgrel])})"

        Rulepack::Common.time("build #{pkgname}") do
          puts "Building: #{pkgname} (#{Rulepack::Common.format_version(pkg[:epoch], pkg[:pkgver],
                                                                        pkg[:pkgrel])})"

          pkg_dir = pkgbuild_path.dirname

          # Initialize or update package index entry
          pkg_index = index_data[:packages][pkgname] || BuildLoader.init_pkg_index(pkg)
          BuildLoader.update_pkg_index_from_pkg(pkg_index, pkg)

          # ─── Fetch source ────────────────────────────────────────────────────────────
          source_content = BuildPerPkg.fetch_source(pkg, pkgname, pkg_index, pkg_dir)
          next unless source_content

          # ─── Process each target ──────────────────────────────────────────────────────
          BuildPerPkg.process_targets(pkg, pkgname, pkg_index, platforms, source_content)

          # Update index
          index_data[:packages][pkgname] = pkg_index
        end
      end

      # ─── Write build index + catalog ───────────────────────────────────────────────

      BuildWriter.write_build_index(index_data)
      BuildWriter.generate_catalog

      puts '✅ Build complete. Run `ruby lib/rulepack/install.rb <platform>` to install packages.'
      true
    end
  end
end

# CLI runner block
if __FILE__ == $PROGRAM_NAME || caller.any? { |c| c.include?('capture_script_run') || c.include?('invoke') }
  begin
    opts = Rulepack::CliParser.parse(ARGV)
    Rulepack::Build.run(opts)
  rescue StandardError => e
    $stderr.puts "❌ Error: #{e.message}"
    exit 1
  end
end
