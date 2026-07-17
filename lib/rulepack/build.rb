# frozen_string_literal: true

# Build orchestrator — thin coordinator
#
# P-B split: 430 LOC → ~150 LOC orchestrator.
#   build_loader.rb  — PKGBUILD discovery, load & validate, pkg_index init
#   build_per_pkg.rb  — source fetching, per-target pipeline, checksum recording
#   build_writer.rb   — build index write, catalog generation

require_relative 'encoding_defaults'
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

      built = []
      failed = []

      pkgbuilds.each do |pkgbuild_path|
        result = BuildLoader.load_and_validate_pkgbuild(pkgbuild_path)
        unless result
          failed << pkgbuild_path.basename.to_s
          next
        end

        pkg, pkgname = result
        BuildLoader.expand_targets(pkg, platforms)

        Rulepack::Common.log "Building: #{pkgname} (#{Rulepack::Common.format_version(pkg[:epoch], pkg[:pkgver],
                                                                                      pkg[:pkgrel])})"

        build_ok = false
        Rulepack::Common.time("build #{pkgname}") do
          Rulepack::Common.spin("Building: #{pkgname} (#{Rulepack::Common.format_version(pkg[:epoch], pkg[:pkgver], pkg[:pkgrel])})") do
            pkg_dir = pkgbuild_path.dirname
            pkg_index = index_data[:packages][pkgname] || BuildLoader.init_pkg_index(pkg)
            BuildLoader.update_pkg_index_from_pkg(pkg_index, pkg)

            source_content = BuildPerPkg.fetch_source(pkg, pkgname, pkg_index, pkg_dir)
            unless source_content
              failed << pkgname.to_s
              next
            end

            BuildPerPkg.process_targets(pkg, pkgname, pkg_index, platforms, source_content)
            index_data[:packages][pkgname] = pkg_index
            build_ok = true
          end
        end

        Rulepack::Common.log "  ✓ Built: #{pkgname}" if build_ok
        built << pkgname.to_s if build_ok
      end

      # ─── Write build index + catalog ───────────────────────────────────────────────

      BuildWriter.write_build_index(index_data)
      BuildWriter.generate_catalog

      status = failed.empty? ? :success : :partial
      messages = ['✅ Build complete. Run `ruby lib/rulepack/install.rb <platform>` to install packages.']
      messages << "⚠ #{failed.size} package(s) failed: #{failed.join(', ')}" if failed.any?

      Rulepack::Result.new(
        status: status,
        data: {
          packages_built: built,
          packages_failed: failed,
          packages_skipped: pkgbuilds.map { |p| BuildLoader.load_and_validate_pkgbuild(p)&.last.to_s }.compact - built - failed,
          build_dir: Rulepack::Common.build_dir,
          index_path: Rulepack::Common.build_index_path
        },
        messages: messages
      )
    end
  end
end

# CLI runner block
if __FILE__ == $PROGRAM_NAME || caller.any? { |c| c.include?('capture_script_run') || c.include?('invoke') }
  begin
    opts = Rulepack::CliParser.parse(ARGV)
    result = Rulepack::Build.run(opts)
    Rulepack::Reporter.print(result, format: opts[:format] || :text)
    exit(result.failure? ? 1 : 0)
  rescue StandardError => e
    $stderr.puts "❌ Error: #{e.message}"
    exit 1
  end
end
