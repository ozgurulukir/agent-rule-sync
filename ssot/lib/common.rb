# frozen_string_literal: true

require 'net/http'
require 'tempfile'
require 'yaml'
require 'pathname'
require 'digest'
require 'json'

module Ssot
  module Lib
    module Common
      SSOT_ROOT = Pathname.new(__dir__).expand_path.join('..').cleanpath
      BUILD_DIR = SSOT_ROOT.join('build')
      BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')

      module_function

# ─── Build Cache ────────────────────────────────────────────────────────

      # Build cache key from source entry
      def cache_key_for_source(source_entry, source_hash = nil)
        case source_entry[:type]
        when "url" then source_entry[:sha256] || source_hash || raise("No sha256 for URL source")
        when "git" then source_hash || raise("No commit hash for git source")
        when "local" then source_hash || raise("No source hash for local source")
        end
      end

      def cache_dir(key)
        SSOT_ROOT.join("cache", key.to_s)
      end

      def source_cached?(key)
        dir = cache_dir(key)
        dir.exist? && (dir.join("extracted").exist? || dir.join("source.tar.gz").exist?)
      end

      def cache_source(key, content_or_path, source_type: "file")
        dir = cache_dir(key)
        dir.mkpath
        extracted = dir.join("extracted")
        case source_type
        when "content"
          extracted.mkpath
          extracted.join("source").write(content_or_path)
        when "file"
          src = Pathname.new(content_or_path)
          if src.directory?
            FileUtils.cp_r(src, extracted, preserve: false)
          else
            extracted.mkpath
            extracted.join("source").write(src.read)
          end
        when "git_archive"
          extracted.mkpath
          system("tar", "-xzf", Pathname.new(content_or_path).to_s, "-C", extracted.to_s)
        end
      end

      def get_cached_source(key, output_filename = nil)
        extracted = cache_dir(key).join("extracted")
        raise "Cache miss: #{key}" unless extracted.exist?
        if output_filename
          file = extracted.join(output_filename)
          raise "Cached file not found: #{output_filename}" unless file.exist?
          file.read
        else
          files = extracted.children.select(&:file?)
          raise "No files in cache: #{key}" if files.empty?
          files.first.read
        end
      end

      def get_cached_git_source(key)
        extracted = cache_dir(key).join("extracted")
        return nil unless extracted.exist?
        extracted
      end

      # ─── Cache-Aware Source Fetchers ────────────────────────────────────────

      # Fetch URL with cache support
      def cached_fetch_url(url, expected_sha256)
        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)
        raise "Failed to fetch #{url}: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        content = response.body
        actual_sha256 = Digest::SHA256.hexdigest(content)

        if expected_sha256 && actual_sha256 != expected_sha256
          raise "SHA256 mismatch for #{url}: expected #{expected_sha256}, got #{actual_sha256}"
        end

        # Store in cache
        cache_source(actual_sha256, content, source_type: 'content')

        [content, actual_sha256]
      end

      # Fetch git source with cache support (single file)
      # Returns [content, commit_hash]
      def cached_fetch_git_file(url, ref, git_path, depth: 1)
        require 'tmpdir'
        Dir.mktmpdir("ssot-git-") do |tmp|
          commit_hash = fetch_git_source(url, ref, tmp, depth: depth)
          repo_base = Pathname.new(tmp)
          source_in_repo = repo_base.join(git_path).cleanpath
          unless source_in_repo.to_s.start_with?(repo_base.to_s + File::SEPARATOR) || source_in_repo == repo_base
            raise "Path traversal in git source path: #{git_path} escapes repository"
          end
          unless source_in_repo.exist?
            raise "Path not found in git repo: #{git_path}"
          end
          content = source_in_repo.read
          # Cache by commit hash
          cache_source(commit_hash, content, source_type: 'content')
          [content, commit_hash]
        end
      end

      # Fetch git source with cache support (directory / skill-bundle)
      # Returns [persistent_dir_path, commit_hash]
      def cached_fetch_git_dir(url, ref, git_path, depth: 1)
        commit_hash = nil
        require 'tmpdir'
        Dir.mktmpdir("ssot-git-") do |tmp|
          commit_hash = fetch_git_source(url, ref, tmp, depth: depth)
          repo_base = Pathname.new(tmp)
          source_in_repo = repo_base.join(git_path).cleanpath
          unless source_in_repo.to_s.start_with?(repo_base.to_s + File::SEPARATOR) || source_in_repo == repo_base
            raise "Path traversal in git source path: #{git_path} escapes repository"
          end
          unless source_in_repo.exist?
            raise "Path not found in git repo: #{git_path}"
          end
          # Cache by commit hash
          cache_source(commit_hash, source_in_repo, source_type: 'file')
        end
        # Return persistent cache dir + hash
        [cache_dir(commit_hash).join('extracted'), commit_hash]
      end

      # Fetch git source with cache (generic: returns content/dir based on source type)
      def fetch_source_with_cache(src_cfg, format:)
        case src_cfg[:type]
        when 'url'
          cached_fetch_url(src_cfg[:url], src_cfg[:sha256])
        when 'git'
          git_url = src_cfg[:url]
          git_ref = src_cfg[:ref] || 'main'
          git_path = Pathname.new(src_cfg[:path] || '.')
          git_depth = src_cfg[:depth] || 1
          if format == 'skill-bundle' || (git_path.exist? && git_path.directory?)
            cached_fetch_git_dir(git_url, git_ref, git_path, depth: git_depth)
          else
            cached_fetch_git_file(git_url, git_ref, git_path, depth: git_depth)
          end
        when 'local'
          read_source(src_cfg)
        else
          raise "Unsupported source type for caching: #{src_cfg[:type]}"
        end
      end

      # Compare two version strings using pacman/vercmp logic.
      # Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2

      # ─── Index Backup / Restore (L4.3 Transaction Rollback) ─────────────────

      # Create a backup of the current index file.
      # Returns the backup Pathname.
      def backup_index(index_path = SSOT_ROOT.join('index.yaml'))
        return nil unless index_path.exist?
        # Use monotonic counter to ensure unique backup filenames even when called rapidly
        @_backup_counter ||= 0
        @_backup_counter += 1
        ts = Time.now.utc.strftime('%Y%m%dT%H%M%S')
        backup_path = index_path.parent.join("#{index_path.basename}.bak.#{ts}.#{@_backup_counter}")
        FileUtils.cp(index_path, backup_path)
        backup_path
      end

      # Restore index from backup, removing the backup afterwards.
      # Returns true if restored, false if backup not found.
      def restore_index(backup_path, index_path = SSOT_ROOT.join('index.yaml'))
        return false unless backup_path && backup_path.exist?
        FileUtils.cp(backup_path, index_path)
        backup_path.delete
        true
      end

      # Remove all index backup files (cleanup helper).
      def cleanup_backups(index_path = SSOT_ROOT.join('index.yaml'))
        pattern = index_path.parent.join("#{index_path.basename}.bak.*")
        Pathname.glob(pattern.to_s).each { |f| f.delete rescue nil }
      end

      # ─── Version Formatting ────────────────────────────────────────────────────

      # Format version as pacman-style string: "epoch:pkgver-pkgrel"
      # epoch 0 is omitted: "1.0.0-1" instead of "0:1.0.0-1"
      def format_version(epoch, pkgver, pkgrel)
        if epoch.to_i > 0
          "#{epoch}:#{pkgver}-#{pkgrel}"
        else
          "#{pkgver}-#{pkgrel}"
        end
      end
      # Supports alphanumeric segments: 1.2.3a < 1.2.3b < 1.2.4
      # Also handles epoch: pkgrel comparison when pkgver equal
      def compare_versions(v1, v2, pkgrel1: nil, pkgrel2: nil, epoch1: 0, epoch2: 0)
        # Epoch comparison (highest priority)
        cmp = epoch1 <=> epoch2
        return cmp unless cmp.zero?

        # pkgver comparison (alphanumeric segments)
        cmp = vercmp(v1, v2)
        return cmp unless cmp.zero?

        # pkgrel comparison (only if both provided)
        if pkgrel1.nil? || pkgrel2.nil?
          return 0  # no pkgrel info → equal
        end
        pkgrel1 <=> pkgrel2
      end

      # VerCmp implementation: split into alphanumeric segments
      # "1.2.3a" → [1, 2, "3a"]
      # Returns -1, 0, 1
      def vercmp(a, b)
        # Split on non-alphanumeric boundaries, keep runs of digits vs letters
        seg_a = a.to_s.scan(/\d+|[a-zA-Z]+|[^a-zA-Z0-9]+/).map { |s| s =~ /^\d+$/ ? s.to_i : s }
        seg_b = b.to_s.scan(/\d+|[a-zA-Z]+|[^a-zA-Z0-9]+/).map { |s| s =~ /^\d+$/ ? s.to_i : s }

        # Compare segment by segment
        [seg_a.size, seg_b.size].max.times do |i|
          sa = seg_a[i] || 0
          sb = seg_b[i] || 0

          # Both numeric → integer compare
          if sa.is_a?(Integer) && sb.is_a?(Integer)
            cmp = sa <=> sb
          elsif sa.is_a?(Integer) && !sb.is_a?(Integer)
            # Numeric < alphabetic (pacman: 1 < 1a)
            cmp = -1
          elsif !sa.is_a?(Integer) && sb.is_a?(Integer)
            cmp = 1
          else
            # Both strings: locale compare
            cmp = sa.to_s <=> sb.to_s
          end
          return cmp unless cmp.zero?
        end
        0
      end

      # Fetch a git repository to a local directory.
      # Returns the commit hash (SHA256/ SHA1) of the checked-out revision.
      # url: git repository URL
      # ref: branch, tag, or commit hash (default: 'main' or 'master')
      # dest_dir: directory to clone into (must not exist)
      # depth: optional shallow clone depth

      # Check platform prerequisites (system tools) and warn if missing.
      # prerequisites format (from platforms.yaml):
      #   tools: [ruby, python, go, node]
      #   versions: { ruby: ">=2.7", python: ">=3.8" }
      # Returns array of missing tools (empty = all present).
      def check_prerequisites(platform_cfg)
        prereqs = platform_cfg[:prerequisites] || {}
        
        missing = []
        
        # Check tools
        Array(prereqs[:tools]).each do |tool|
          found = system("which #{tool} > /dev/null 2>&1")
          missing << tool unless found
        end
        
        # Check versions (informational only, no enforcement)
        Array(prereqs[:versions]).each do |tool, version_req|
          # Could add version check here; for now just log
        end
        
        missing
      end
      def fetch_git_source(url, ref, dest_dir, depth: nil)
        # Try main first, fallback to master if ref not specified
        ref ||= begin
          # We'll try main, then master during clone
          'main'
        end
        
        # Build git clone command
        cmd = ['git', 'clone']
        cmd << "--depth=1" if depth
        # Determine if ref is a full commit hash (40 hex chars) → cannot use --branch
        is_commit = ref =~ /^[0-9a-f]{40}$/i
        cmd << "--branch=#{ref}" if ref && !is_commit
        cmd << '--quiet'
        cmd << url
        cmd << dest_dir

        unless system(*cmd)
          # If main failed, try master (only when ref was default 'main')
          if ref == 'main' && !is_commit && !system('git', 'clone', '--depth=1', '--branch=master', '--quiet', url, dest_dir)
            raise "git clone failed for #{url} (tried main and master)"
          else
            raise "git clone failed for #{url}"
          end
        end

        # If ref is a commit hash (full), we need to checkout that exact commit
        if is_commit
          Dir.chdir(dest_dir) do
            unless system('git', 'checkout', '--quiet', ref)
              raise "git checkout #{ref} failed"
            end
          end
        end

        # Get the commit hash we ended up on
        commit_hash = Dir.chdir(dest_dir) { `git rev-parse HEAD`.strip }
        raise "Failed to get commit hash from cloned repo" if commit_hash.empty? || commit_hash.length < 40

        commit_hash
      end

      def read_source(source_entry, base_dir = nil)
        case source_entry[:type]
        when 'local'
          path_str = source_entry[:path]
          # If path is relative and base_dir given, join them
          path = if base_dir && !Pathname.new(path_str).absolute?
                   Pathname.new(base_dir).join(path_str)
                 else
                   Pathname.new(expand_user_path(path_str))
                 end
          raise "Local source not found: #{path}" unless path.exist?

          content = path.read
          checksum = Digest::SHA256.hexdigest(content)
          [content, checksum]
        when 'url'
          url = source_entry[:url]
          expected_sha256 = source_entry[:sha256]

          uri = URI.parse(url)
          response = Net::HTTP.get_response(uri)

          unless response.is_a?(Net::HTTPSuccess)
            raise "Failed to fetch #{url}: #{response.code} #{response.message}"
          end

          content = response.body
          actual_sha256 = Digest::SHA256.hexdigest(content)

          if expected_sha256 && actual_sha256 != expected_sha256
            raise "SHA256 mismatch for #{url}: expected #{expected_sha256}, got #{actual_sha256}"
          end

          [content, actual_sha256]
        else
          raise "Unknown source type: #{source_entry[:type]}"
        end
      end

      # Apply a transformer to content
      # transformer: 'copy', 'strip-frontmatter', or 'custom:/path/to/transformer.rb'
      def apply_transformer(transformer, content, pkgname:)
        case transformer
        when 'copy'
          content
        when 'strip-frontmatter'
          strip_frontmatter(content)
        when /^custom:(.+)/
          custom_rel = Regexp.last_match(1)
          # Resolve relative to repo root (SSOT_ROOT)
          custom_path = if custom_rel.start_with?('/') || custom_rel.start_with?('~')
                          expand_user_path(custom_rel)
                        else
                          SSOT_ROOT.join(custom_rel)
                        end.cleanpath
          unless custom_path.exist?
            raise "Custom transformer not found: #{custom_path}"
          end
          # Security: ensure transformer path is within repo (symlink attack prevention)
          real_path = custom_path.realpath
          unless real_path.to_s.start_with?(SSOT_ROOT.to_s + File::SEPARATOR) || real_path == SSOT_ROOT
            raise "Custom transformer path outside repo (symlink attack?): #{custom_path}"
          end
          load custom_path
          unless defined?(Transform) && Transform.respond_to?(:transform)
            raise "Custom transformer #{custom_path} must define Transform.transform(content, pkgname: nil) method"
          end
          Transform.transform(content, pkgname: pkgname)
        else
          raise "Unknown transformer: #{transformer}"
        end
      end

      # Remove YAML frontmatter (--- ... ---) from content
      def strip_frontmatter(content)
        content.sub(/\A---\s*\n.*?\n---\s*\n/m, '')
      end

      # Expand user home directory in path (~/...)
      def expand_user_path(path)
        path.start_with?('~') ? File.expand_path(path) : path
      end

      # Validate output filename - no path traversal
      def validate_output_filename(output, pkgname)
        # Must not contain '..' or absolute path
        if output.include?('..') || Pathname.new(output).absolute?
          raise "Invalid output path '#{output}' in package '#{pkgname}': path traversal not allowed"
        end

        # Must not contain directory separators that escape current dir
        clean = Pathname.new(output).cleanpath
        if clean.to_s != output || clean.to_s.include?(File::SEPARATOR)
          raise "Invalid output path '#{output}' in package '#{pkgname}': only filename allowed"
        end
      end

      # Validate target_dir - no path traversal
      def validate_target_dir(target_dir, pkgname)
        if target_dir.include?('..') || Pathname.new(target_dir).absolute?
          raise "Invalid target_dir '#{target_dir}' in package '#{pkgname}': path traversal not allowed"
        end
      end

      # Atomic write: write content to temp file then rename
      def atomic_write(path, content)
        path = Pathname.new(path)
        path.dirname.mkpath

        Tempfile.create(['ssot', path.extname], path.dirname) do |tmp|
          tmp.write(content)
          tmp.flush
          FileUtils.mv(tmp.path, path.to_s)
        end
      end

      # Load and validate PKGBUILD YAML
      # Returns parsed hash with symbolized keys
      def load_pkgbuild(pkgdir)
        pkgbuild_path = Pathname.new(pkgdir).join('PKGBUILD')
        unless pkgbuild_path.exist?
          raise "PKGBUILD not found in #{pkgdir}"
        end

        raw = pkgbuild_path.read
        data = YAML.safe_load(raw, permitted_classes: [Symbol, Pathname], symbolize_names: true)

        # Validate required fields
        %i[pkgname pkgver source targets].each do |field|
          unless data.key?(field)
            raise "PKGBUILD missing required field: #{field}"
          end
        end

        # Validate source array
        unless data[:source].is_a?(Array) && !data[:source].empty?
          raise "PKGBUILD must have at least one source entry"
        end

        data[:source].each do |src|
          unless src[:type] && (src[:path] || src[:url])
            raise "Invalid source entry: #{src.inspect}"
          end
        end

        # Validate targets array
        unless data[:targets].is_a?(Array) && !data[:targets].empty?
          raise "PKGBUILD must have at least one target"
        end

        valid_formats = %w[directory import skill skill-bundle]
        data[:targets].each do |t|
          unless t[:platform] && t[:format] && t[:output]
            raise "Target missing required fields: #{t.inspect}"
          end
          unless valid_formats.include?(t[:format])
            raise "Invalid format '#{t[:format]}' for platform '#{t[:platform]}'"
          end

          # skill-bundle: output must be '.' (directory marker), target_dir required
          if t[:format] == 'skill-bundle'
            if t[:output] && t[:output] != '.' && !t[:output].empty?
              raise "skill-bundle output must be '.' (directory marker), got '#{t[:output]}'"
            end
            unless t[:install] && t[:install][:target_dir]
              raise "skill-bundle requires install.target_dir in PKGBUILD"
            end
            # install type for skill-bundle should be 'copy' only
            install_type = t[:install][:type] || 'copy'
            unless install_type == 'copy'
              raise "skill-bundle only supports install.type: 'copy', got '#{install_type}'"
            end
          end
        end

        data
      end

      # Load YAML from path (symbol keys)
      def load_yaml(path)
        content = Pathname.new(path).read
        YAML.safe_load(content, permitted_classes: [Symbol, Pathname], symbolize_names: true)
      end

      # Write YAML atomically
      def write_yaml_atomic(path, data)
        yaml_content = data.to_yaml
        atomic_write(path, yaml_content)
      end

      # Append to file atomically (create if doesn't exist)
      def atomic_append(path, content)
        path = Pathname.new(path)
        path.dirname.mkpath

        File.open(path.to_s, 'a') { |f| f.write(content) }
      end

      # Generate skill-bundle manifest JSON for a built package directory.
      # build_pkg_dir: Pathname to the built package directory
      # pkgname: package name (string)
      # platform_id: platform identifier (string)
      # Returns the parsed manifest hash.
      def generate_skill_bundle_manifest(build_pkg_dir, pkgname, platform_id)
        build_pkg_dir = Pathname.new(build_pkg_dir)
        manifest = {
          generated_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
          pkgname: pkgname.to_s,
          platform: platform_id.to_s,
          sub_skills: []
        }
        seen_paths = {}

        # Collect root-level files (not in a subdir)
        Dir.glob("#{build_pkg_dir}/*", File::FNM_DOTMATCH).each do |entry_path|
          entry = Pathname.new(entry_path)
          next unless entry.file?
          next if entry.basename.to_s == 'manifest.json'
          rel_path = entry.basename.to_s
          sub = manifest[:sub_skills].find { |s| s[:path] == '.' }
          unless sub
            sub = { path: '.', name: '.', sha256: '', files: {} }
            manifest[:sub_skills] << sub
          end
          sub[:files][rel_path] = Digest::SHA256.hexdigest(entry.read)
        end
        if (sub = manifest[:sub_skills].find { |s| s[:path] == '.' })
          sub[:sha256] = Digest::SHA256.hexdigest(sub[:files].sort.to_h.to_s)
          seen_paths['.'] = true
        end

        # Each top-level subdirectory is a sub-skill
        Dir.glob("#{build_pkg_dir}/*/", File::FNM_DOTMATCH).each do |subdir_path|
          subdir = Pathname.new(subdir_path)
          sub_name = subdir.basename.to_s
          next unless subdir.directory?
          next if sub_name == '.' || sub_name == '..'  # skip FNM_DOTMATCH artifacts
          sub_name = subdir.basename.to_s
          next if seen_paths[sub_name]
          sub_files = {}
          Dir.glob("#{subdir}/**/*", File::FNM_DOTMATCH).each do |file_path|
            file = Pathname.new(file_path)
            next unless file.file?
            rel_path = file.relative_path_from(build_pkg_dir).to_s
            sub_files[rel_path] = Digest::SHA256.hexdigest(file.read)
          end
          agg_sha = Digest::SHA256.hexdigest(sub_files.sort.to_h.to_s)
          manifest[:sub_skills] << { path: sub_name, name: sub_name, sha256: agg_sha, files: sub_files }
          seen_paths[sub_name] = true
        end

        manifest_path = build_pkg_dir.join('manifest.json')
        manifest_path.write(JSON.pretty_generate(manifest))
        manifest
      end

      # Load platform registry
      def load_platform_registry
        # __dir__ points to ssot/lib, go up one level to ssot/
        registry_path = Pathname.new(__dir__).join('../registry/platforms.yaml').cleanpath
        raw = load_yaml(registry_path)

        # Validate each platform config
        raw.each do |id, cfg|
          validate_platform_config(id, cfg)
        end

        raw
      end

      # Validate a single platform configuration
      def validate_platform_config(id, cfg)
        [:type, :base_path].each do |req|
          unless cfg[req]
            raise "Platform '#{id}' missing required field: #{req}"
          end
        end

        case cfg[:type]
        when 'directory'
          unless cfg[:rules_dir]
            raise "Platform '#{id}' (directory) missing :rules_dir"
          end
        when 'import'
          unless cfg[:config_file]
            raise "Platform '#{id}' (import) missing :config_file"
          end
        when 'skill'
          unless cfg[:skill_file]
            raise "Platform '#{id}' (skill) missing :skill_file"
          end
        else
          raise "Platform '#{id}' has unknown type: #{cfg[:type]}"
        end
      end

      # Find a platform config by name (string or symbol key)
      def platform_config(name, registry)
        key = name.to_sym
        cfg = registry[key] || registry[name.to_s]
        raise "Unknown platform: #{name}" unless cfg
        cfg
      end

       # Resolve install path for a platform/target
       # base_override: for project-level platforms, the actual project root Pathname
       def resolve_install_path(platform_cfg, target_cfg, base_override = nil)
         base = if base_override
                  base_override.to_s
                else
                  expand_user_path(platform_cfg[:base_path])
                end

         case platform_cfg[:type]
         when 'directory'
           dir = if target_cfg[:format] == 'skill'
                   platform_cfg[:skills_dir] || platform_cfg[:rules_dir]
                 else
                   platform_cfg[:rules_dir]
                 end
           Pathname.new(base).join(dir, target_cfg[:output])
         when 'import'
           Pathname.new(base).join(platform_cfg[:config_file])
         when 'skill'
           Pathname.new(base).join(platform_cfg[:skill_file])
         else
           raise "Unknown platform type: #{platform_cfg[:type]}"
         end
       end

      # Safe relative path (no escaping parent)
      def safe_relative(path, base)
        relative = Pathname.new(path).relative_path_from(base).to_s
        if relative.start_with?('..')
          raise "Path escapes base: #{path} relative to #{base}"
        end
        relative
      end

      # Get build directory for a platform
      def build_dir_for_platform(platform)
        Pathname.new('ssot/build').join(platform)
      end

      # Validate PKGBUILD hash completely
       def validate_pkgbuild(pkg, pkgdir)
        errors = []

        # pkgname: lowercase alphanumeric + hyphens/underscores, min 2 char
        unless pkg[:pkgname] =~ /\A[a-z0-9][a-z0-9_-]*\z/
          errors << "Invalid pkgname '#{pkg[:pkgname]}': must be lowercase alphanumeric with - or _"
        end

        # pkgver: non-empty string (can be overridden by pkgver_func)
        unless pkg[:pkgver].is_a?(String) && !pkg[:pkgver].empty?
          errors << "Invalid pkgver: must be non-empty string"
        end

        # pkgver_func: optional command string
        if pkg.key?(:pkgver_func)
          unless pkg[:pkgver_func].is_a?(String) && !pkg[:pkgver_func].empty?
            errors << "pkgver_func must be a non-empty string"
          end
        end

        # epoch: integer >= 0 (defaulted before call)
        unless pkg[:epoch].is_a?(Integer) && pkg[:epoch] >= 0
          errors << "Invalid epoch: must be integer >= 0"
        end

        # pkgrel: integer >= 1 (defaulted before call)
        unless pkg[:pkgrel].is_a?(Integer) && pkg[:pkgrel] >= 1
          errors << "Invalid pkgrel: must be integer >= 1"
        end

        # pkgdesc: non-empty string
        unless pkg[:pkgdesc].is_a?(String) && !pkg[:pkgdesc].empty?
          errors << "Invalid pkgdesc: must be non-empty string"
        end

        # arch: currently only 'any'
        unless pkg[:arch] == 'any'
          errors << "Invalid arch: only 'any' supported"
        end

        # order: integer >= 0
        order_val = pkg[:order] || 0
        unless order_val.is_a?(Integer) && order_val >= 0
          errors << "Invalid order: must be integer >= 0"
        end

        # source: array, at least one entry
        unless pkg[:source].is_a?(Array) && !pkg[:source].empty?
          errors << "source must be a non-empty array"
        end

        # Guard each_with_index against nil source; empty arrays still iterate (zero times)
        pkg[:source]&.each_with_index do |src, i|
            unless src[:type] && (src[:path] || src[:url])
              errors << "source[#{i}] missing type or path/url"
            end
          case src[:type]
          when 'local'
            unless src[:path].is_a?(String) && !src[:path].empty?
              errors << "source[#{i}] local type requires non-empty path"
            end
          when 'url'
            unless src[:url].is_a?(String) && !src[:url].empty?
              errors << "source[#{i}] url type requires url"
            end
            unless src[:sha256] =~ /\A[0-9a-f]{64}\z/i
              errors << "source[#{i}] url type requires valid sha256"
            end
          when 'git'
            unless src[:url].is_a?(String) && !src[:url].empty?
              errors << "source[#{i}] git type requires url"
            end
            # ref, path, depth optional
            if src.key?(:ref) && !src[:ref].is_a?(String)
              errors << "source[#{i}] git ref must be string"
            end
            if src.key?(:path) && !src[:path].is_a?(String)
              errors << "source[#{i}] git path must be string"
            end
            if src.key?(:depth) && !src[:depth].is_a?(Integer)
              errors << "source[#{i}] git depth must be integer"
            end
          else
            errors << "source[#{i}] unknown type: #{src[:type]}"
          end
        end  # each_with_index

        # targets: array, at least one
        unless pkg[:targets].is_a?(Array) && !pkg[:targets].empty?
          errors << "targets must be a non-empty array"
        end

        if pkg[:targets].is_a?(Array)
          valid_formats = %w[directory import skill skill-bundle]
          pkg[:targets].each_with_index do |t, i|
          unless t[:platform] && t[:platform].is_a?(String)
            errors << "targets[#{i}]: missing platform"
          end
          unless valid_formats.include?(t[:format])
            errors << "targets[#{i}]: invalid format '#{t[:format]}' (must be #{valid_formats.join('/')})"
          end
          # output validation
          output = t[:output]
          if output.nil? || output.empty?
            errors << "targets[#{i}]: output cannot be empty"
          else
            begin
              validate_output_filename(output, pkg[:pkgname])
            rescue => e
              errors << "targets[#{i}]: #{e.message}"
            end
          end
          # transformer validation
          if t[:transformer] && t[:transformer] != 'copy' && t[:transformer] != 'strip-frontmatter'
            unless t[:transformer] =~ /\Acustom:.+\z/
              errors << "targets[#{i}]: invalid transformer '#{t[:transformer]}'"
            end
          end
          # install validation
          if t[:install]
            inst = t[:install]
            unless %w[symlink copy inject append].include?(inst[:type])
              errors << "targets[#{i}]: invalid install.type '#{inst[:type]}'"
            end
            if inst[:target_dir]
              validate_target_dir(inst[:target_dir], pkg[:pkgname])
            end
          end
          # skill-bundle requires install.target_dir even when no install block present
          if t[:format] == 'skill-bundle'
            inst = t[:install] || {}
            unless inst[:target_dir] && inst[:target_dir].is_a?(String) && !inst[:target_dir].empty?
              errors << "targets[#{i}]: skill-bundle requires install.target_dir"
            end
            unless (inst[:type] || 'copy') == 'copy'
              errors << "targets[#{i}]: skill-bundle install.type must be 'copy'"
            end
          end
        end  # each_with_index
      end  # if pkg[:targets].is_a?(Array)

        # checksums: auto, skip

        # dependencies, conflicts, provides, tags, maintainer, license: optional types
        # No strict validation on these

        errors.empty? ? true : errors.join('; ')
      end

       # Uninstall packages from a platform, modifying index in-place.
       # Returns array of uninstalled package names.
       # Does NOT write index to disk.
       def uninstall_packages(index, platform_id, dry_run: false, project_root: nil, specific_packages: nil)
         platform_cfg = platform_config(platform_id, load_platform_registry)
         base_path = if project_root
                       project_root
                     else
                       Pathname.new(expand_user_path(platform_cfg[:base_path]))
                     end

         # Load build index for target info
         build_index = load_yaml(BUILD_INDEX_PATH)
         packages_to_uninstall = if specific_packages
                                   specific_packages
                                 else
                                   index[:packages].select { |name, pkg| pkg[:installed]&.any? { |i| i[:platform] == platform_id } }.keys
                                 end

         uninstalled = []

         packages_to_uninstall.each do |pkgname|
           pkg_index = index[:packages][pkgname]
           next unless pkg_index

           records = pkg_index[:installed] || []
           platform_records = records.select { |r| r[:platform] == platform_id }

           if platform_records.empty?
             log "  ⚠ #{pkgname} not installed on #{platform_id}, skipping uninstall" unless dry_run
             next
           end

           pkgdata = build_index[:packages][pkgname]
           unless pkgdata
             log_error "Package not found in build index: #{pkgname}"
             next
           end
           targets = pkgdata[:targets]&.select { |t| t[:platform] == platform_id } || []
           target_by_output = {}
           targets.each { |t| target_by_output[t[:output]] = t }

           platform_records.each do |rec|
             output = rec[:output]
             target = target_by_output[output]
             unless target
               log_warn "  ⚠ No target found for output '#{output}' in #{pkgname}, skipping uninstall"
               next
             end

             if dry_run
               log "    [DRY-RUN] Would remove: #{output}"
               uninstalled << pkgname
               next
             end

             format = target[:format]
             install_cfg = target[:install] || {}
             case format
             when 'skill-bundle'
               target_dir = install_cfg[:target_dir] || raise("Missing target_dir for skill-bundle uninstall: #{pkgname}")
               dest_dir = base_path.join(platform_cfg[:skills_dir]).join(target_dir)
               if dest_dir.exist?
                 FileUtils.rm_rf(dest_dir)
                 log "    ✓ Removed directory: #{dest_dir}"
               else
                 log "    ✓ Already removed: #{dest_dir}"
               end
             else
               install_path = resolve_install_path(platform_cfg, target, project_root)
               if install_path.exist?
                 FileUtils.rm(install_path) if install_path.file? || install_path.symlink?
                 FileUtils.rm_rf(install_path) if install_path.directory?
                 log "    ✓ Removed: #{install_path}"
               else
                 log "    ✓ Already removed: #{install_path}"
               end
             end

             # Mark record for removal
             records.delete(rec)
             uninstalled << pkgname
           end
         end

         uninstalled.uniq
       end

       # Migrate installed records to include pkgrel/epoch if missing (for old index)
       def migrate_installed_records(pkg_index)
         return unless pkg_index[:installed].is_a?(Array)
         pkg_index[:installed].each do |rec|
           rec[:pkgrel] ||= 1
           rec[:epoch] ||= 0
         end
       end
     end
   end
 end

      # ─── Build Cache ────────────────────────────────────────────────────────

      # Build cache key from source entry
      def cache_key_for_source(source_entry, source_hash = nil)
        case source_entry[:type]
        when "url" then source_entry[:sha256] || source_hash || raise("No sha256 for URL source")
        when "git" then source_hash || raise("No commit hash for git source")
        when "local" then source_hash || raise("No source hash for local source")
        end
      end

      def cache_dir(key)
        SSOT_ROOT.join("cache", key.to_s)
      end

      def source_cached?(key)
        dir = cache_dir(key)
        dir.exist? && (dir.join("extracted").exist? || dir.join("source.tar.gz").exist?)
      end

      def cache_source(key, content_or_path, source_type: "file")
        dir = cache_dir(key)
        dir.mkpath
        extracted = dir.join("extracted")
        case source_type
        when "content"
          extracted.mkpath
          extracted.join("source").write(content_or_path)
        when "file"
          src = Pathname.new(content_or_path)
          if src.directory?
            FileUtils.cp_r(src, extracted, preserve: false)
          else
            extracted.mkpath
            extracted.join("source").write(src.read)
          end
        when "git_archive"
          extracted.mkpath
          system("tar", "-xzf", Pathname.new(content_or_path).to_s, "-C", extracted.to_s)
        end
      end

      def get_cached_source(key, output_filename = nil)
        extracted = cache_dir(key).join("extracted")
        raise "Cache miss: #{key}" unless extracted.exist?
        if output_filename
          file = extracted.join(output_filename)
          raise "Cached file not found: #{output_filename}" unless file.exist?
          file.read
        else
          files = extracted.children.select(&:file?)
          raise "No files in cache: #{key}" if files.empty?
          files.first.read
        end
      end

      def get_cached_git_source(key)
        extracted = cache_dir(key).join("extracted")
        return nil unless extracted.exist?
        extracted
      end

      # ─── Cache-Aware Source Fetchers ────────────────────────────────────────

      # Fetch URL with cache support
      def cached_fetch_url(url, expected_sha256)
        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)
        raise "Failed to fetch #{url}: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        content = response.body
        actual_sha256 = Digest::SHA256.hexdigest(content)

        if expected_sha256 && actual_sha256 != expected_sha256
          raise "SHA256 mismatch for #{url}: expected #{expected_sha256}, got #{actual_sha256}"
        end

        # Store in cache
        cache_source(actual_sha256, content, source_type: 'content')

        [content, actual_sha256]
      end

      # Fetch git source with cache support (single file)
      # Returns [content, commit_hash]
      def cached_fetch_git_file(url, ref, git_path, depth: 1)
        require 'tmpdir'
        Dir.mktmpdir("ssot-git-") do |tmp|
          commit_hash = fetch_git_source(url, ref, tmp, depth: depth)
          repo_base = Pathname.new(tmp)
          source_in_repo = repo_base.join(git_path).cleanpath
          unless source_in_repo.to_s.start_with?(repo_base.to_s + File::SEPARATOR) || source_in_repo == repo_base
            raise "Path traversal in git source path: #{git_path} escapes repository"
          end
          unless source_in_repo.exist?
            raise "Path not found in git repo: #{git_path}"
          end
          content = source_in_repo.read
          # Cache by commit hash
          cache_source(commit_hash, content, source_type: 'content')
          [content, commit_hash]
        end
      end

      # Fetch git source with cache support (directory / skill-bundle)
      # Returns [persistent_dir_path, commit_hash]
      def cached_fetch_git_dir(url, ref, git_path, depth: 1)
        commit_hash = nil
        require 'tmpdir'
        Dir.mktmpdir("ssot-git-") do |tmp|
          commit_hash = fetch_git_source(url, ref, tmp, depth: depth)
          repo_base = Pathname.new(tmp)
          source_in_repo = repo_base.join(git_path).cleanpath
          unless source_in_repo.to_s.start_with?(repo_base.to_s + File::SEPARATOR) || source_in_repo == repo_base
            raise "Path traversal in git source path: #{git_path} escapes repository"
          end
          unless source_in_repo.exist?
            raise "Path not found in git repo: #{git_path}"
          end
          # Cache by commit hash
          cache_source(commit_hash, source_in_repo, source_type: 'file')
        end
        # Return persistent cache dir + hash
        [cache_dir(commit_hash).join('extracted'), commit_hash]
      end

      # Fetch git source with cache (generic: returns content/dir based on source type)
      def fetch_source_with_cache(src_cfg, format:)
        case src_cfg[:type]
        when 'url'
          cached_fetch_url(src_cfg[:url], src_cfg[:sha256])
        when 'git'
          git_url = src_cfg[:url]
          git_ref = src_cfg[:ref] || 'main'
          git_path = Pathname.new(src_cfg[:path] || '.')
          git_depth = src_cfg[:depth] || 1
          if format == 'skill-bundle' || (git_path.exist? && git_path.directory?)
            cached_fetch_git_dir(git_url, git_ref, git_path, depth: git_depth)
          else
            cached_fetch_git_file(git_url, git_ref, git_path, depth: git_depth)
          end
        when 'local'
          read_source(src_cfg)
        else
          raise "Unsupported source type for caching: #{src_cfg[:type]}"
        end
      end
