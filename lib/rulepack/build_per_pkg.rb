# frozen_string_literal: true

# Build Per-Package — Source fetching and per-target artifact construction.
#
# Takes an immutable Rulepack::Package and an accumulating Rulepack::BuildRecord;
# every method returns the updated record (value-threading, no mutation).
# The build-index entry schema is owned by BuildRecord.

require 'pathname'
require_relative 'common'
require_relative 'emitter'
require_relative 'security'
require_relative 'schema_engine'
require_relative 'build_pipeline'
require_relative 'build_loader'
require_relative 'lib/skill_bundle_lazy'

module Rulepack
  module BuildPerPkg
    module_function

    # ─── Fetch source ─────────────────────────────────────────────────────────────

    # Returns [source_content_or_truthy, record]. For materializable packages
    # (directory source) source_content is true — nothing downstream needs it.
    # A nil first element marks the package as failed (fetch or pkgver_func
    # error); the record is still returned so partial state can be inspected.
    def fetch_source(pkg, pkgname, record, pkg_dir)
      if pkg.materializable_only?
        record = fetch_skill_bundle_source(pkg, pkgname, record, pkg_dir)
        record ? [true, record] : [nil, record]
      else
        fetch_file_source(pkg, pkgname, record, pkg_dir)
      end
    end

    # Returns the updated record, or nil when the source cannot be fetched
    # (missing/invalid source config, or pkgver_func failure — the package
    # must not be built with a stale version).
    def fetch_skill_bundle_source(pkg, pkgname, record, pkg_dir)
      src_cfg = pkg.source.first
      unless src_cfg
        Rulepack::Common.log_error "No source defined for #{pkgname} (skill-bundle)"
        return nil
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
          return nil
        end

        # Deterministic content hash of the source tree — never nil, so the
        # install-time materialization staleness gate always has a real
        # fingerprint to compare against. (compute_local_source_sha returns
        # nil only for a non-directory, rejected above.)
        record = record.with_source(
          source_dir: source_dir.relative_path_from(Rulepack::Common::RULEPACK_ROOT).to_s,
          source_sha256: Rulepack::SkillBundle.compute_local_source_sha(source_dir)
        )

        ok, pkg, record = run_pkgver_func(pkg, pkgname, record, source_dir)
        return nil unless ok

        Rulepack::Emitter.emit(:progress, message: "  ✓ Source directory verified: #{source_dir}")
      when 'git'
        git_url = src_cfg[:url]
        git_ref = src_cfg[:ref] || 'main'
        git_path = Pathname.new(src_cfg[:path] || '.')
        git_depth = src_cfg[:depth] || 1
        Rulepack::Common.log "  Fetching git repo (cached): #{git_url} (ref: #{git_ref})"

        # pkgver_func needs the real repository (.git) — run it inside the
        # clone via the cache layer's on_clone hook, before extraction to
        # the .git-less cache tree.
        pkgver_result = nil
        cached_dir, commit_hash, pkgver_result = Rulepack::Common.cached_fetch_git_dir(
          git_url, git_ref, git_path, depth: git_depth,
          on_clone: lambda { |clone_root|
            run_pkgver_shell(pkg, pkgname, clone_root)
          }
        )
        ok, updated_pkg, new_pkgver = pkgver_result
        unless ok
          Rulepack::Common.log_error "pkgver_func failed for #{pkgname}: aborting package"
          return nil
        end
        pkg = updated_pkg

        persistent_dir = Rulepack::Common.paths.git_sources_dir(pkgname.to_s)
        FileUtils.rm_rf(persistent_dir)
        FileUtils.mkpath(persistent_dir.parent)
        FileUtils.cp_r(cached_dir, persistent_dir)
        record = record.with_source(
          source_dir: persistent_dir.relative_path_from(Rulepack::Common::RULEPACK_ROOT).to_s,
          source_sha256: commit_hash
        )
        Rulepack::Emitter.emit(:progress, message: "  ✓ Git source cached/build dir (#{commit_hash[0..7]})")

        record = record.with(pkgver: new_pkgver) if new_pkgver
      else
        Rulepack::Common.log_error "skill-bundle only supports 'local' or 'git' source type, got: #{src_cfg[:type]}"
        return nil
      end

      record
    end

    # Returns [source_content_or_nil, record].
    def fetch_file_source(pkg, pkgname, record, pkg_dir)
      sources = pkg.source
      sources = [sources] unless sources.is_a?(Array)

      src_cfg = sources.first
      unless src_cfg
        Rulepack::Common.log_warn "  ⚠ No source defined for #{pkgname}, skipping"
        return [nil, record]
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
        return [nil, record]
      end

      record = record.with_checksum_source(source_sha256)
      Rulepack::Emitter.emit(:progress, message: "  ✓ Fetched source (#{source_sha256[0..7]})")

      [source_content, record]
    end

    # ─── Process each target ──────────────────────────────────────────────────────

    # Returns [ok, record].
    def process_targets(pkg, pkgname, record, platforms, source_content)
      transform_cache = {}

      success = true
      pkg.targets.each do |tgt|
        result, record = if tgt.materializable?
                           build_skill_bundle_target(pkgname, record, tgt)
                         else
                           build_single_file_target(pkg, pkgname, record, tgt, platforms,
                                                    source_content, transform_cache)
                         end
        success = false unless result
      end
      [success, record]
    end

    def build_skill_bundle_target(pkgname, record, tgt)
      # ADR-2026-07-29: source-centric build.
      # The build phase no longer copies source_dir → build/<plat>/<pkg>/.
      # That step (cp_r, symlink strip, agent translate, schema engine,
      # manifest generation) is deferred to install-time via
      # Rulepack::SkillBundleLazy.ensure_materialized!. Recording the
      # available_target and source SHA here is sufficient — install will
      # lazily create the build/<plat>/<pkg>/ tree when needed.
      platform_id = tgt.platform

      unless record.source_dir
        Rulepack::Common.log_error "internal error: source_dir not set for skill-bundle #{pkgname}"
        return [false, record]
      end

      Rulepack::Emitter.emit(:progress, message: "  → Recorded for #{platform_id} (skill-bundle: #{pkgname}, lazy)")

      # Install will use these to materialize on demand; the built checksum
      # for lazy targets is the source fingerprint itself.
      [true, record.with_target(platform_id, record.source_sha256)]
    end

    def build_single_file_target(pkg, pkgname, record, tgt, platforms, source_content, transform_cache = {})
      platform_id = tgt.platform
      output = tgt.output

      # Validate output filename (path traversal protection)
      begin
        Rulepack::Common.validate_output_filename(output, pkgname)
      rescue StandardError => e
        Rulepack::Common.log_error e.message
        return [false, record]
      end

      platform_cfg = Rulepack::Common.platform_config(platform_id, platforms)
      format_profile = platform_cfg[:format_profile] || {}
      translate = tgt.translate
      transformer = tgt.transformer || 'copy'

      translator_cfg = Rulepack::SchemaEngine.resolve_translator(translate, platform_id, tgt.format, platform_cfg)
      schema_section = tgt.skill_format? || tgt.skill_bundle? ? :skills : :rules
      ruleset = format_profile[schema_section] || {}
      transformer_cfg = Rulepack::SchemaEngine.resolve_transformer(transformer, platform_id, tgt.format, platform_cfg)

      source_sha = record.source_sha256 || record.checksums[:source]
      union_key = Digest::SHA256.hexdigest([
        source_sha,
        tgt.format,
        translator_cfg.to_s,
        ruleset.to_json,
        transformer_cfg.to_s
      ].join('::'))

      transformed = nil
      if transform_cache.key?(union_key)
        transformed, cached_plat = transform_cache[union_key]
        Rulepack::Emitter.emit(:progress, message: "  → Building for #{platform_id} (#{output}) [Union cached from #{cached_plat}]")
      else
        Rulepack::Emitter.emit(:progress, message: "  → Building for #{platform_id} (#{output})")

        # Run the build pipeline
        begin
          pipeline = Rulepack::BuildPipeline.new(
            source_content,
            platform_id: platform_id,
            pkgname: pkgname,
            target_format: tgt.format,
            format_profile: format_profile,
            transformer: transformer,       # explicit from PKGBUILD (may be 'copy')
            explicit_translate: translate   # explicit from PKGBUILD (nil if not set)
          )
          transformed = pipeline.run(platform_cfg)
          transform_cache[union_key] = [transformed, platform_id]
        rescue StandardError => e
          Rulepack::Common.log_error "Build pipeline failed for #{pkgname}/#{platform_id}: #{e.message}"
          return [false, record]
        end
      end

      transformed_sha256 = Digest::SHA256.hexdigest(transformed)

      # Write to build store & link to build directory
      begin
        # Write canonical file to build/store/
        store_dir = Rulepack::Common.paths.store_dir
        store_dir.mkpath
        store_file = store_dir.join(transformed_sha256)
        store_file.write(transformed) unless store_file.exist?

        # Build destination path
        build_file = Rulepack::Common.paths.platform_dir(platform_id, pkgname).join(output)
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
        return [false, record]
      end

      Rulepack::Emitter.emit(:progress, message: "    ✓ Built #{output} (#{transformed_sha256[0..7]})")

      [true, record.with_target(platform_id, transformed_sha256)]
    end

    # ─── Helper ──────────────────────────────────────────────────────────────────

    # Runs pkgver_func when the descriptor declares one. Returns
    # [ok, pkg, record]: success propagates the refreshed version into both
    # the Package and the record; failure aborts the package without partial
    # state (caller returns the record untouched apart from source fields).
    def run_pkgver_func(pkg, pkgname, record, source_dir)
      return [true, pkg, record] unless pkg.pkgver_func

      ok, updated_pkg, new_pkgver = run_pkgver_shell(pkg, pkgname, source_dir)
      return [false, pkg, record] unless ok

      [true, updated_pkg, record.with(pkgver: new_pkgver)]
    end

    # Raw shell execution of pkgver_func in dir. Returns [ok, pkg, new_pkgver].
    def run_pkgver_shell(pkg, pkgname, dir)
      return [true, pkg, nil] unless pkg.pkgver_func

      Rulepack::Common.log "  Running pkgver_func: #{pkg.pkgver_func}"
      stdout_err, status = Dir.chdir(dir) do
        Open3.capture2e({ 'LC_ALL' => 'C.UTF-8' }, 'sh', '-c', pkg.pkgver_func)
      end
      new_pkgver = stdout_err.force_encoding(Encoding::UTF_8).scrub.strip
      unless status.success?
        Rulepack::Common.log_error "pkgver_func failed for #{pkgname}: #{stdout_err}"
        return [false, pkg, nil]
      end
      if new_pkgver.empty?
        Rulepack::Common.log_error "pkgver_func returned empty version for #{pkgname}"
        return [false, pkg, nil]
      end
      Rulepack::Common.log "  pkgver updated: #{pkg.pkgver} → #{new_pkgver}"
      [true, pkg.with(pkgver: new_pkgver), new_pkgver]
    end
  end
end
