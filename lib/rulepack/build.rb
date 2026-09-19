# frozen_string_literal: true

# Build orchestrator — thin coordinator
#
# P-B split: 430 LOC → ~150 LOC orchestrator.
#   build_loader.rb  — PKGBUILD discovery, load & validate, target expansion
#   build_per_pkg.rb  — source fetching, per-target pipeline, checksum recording
#   build_writer.rb   — build index write, catalog generation

require_relative 'encoding_defaults'
require 'yaml'
require 'json'
require 'pathname'
require 'fileutils'
require 'digest'
require 'open3'
require_relative 'models/package'
require_relative 'models/platform'
require_relative 'models/target'
require_relative 'models/build_record'
require_relative 'common'
require_relative 'schema_engine'
require_relative 'build_loader'
require_relative 'build_per_pkg'
require_relative 'build_writer'

module Rulepack
  module Build
    module_function

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
      Rulepack::Logging.log_level = options[:verbose] ? :debug : Rulepack::Config.log_level
      log_path = Rulepack::Common.build_dir.join('build.log')
      Rulepack::Logging.log_file = log_path

      # ─── Clean Build Directory ──────────────────────────────────────────────────────
      if Rulepack::Common.build_dir.exist?
        Rulepack::Emitter.emit(:progress, message: "🧹 Cleaning stale build directory: #{Rulepack::Common.build_dir.relative_path_from(Rulepack::Common.paths.root)}")
        FileUtils.rm_rf(Rulepack::Common.build_dir)
        sleep 0.1 # wait for Windows file system to catch up
      end
      FileUtils.mkpath(Rulepack::Common.build_dir)

      Rulepack::Emitter.emit(:progress, message: '🔧 Loading platform registry...')
      platforms = Rulepack::Common.load_platform_registry
      if options[:target] && options[:target].to_s != 'all'
        target_list = options[:target].to_s.split(',').map(&:strip)
        platforms = platforms.select { |id, _| target_list.include?(id.to_s) }
        if platforms.empty?
          return Rulepack::Result.new(
            status: :failure,
            errors: ["❌ Build failed: No matching platforms found for target '#{options[:target]}'."]
          )
        end
        Rulepack::Emitter.emit(:progress, message: "🎯 Filtering targets for platform(s): #{target_list.join(', ')}")
        Rulepack::Emitter.emit(:progress, message: "🎯 Filtering targets for platform(s): #{target_list.join(', ')}\n\n")
      end

      # BuildIndex.write owns the envelope (version, :generated) — this hash
      # only accumulates the package map.
      index_data = { packages: {} }

      # ─── Discover PKGBUILDs ────────────────────────────────────────────────────────

      pkgbuilds = BuildLoader.discover_pkgbuilds
      Rulepack::Emitter.emit(:progress, message: "📦 Found #{pkgbuilds.size} package(s)")
      Rulepack::Emitter.emit(:progress, message: "📦 Found #{pkgbuilds.size} package(s)\n\n")

      # ─── Build each package ─────────────────────────────────────────────────────────

      built = []
      failed = []
      all_discovered = []

      pkgbuilds.each do |pkgbuild_path|
        result = BuildLoader.load_and_validate_pkgbuild(pkgbuild_path)
        unless result
          failed << pkgbuild_path.dirname.basename.to_s
          next
        end

        pkg, pkgname = result
        all_discovered << pkgname.to_s

        pkg = BuildLoader.expand_targets(pkg, platforms)
        record = BuildRecord.from_package(pkg)

        Rulepack::Common.log "Building: #{pkgname} (#{Rulepack::Common.format_version(pkg.epoch, pkg.pkgver,
                                                                                      pkg.pkgrel)})"

        build_attempted = true
        build_ok = false
        Rulepack::Common.time("build #{pkgname}") do
          Rulepack::Common.spin("Building: #{pkgname} (#{Rulepack::Common.format_version(pkg.epoch, pkg.pkgver, pkg.pkgrel)})") do
            pkg_dir = pkgbuild_path.dirname

            source_content, record = BuildPerPkg.fetch_source(pkg, pkgname, record, pkg_dir)
            unless source_content
              failed << pkgname.to_s
              build_attempted = false
              next
            end

            build_ok, record = BuildPerPkg.process_targets(pkg, pkgname, record, platforms, source_content)
            # Serialize only successful packages: to_h enforces the
            # materializable-needs-source_sha256 invariant, which a failed
            # fetch would violate.
            index_data[:packages][pkgname] = record.to_h if build_ok
          end
        end

        Rulepack::Emitter.emit(:progress, message: "  ✓ Built: #{pkgname}") if build_ok
        if build_ok
          built << pkgname.to_s
        elsif build_attempted
          failed << pkgname.to_s
        end
      end

      # ─── Write build index + catalog ───────────────────────────────────────────────

      unless BuildWriter.write_build_index(index_data)
        return Rulepack::Result.new(
          status: :failure,
          data: {},
          messages: ['❌ Build failed: Could not write build index.']
        )
      end
      BuildWriter.generate_catalog

      status = failed.empty? ? :success : :partial
      messages = ['✅ Build complete. Run `rulepack install <platform>` to install packages.']
      messages << "⚠ #{failed.size} package(s) failed: #{failed.join(', ')}" if failed.any?

      Rulepack::Result.new(
        status: status,
        view: :build,
        data: {
          packages_built: built,
          packages_failed: failed,
          packages_skipped: all_discovered - built - failed,
          build_dir: Rulepack::Common.build_dir,
          index_path: Rulepack::Common.build_index_path
        },
        messages: messages
      )
    end
  end
end

