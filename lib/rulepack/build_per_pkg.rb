# frozen_string_literal: true

# Build Per-Package — Source fetching and per-target artifact construction.
#
# Extracted from build.rb (P-B: split 430 LOC build.rb into 3 focused files).
# Requires build_loader.rb for pkg_index initialization helpers.

require 'pathname'
require_relative 'common'
require_relative 'schema_engine'
require_relative 'build_pipeline'
require_relative 'build_loader'

module Rulepack
  module BuildPerPkg
    module_function

    # ─── Fetch source ─────────────────────────────────────────────────────────────

    def fetch_source(pkg, pkgname, pkg_index, pkg_dir)
      # Determine if all targets are skill-bundle (source is a directory)
      all_skill_bundle = pkg[:targets].all? { |t| %w[skill-bundle agent].include?(t[:format]) }

      if all_skill_bundle
        fetch_skill_bundle_source(pkg, pkgname, pkg_index, pkg_dir)
        # skill-bundle: source is a directory; no source_content needed downstream
        true
      else
        source_content, _source_sha256 = fetch_file_source(pkg, pkgname, pkg_index, pkg_dir)
        source_content
      end
    end

    def fetch_skill_bundle_source(pkg, pkgname, pkg_index, pkg_dir)
      src_cfg = pkg[:source].first
      unless src_cfg
        Rulepack::Common.log_error "No source defined for #{pkgname} (skill-bundle)"
        return
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
          return
        end
        pkg_index[:source_dir] = source_dir.relative_path_from(Rulepack::Common::RULEPACK_ROOT).to_s
        pkg_index[:source_sha256] = nil

        run_pkgver_func(pkg, pkgname, pkg_index, source_dir) || return

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
        pkg_index[:source_dir] = persistent_dir.relative_path_from(Rulepack::Common::RULEPACK_ROOT).to_s
        pkg_index[:source_sha256] = commit_hash
        Rulepack::Common.log "  ✓ Git source cached/build dir (#{commit_hash[0..7]})"
        puts "  ✓ Git source cached/build dir (#{commit_hash[0..7]})"

        run_pkgver_func(pkg, pkgname, pkg_index, persistent_dir) || return
      else
        Rulepack::Common.log_error "skill-bundle only supports 'local' or 'git' source type, got: #{src_cfg[:type]}"
        return
      end

      pkg_index[:checksums][:source] = pkg_index[:source_sha256]
    end

    def fetch_file_source(pkg, pkgname, pkg_index, pkg_dir)
      sources = pkg[:source]
      sources = [sources] unless sources.is_a?(Array)

      src_cfg = sources.first
      unless src_cfg
        Rulepack::Common.log_warn "  ⚠ No source defined for #{pkgname}, skipping"
        return nil
      end

      source_content = nil
      source_sha256 = nil

      case src_cfg[:type]
      when 'local'
        source_content, source_sha256 = Rulepack::Common.read_source(src_cfg, pkg_dir)
      when 'url'
        url = src_cfg[:url]
        expected = src_cfg[:sha256]
        source_content, source_sha256 = Rulepack::Common.cached_fetch_url(url, expected)
        # NOTE: we intentionally do not rewrite the source PKGBUILD here.
        # Fetched checksums are stored in build/index.yaml; the PKGBUILD remains
        # the canonical user-editable descriptor.
        if expected && expected != source_sha256
          Rulepack::Common.log_warn "  ⚠ SHA256 mismatch for #{pkgname}: PKGBUILD has #{expected[0..7]}, fetched #{source_sha256[0..7]}. Update the PKGBUILD sha256 field."
        end
      when 'git'
        git_url = src_cfg[:url]
        git_ref = src_cfg[:ref] || 'main'
        git_path = Pathname.new(src_cfg[:path] || '.')
        git_depth = src_cfg[:depth] || 1
        Rulepack::Common.log "  Fetching git file (cached): #{git_url} (#{git_path})"
        source_content, source_sha256 = Rulepack::Common.spin("Fetching git file...") do
          Rulepack::Common.cached_fetch_git_file(git_url, git_ref, git_path, depth: git_depth)
        end
      else
        Rulepack::Common.log_warn "  ⚠ Unknown source type: #{src_cfg[:type]} for #{pkgname}"
        return nil
      end

      pkg_index[:checksums][:source] = source_sha256
      Rulepack::Common.log "  ✓ Fetched source (#{source_sha256[0..7]})"
      puts "  ✓ Fetched source (#{source_sha256[0..7]})"

      [source_content, source_sha256]
    end

    # ─── Process each target ──────────────────────────────────────────────────────

    def process_targets(pkg, pkgname, pkg_index, platforms, source_content)
      targets = pkg[:targets]
      targets = [targets] unless targets.is_a?(Array)

      manifest_generated = false
      manifest_path = nil

      success = true
      targets.each do |tgt|
        platform_id = tgt[:platform]
        format = tgt[:format]
        output = tgt[:output]
        translate = tgt[:translate] || nil
        transformer = tgt[:transformer] || 'copy'

        result = if %w[skill-bundle agent].include?(format)
          build_skill_bundle_target(pkg, pkgname, pkg_index, tgt, platforms, translate, manifest_generated, manifest_path)
        else
          build_single_file_target(pkg, pkgname, pkg_index, tgt, platforms, source_content, translate, transformer)
        end
        success = false unless result
      end
      success
    end


    def build_skill_bundle_target(pkg, pkgname, pkg_index, tgt, platforms, translate, manifest_generated, manifest_path)
      platform_id = tgt[:platform]
      format = tgt[:format]

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
        return false
      end

      # Security: strip any symlinks that survived cp_r (e.g. from an untrusted
      # git source). A symlinked .md would otherwise be followed by File.write /
      # path.read in later translate, schema-engine, and manifest steps, allowing
      # arbitrary file overwrite/read on the host. Mirrors the skip policy used by
      # extract_tar_gz in source.rb.
      strip_symlinks_in_tree(build_pkg_dir)

      Rulepack::Common.log '    ✓ Built skill-bundle (directory copied)'
      puts '    ✓ Built skill-bundle (directory copied)'

      # Agent format: translate each .md file if translator specified
      if format == 'agent' && translate
        translator_cfg = translate
        translate_extra = { pkgdesc: (pkg[:pkgdesc] || ''), tags: (pkg[:tags] || []) }
        Rulepack::Common.log "    → Translating agent files for #{platform_id} (#{translator_cfg})"
        puts "    → Translating agent files for #{platform_id} (#{translator_cfg})"
        Dir.glob(build_pkg_dir.join('**', '*.md')).each do |md_file|
          next if File.symlink?(md_file)
          file_content = File.read(md_file)
          translated = Rulepack::Common.apply_translator(translator_cfg, file_content, pkgname: pkgname.to_s, extra_args: translate_extra)
          File.write(md_file, translated)
        end
        Rulepack::Common.log "    ✓ Agent files translated (#{translator_cfg})"
        puts "    ✓ Agent files translated (#{translator_cfg})"
      end

      apply_schema_engine_to_directory(build_pkg_dir, tgt, platforms, format)

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

      if format == 'agent' && tgt[:agent_config]
        agent_cfg = tgt[:agent_config]
        manifest = {
          'name' => pkgname.to_s,
          'description' => (pkg[:pkgdesc] || '').to_s.strip.tr("\n", ' '),
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

      # Record in package index
      pkg_index[:available_targets] << platform_id unless pkg_index[:available_targets].include?(platform_id)
      pkg_index[:checksums][:built][platform_id.to_s] = pkg_index[:source_sha256]
      true
    end

    def build_single_file_target(pkg, pkgname, pkg_index, tgt, platforms, source_content, translate, transformer)
      platform_id = tgt[:platform]
      format = tgt[:format]
      output = tgt[:output]

      Rulepack::Common.log "  → Building for #{platform_id} (#{output})"
      puts "  → Building for #{platform_id} (#{output})"

      # Validate output filename (path traversal protection)
      begin
        Rulepack::Common.validate_output_filename(output, pkgname)
      rescue StandardError => e
        Rulepack::Common.log_error e.message
        return false
      end

      # Run the build pipeline
      begin
        format_profile = Rulepack::Common.platform_config(platform_id, platforms)[:format_profile]
        platform_cfg = Rulepack::Common.platform_config(platform_id, platforms)

        pipeline = Rulepack::BuildPipeline.new(
          source_content,
          platform_id: platform_id,
          pkgname: pkgname,
          target_format: tgt[:format],
          format_profile: format_profile,
          transformer: transformer,       # explicit from PKGBUILD (may be 'copy')
          explicit_translate: translate   # explicit from PKGBUILD (nil if not set)
        )
        transformed = pipeline.run(platform_cfg)
      rescue StandardError => e
        Rulepack::Common.log_error "Build pipeline failed for #{pkgname}/#{platform_id}: #{e.message}"
        return false
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
        begin
          FileUtils.ln_s(target_rel, build_file)
        rescue NotImplementedError, SystemCallError
          FileUtils.cp(store_file, build_file)
        end
      rescue StandardError => e
        Rulepack::Common.log_error "Failed to write build artifact for #{pkgname}/#{platform_id}: #{e.message}"
        return false
      end

      Rulepack::Common.log "    ✓ Built #{output} (#{transformed_sha256[0..7]})"
      puts "    ✓ Built #{output} (#{transformed_sha256[0..7]})"

      # Record in package index
      pkg_index[:available_targets] << platform_id unless pkg_index[:available_targets].include?(platform_id)
      pkg_index[:checksums][:built][platform_id.to_s] = transformed_sha256
      true
    end

    # ─── Helper ──────────────────────────────────────────────────────────────────

    def run_pkgver_func(pkg, pkgname, pkg_index, source_dir)
      return true unless pkg[:pkgver_func]

      Rulepack::Common.log "  Running pkgver_func: #{pkg[:pkgver_func]}"
      stdout_err, status = Dir.chdir(source_dir) do
        Open3.capture2e({ 'LC_ALL' => 'C.UTF-8' }, 'sh', '-c', pkg[:pkgver_func])
      end
      new_pkgver = stdout_err.force_encoding(Encoding::UTF_8).scrub.strip
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

      if applied > 0
        Rulepack::Common.log "    ✓ Schema Engine applied to #{applied} file(s) in directory build"
        puts "    ✓ Schema Engine applied to #{applied} file(s) in directory build"
      end
    end

    # Security: recursively remove all symlinks (files and dirs) under a tree.
    # Used after cp_r to ensure untrusted git/url sources cannot plant symlinks
    # that later File.write / File.read calls would follow out of the build dir.
    def strip_symlinks_in_tree(root)
      return unless Dir.exist?(root)
      Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH).each do |entry|
        next if entry == root
        if File.symlink?(entry)
          File.unlink(entry)
          Rulepack::Common.log "    ⚠ Removed untrusted symlink from build tree: #{entry}"
        end
      end
    end
  end
end
