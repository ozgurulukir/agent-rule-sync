# frozen_string_literal: true

# Skill-bundle lazy materialization — ADR-2026-07-29
#
# Before this refactor, build_per_pkg.rb#build_skill_bundle_target copied
# the entire source_dir into build/<plat>/<pkg>/ for every target platform.
# For anthropics-skills (~85 MB) × 14 platforms, that produced 1.19 GB of
# identical copies in build/.
#
# After this refactor:
#   - build phase records pkg_index[:source_dir] / pkg_index[:source_sha256]
#     and does NOT copy anything for skill-bundle/agent format.
#   - install phase calls ensure_materialized! the first time it needs the
#     built tree, which copies source → build/<plat>/<pkg>/, applies Schema
#     Engine, and writes manifest.json derived from the materialized contents.
#   - verify / fix / uninstall paths still expect build/<plat>/<pkg>/ to
#     exist; ensure_materialized! is idempotent so they can call it freely.
#
# This is the Strangler Fig shim. The build path now writes nothing for
# skill-bundle format; the install path transparently materializes on demand.

require 'fileutils'
require 'digest'
require 'json'
require 'pathname'
require_relative '../platform'
require_relative '../schema_engine'
require_relative 'skill_bundle'

module Rulepack
  module SkillBundleLazy
    module_function

    # Build directory for a (platform, package) pair, given the build_index
    # entry. Returns Pathname. Does not check existence.
    def build_dir_for(build_index, platform_id, pkgname)
      Rulepack::Common.build_dir.join(platform_id.to_s, pkgname.to_s)
    end

    # Returns true if the materialized tree is up-to-date with the source.
    # A tree is "up-to-date" when:
    #   1. The build/<plat>/<pkg>/ directory exists.
    #   2. manifest.json exists.
    #   3. manifest's source_sha matches pkg_index[:source_sha256].
    def materialization_up_to_date?(build_pkg_dir, pkg_index)
      return false unless build_pkg_dir.directory?
      return false unless build_pkg_dir.join('manifest.json').exist?

      begin
        manifest = JSON.parse(build_pkg_dir.join('manifest.json').read)
      rescue JSON::ParserError
        return false
      end

      manifest['source_sha256'] == pkg_index[:source_sha256]
    end

    # Idempotent: ensures build/<plat>/<pkg>/ exists and is up-to-date with
    # source_dir. Performs cp_r + strip_symlinks + schema engine + manifest.
    # Returns Pathname to the materialized directory.
    #
    # `tgt` is the target spec (carries :format, :translate, :agent_config).
    # `platforms` is the full platform registry hash.
    def ensure_materialized!(pkgname, pkg_index, platform_id, tgt, platforms, manifest_generated: false, manifest_path: nil)
      source_dir_str = pkg_index[:source_dir]
      raise "internal error: source_dir not set for #{pkgname}" unless source_dir_str

      source_dir = Pathname.new(source_dir_str)
      raise "source_dir does not exist: #{source_dir}" unless source_dir.exist?

      build_pkg_dir = build_dir_for(pkg_index, platform_id, pkgname)
      return build_pkg_dir if materialization_up_to_date?(build_pkg_dir, pkg_index)

      build_pkg_dir.mkpath
      # Remove stale contents before re-copying (in case of partial prior state).
      FileUtils.rm_rf(build_pkg_dir.children)
      FileUtils.cp_r("#{source_dir}/.", build_pkg_dir, preserve: false)

      # Security: strip symlinks planted by untrusted sources.
      strip_symlinks_in_tree(build_pkg_dir)

      # Apply agent translator to .md files (matches old build_skill_bundle_target).
      if tgt[:format] == 'agent' && tgt[:translate]
        translator_cfg = tgt[:translate]
        translate_extra = { pkgdesc: (pkg_index[:pkgdesc] || ''), tags: (pkg_index[:tags] || []) }
        Dir.glob(build_pkg_dir.join('**', '*.md')).each do |md_file|
          next if File.symlink?(md_file)

          file_content = File.read(md_file)
          translated = Rulepack::Common.apply_translator(
            translator_cfg, file_content,
            pkgname: pkgname.to_s, extra_args: translate_extra
          )
          File.write(md_file, translated)
        end
      end

      # Apply Schema Engine to .md files.
      apply_schema_engine_to_directory(build_pkg_dir, tgt, platforms, tgt[:format])

      # Write manifest.json with source_sha256 so subsequent materialization
      # can detect staleness cheaply.
      manifest_data = Rulepack::Common.generate_skill_bundle_manifest(
        build_pkg_dir, pkgname, platform_id
      )
      manifest_data['source_sha256'] = pkg_index[:source_sha256]
      manifest_data['generated_at'] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      manifest_path = build_pkg_dir.join('manifest.json')
      manifest_path.write(JSON.pretty_generate(manifest_data))

      # Optional: agent.json for agent format.
      if tgt[:format] == 'agent' && tgt[:agent_config]
        agent_cfg = tgt[:agent_config]
        manifest = {
          'name' => pkgname.to_s,
          'description' => (pkg_index[:pkgdesc] || '').to_s.strip.tr("\n", ' '),
          'model' => agent_cfg[:model] || 'claude-3.5-sonnet',
          'temperature' => agent_cfg[:temperature] || 0.3
        }
        if agent_cfg[:triggers]
          manifest['triggers'] = agent_cfg[:triggers].transform_keys(&:to_s)
        end
        File.write(build_pkg_dir.join('agent.json'), JSON.pretty_generate(manifest))
      end

      build_pkg_dir
    end

    # ─── Helpers (extracted from build_per_pkg.rb) ─────────────────────────────

    def apply_schema_engine_to_directory(build_pkg_dir, tgt, platforms, format)
      platform_id = tgt[:platform]
      format_profile = begin
        Rulepack::Common.platform_config(platform_id, platforms)[:format_profile]
      rescue StandardError
        {}
      end
      return if format_profile.nil? || format_profile.empty?

      schema_section = %w[skill skill-bundle].include?(format) ? :skills : :rules
      ruleset = format_profile[schema_section]
      return unless ruleset

      md_files = Dir.glob(build_pkg_dir.join('**', '*.md'))
      return if md_files.empty?

      applied = 0
      md_files.each do |md_file|
        next if File.symlink?(md_file)

        content = File.read(md_file)
        normalized = Rulepack::SchemaEngine.apply(content, format_profile, format)
        unless normalized == content
          File.write(md_file, normalized)
          applied += 1
        end
      end

      Rulepack::Common.log "    ✓ Schema Engine applied to #{applied} file(s) in directory build" if applied > 0
      puts "    ✓ Schema Engine applied to #{applied} file(s) in directory build" if applied > 0
    end

    def strip_symlinks_in_tree(root)
      return unless Dir.exist?(root)

      Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH).each do |entry|
        next if entry == root

        File.unlink(entry) if File.symlink?(entry)
      end
    end
  end
end
