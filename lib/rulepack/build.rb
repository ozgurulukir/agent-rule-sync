# frozen_string_literal: true

require 'yaml'
require 'json'
require 'pathname'
require 'fileutils'
require 'digest'
require 'net/http'
require 'uri'
require 'open3'
require_relative 'common'
require_relative 'schema_engine'
require_relative 'build_pipeline'
require_relative 'cli_parser'

module Rulepack
  module Build
    module_function

    def run(options = {})
      Rulepack::Common.log_level = options[:verbose] ? :debug : Rulepack::Config.log_level
      log_path = Rulepack::Common.build_dir.join('build.log')
      Rulepack::Common.log_file = log_path

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

      pkgbuilds = Rulepack::Common::RULEPACK_ROOT.join('data', 'packages').glob('*/PKGBUILD')
      Rulepack::Common.log "📦 Found #{pkgbuilds.size} package(s)"
      puts "📦 Found #{pkgbuilds.size} package(s)\n\n"

      # ─── Build each package ─────────────────────────────────────────────────────────

      pkgbuilds.each do |pkgbuild_path|
        pkg_dir = pkgbuild_path.dirname
        pkg = Rulepack::Common.load_pkgbuild(pkg_dir)

        pkgname = pkg[:pkgname].to_sym

        # Set default epoch/pkgrel before validation (PKGBUILD may omit them)
        pkg[:epoch] = 0 unless pkg.key?(:epoch)
        pkg[:pkgrel] = 1 unless pkg.key?(:pkgrel)

        # Validate PKGBUILD
        validation_error = Rulepack::Common.validate_pkgbuild(pkg, pkg_dir)
        if validation_error != true
          Rulepack::Common.log_error "PKGBUILD validation failed for #{pkgname}: #{validation_error}"
          next
        end

        Rulepack::Common.log "Building: #{pkgname} (#{Rulepack::Common.format_version(pkg[:epoch], pkg[:pkgver],
                                                                                      pkg[:pkgrel])})"

        Rulepack::Common.time("build #{pkgname}") do
          puts "Building: #{pkgname} (#{Rulepack::Common.format_version(pkg[:epoch], pkg[:pkgver],
                                                                        pkg[:pkgrel])})"

          # Initialize package index entry if missing
          pkg_index = index_data[:packages][pkgname] || {
            pkgver: pkg[:pkgver],
            pkgrel: pkg[:pkgrel],
            epoch: pkg[:epoch],
            pkgdesc: pkg[:pkgdesc],
            order: pkg[:order] || 0,
            status: 'stable',
            installed: [],
            available_targets: [],
            dependencies: pkg[:dependencies] || [],
            conflicts: pkg[:conflicts] || [],
            provides: pkg[:provides] || [],
            tags: pkg[:tags] || [],
            checksums: { source: nil, built: {} }
          }
          # Always update version fields (epoch/pkgrel may have changed in PKGBUILD)
          pkg_index[:pkgver] = pkg[:pkgver]
          pkg_index[:pkgrel] = pkg[:pkgrel]
          pkg_index[:epoch] = pkg[:epoch]

          # Always update targets (they may have changed)
          pkg_index[:targets] = pkg[:targets] || []

          # ─── Fetch source ────────────────────────────────────────────────────────────

          # Determine if all targets are skill-bundle (source is a directory)
          all_skill_bundle = pkg[:targets].all? { |t| %w[skill-bundle agent].include?(t[:format]) }

          skip_pkg = false

          if all_skill_bundle
            # ─── skill-bundle: source must be a directory (local or git) ──────────────────
            src_cfg = pkg[:source].first
            unless src_cfg
              Rulepack::Common.log_error "No source defined for #{pkgname} (skill-bundle)"
              next
            end

            case src_cfg[:type]
            when 'local'
              src_path = src_cfg[:path]
              source_dir = if src_path.start_with?('/') || src_path.start_with?('~')
                             Pathname.new(Rulepack::Common.expand_user_path(src_path))
                           else
                             pkg_dir.join(src_path)
                           end
              source_dir = source_dir.cleanpath
              unless source_dir.directory?
                Rulepack::Common.log_error "Source path must be a directory for skill-bundle: #{source_dir}"
                next
              end
              pkg_index[:source_dir] = source_dir.to_s
              pkg_index[:source_sha256] = nil

              # Run pkgver_func if defined
              skip_pkg = true unless run_pkgver_func(pkg, pkgname, pkg_index, source_dir)

              Rulepack::Common.log "  ✓ Source directory verified: #{source_dir}"
              puts "  ✓ Source directory verified: #{source_dir}"
            when 'git'
              git_url = src_cfg[:url]
              git_ref = src_cfg[:ref] || 'main'
              git_path = Pathname.new(src_cfg[:path] || '.')
              git_depth = src_cfg[:depth] || 1
              Rulepack::Common.log "  Fetching git repo (cached): #{git_url} (ref: #{git_ref})"
              cached_dir, commit_hash = Rulepack::Common.cached_fetch_git_dir(git_url, git_ref, git_path,
                                                                              depth: git_depth)
              persistent_dir = Rulepack::Common.build_dir.join('git-sources', pkgname.to_s)
              FileUtils.rm_rf(persistent_dir)
              FileUtils.mkpath(persistent_dir.parent)
              FileUtils.cp_r(cached_dir, persistent_dir)
              pkg_index[:source_dir] = persistent_dir.to_s
              pkg_index[:source_sha256] = commit_hash
              Rulepack::Common.log "  ✓ Git source cached/build dir (#{commit_hash[0..7]})"
              puts "  ✓ Git source cached/build dir (#{commit_hash[0..7]})"

              skip_pkg = true unless run_pkgver_func(pkg, pkgname, pkg_index, persistent_dir)
            else
              Rulepack::Common.log_error "skill-bundle only supports 'local' or 'git' source type, got: #{src_cfg[:type]}"
              next
            end
            next if skip_pkg

            pkg_index[:checksums][:source] = pkg_index[:source_sha256]
          else
            # ─── Non-skill-bundle: fetch file content (local/url/git) ───────────────────
            source_content = nil
            source_sha256 = nil

            sources = pkg[:source]
            sources = [sources] unless sources.is_a?(Array)

            src_cfg = sources.first
            unless src_cfg
              Rulepack::Common.log_warn "  ⚠ No source defined for #{pkgname}, skipping"
              next
            end

            case src_cfg[:type]
            when 'local'
              source_content, source_sha256 = Rulepack::Common.read_source(src_cfg, pkg_dir)
            when 'url'
              url = src_cfg[:url]
              expected = src_cfg[:sha256]
              source_content, source_sha256 = Rulepack::Common.cached_fetch_url(url, expected)
              # Update PKGBUILD with fetched sha256
              if src_cfg[:sha256] != source_sha256
                src_cfg[:sha256] = source_sha256
                pkgbuild_path.write(pkg.to_yaml)
              end
            when 'git'
              git_url = src_cfg[:url]
              git_ref = src_cfg[:ref] || 'main'
              git_path = Pathname.new(src_cfg[:path] || '.')
              git_depth = src_cfg[:depth] || 1
              Rulepack::Common.log "  Fetching git file (cached): #{git_url} (#{git_path})"
              source_content, source_sha256 = Rulepack::Common.cached_fetch_git_file(git_url, git_ref, git_path,
                                                                                     depth: git_depth)
            else
              Rulepack::Common.log_warn "  ⚠ Unknown source type: #{src_cfg[:type]} for #{pkgname}"
              next
            end

            pkg_index[:checksums][:source] = source_sha256
            Rulepack::Common.log "  ✓ Fetched source (#{source_sha256[0..7]})"
            puts "  ✓ Fetched source (#{source_sha256[0..7]})"

            # For URL sources, update PKGBUILD with fetched sha256
            if src_cfg[:type] == 'url' && src_cfg[:sha256] != source_sha256
              src_cfg[:sha256] = source_sha256
              pkgbuild_path.write({ **pkg, source: sources }.to_yaml)
            end
          end

          # ─── Process each target ──────────────────────────────────────────────────────
          targets = pkg[:targets]
          targets = [targets] unless targets.is_a?(Array)

          manifest_generated = false
          manifest_path = nil

          targets.each do |tgt|
            platform_id = tgt[:platform]
            format = tgt[:format]
            output = tgt[:output]
            translate = tgt[:translate] || nil # optional translate step (before transformer)
            transformer = tgt[:transformer] || 'copy'

            if %w[skill-bundle agent].include?(format)
              Rulepack::Common.log "  → Building for #{platform_id} (skill-bundle: #{pkgname})"
              puts "  → Building for #{platform_id} (skill-bundle: #{pkgname})"

              sd = pkg_index[:source_dir] || raise('internal error: source_dir not set for skill-bundle')
              source_dir = Pathname.new(sd)
              build_platform_dir = Rulepack::Common.build_dir.join(platform_id)
              begin
                build_pkg_dir = build_platform_dir.join(pkgname.to_s)
                FileUtils.mkpath(build_pkg_dir)
                FileUtils.cp_r("#{source_dir}/.", build_pkg_dir, preserve: false)
              rescue StandardError => e
                Rulepack::Common.log_error "Failed to copy skill-bundle source: #{e.message}"
                next
              end

              Rulepack::Common.log '    ✓ Built skill-bundle (directory copied)'
              puts '    ✓ Built skill-bundle (directory copied)'

              if manifest_generated
                FileUtils.cp(manifest_path, build_pkg_dir.join('manifest.json'))
              else
                manifest_data = Rulepack::Common.generate_skill_bundle_manifest(
                  build_pkg_dir, pkgname, platform_id
                )
                manifest_path = build_pkg_dir.join('manifest.json')
                manifest_generated = true
                count = manifest_data[:sub_skills].size
                Rulepack::Common.log "    ✓ Manifest generated: #{count} sub-skill(s)"
                puts "    ✓ Manifest generated: #{count} sub-skill(s)"
              end

              # Agent format: translate each .md file if translator specified
              if format == 'agent' && translate
                translator_cfg = translate
                Rulepack::Common.log "    → Translating agent files for #{platform_id} (#{translator_cfg})"
                puts "    → Translating agent files for #{platform_id} (#{translator_cfg})"
                translate_args = {
                  pkgname: pkgname,
                  pkgdesc: pkg[:pkgdesc],
                  tags: pkg[:tags]
                }
                translate_extra = { pkgdesc: pkg[:pkgdesc], tags: pkg[:tags] }
                Dir.glob(build_pkg_dir.join('**', '*.md')).each do |md_file|
                  file_content = File.read(md_file)
                  translated = Rulepack::Common.apply_translator(translator_cfg, file_content, pkgname: pkgname.to_s, extra_args: translate_extra)
                  File.write(md_file, translated)
                end
                Rulepack::Common.log "    ✓ Agent files translated (#{translator_cfg})"
                puts "    ✓ Agent files translated (#{translator_cfg})"
              end

              # Agent format: generate agent.json manifest from agent_config (Cursor)
              if format == 'agent' && tgt[:agent_config]
                agent_cfg = tgt[:agent_config]
                manifest = {
                  'name' => pkgname.to_s,
                  'description' => (pkg[:pkgdesc] || '').to_s.strip.tr("
", ' '),
                  'model' => agent_cfg[:model] || 'claude-3.5-sonnet',
                  'temperature' => agent_cfg[:temperature] || 0.3
                }
                if agent_cfg[:triggers]
                  manifest['triggers'] = agent_cfg[:triggers].transform_keys(&:to_s)
                end
                File.write(build_pkg_dir.join('agent.json'), JSON.pretty_generate(manifest))
                Rulepack::Common.log "    ✓ Generated agent.json manifest"
                puts "    ✓ Generated agent.json manifest"
              end

              # Record in package index (no single checksum for bundle; use source_sha256 i.e. commit hash or nil)
              pkg_index[:available_targets] << platform_id unless pkg_index[:available_targets].include?(platform_id)
              pkg_index[:checksums][:built][platform_id.to_s] = pkg_index[:source_sha256]
            else
              # Single-file formats: directory, import, skill
              Rulepack::Common.log "  → Building for #{platform_id} (#{output})"
              puts "  → Building for #{platform_id} (#{output})"

              # Validate output filename (path traversal protection)
              begin
                Rulepack::Common.validate_output_filename(output, pkgname)
              rescue StandardError => e
                Rulepack::Common.log_error e.message
                next
              end

              # ─── BUILD PIPELINE step ──────────────────────────────────────────────────
              begin
                format_profile = Rulepack::Common.platform_config(platform_id, platforms)[:format_profile]
                platform_cfg = Rulepack::Common.platform_config(platform_id, platforms)

                pipeline = Rulepack::BuildPipeline.new(
                  source_content,
                  platform_id: platform_id,
                  pkgname: pkgname,
                  target_format: tgt[:format],
                  format_profile: format_profile
                )
                transformed = pipeline.run(platform_cfg)
              rescue StandardError => e
                Rulepack::Common.log_error "Build pipeline failed for #{pkgname}/#{platform_id}: #{e.message}"
                next
              end

              transformed_sha256 = Digest::SHA256.hexdigest(transformed)

              # Write to build store & link to build directory
              begin
                # Write canonical file to build/store/
                store_dir = Rulepack::Common.build_dir.join('store')
                store_dir.mkpath
                store_file = store_dir.join(transformed_sha256)
                store_file.write(transformed) unless store_file.exist?

                # Build destination path
                build_platform_dir = Rulepack::Common.build_dir.join(platform_id, pkgname.to_s)
                build_file = build_platform_dir.join(output)
                build_file.parent.mkpath

                # Remove existing file/symlink
                FileUtils.rm_f(build_file)

                # Create relative symlink
                target_rel = store_file.relative_path_from(build_file.parent)
                FileUtils.ln_s(target_rel, build_file)
              rescue StandardError => e
                Rulepack::Common.log_error "Failed to write build artifact for #{pkgname}/#{platform_id}: #{e.message}"
                next
              end

              Rulepack::Common.log "    ✓ Built #{output} (#{transformed_sha256[0..7]})"
              puts "    ✓ Built #{output} (#{transformed_sha256[0..7]})"

              # Record in package index
              pkg_index[:available_targets] << platform_id unless pkg_index[:available_targets].include?(platform_id)
              pkg_index[:checksums][:built][platform_id.to_s] = transformed_sha256
            end
          end

          # Update index
          index_data[:packages][pkgname] = pkg_index
        end
      end

      # ─── Write build index ─────────────────────────────────────────────────────────

      build_index_data = {
        version: 3.0,
        generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        packages: index_data[:packages]
      }
      begin
        Rulepack::Common.write_yaml_atomic(Rulepack::Common::BUILD_INDEX_PATH, build_index_data)
        Rulepack::Common.log "📝 Build index written: #{Rulepack::Common::BUILD_INDEX_PATH}"
        puts "\n📝 Build index written: #{Rulepack::Common::BUILD_INDEX_PATH}"
      rescue StandardError => e
        Rulepack::Common.log_error "Failed to write build index: #{e.message}"
        exit 1
      end

      # ─── Generate catalog.json ─────────────────────────────────────────────────────

      begin
        load Rulepack::Common::RULEPACK_ROOT.join('lib', 'rulepack', 'generate-catalog.rb').to_s
      rescue StandardError => e
        Rulepack::Common.log_error "Failed to generate catalog: #{e.message}"
      end

      puts '✅ Build complete. Run `ruby lib/rulepack/install.rb <platform>` to install packages.'
      true
    end

    # Private Helpers

    def run_pkgver_func(pkg, pkgname, pkg_index, source_dir)
      return true unless pkg[:pkgver_func]

      Rulepack::Common.log "  Running pkgver_func: #{pkg[:pkgver_func]}"
      stdout_err, status = Dir.chdir(source_dir) do
        Open3.capture2e(pkg[:pkgver_func])
      end
      new_pkgver = stdout_err.strip
      unless status.success?
        Rulepack::Common.log_error "pkgver_func failed for #{pkgname}: #{stdout_err}"
        return false
      end
      if new_pkgver.empty?
        Rulepack::Common.log_error "pkgver_func returned empty version for #{pkgname}"
        return false
      end
      Rulepack::Common.log "  pkgver updated: #{pkg[:pkgver]} → #{new_pkgver}"
      pkg[:pkgver] = new_pkgver
      pkg_index[:pkgver] = new_pkgver
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
