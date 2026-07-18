# frozen_string_literal: true

module Rulepack
  module Common
    module_function

    # ─── Build Cache ────────────────────────────────────────────────────────

    # Build cache key from source entry
    def cache_key_for_source(source_entry, source_hash = nil)
      case source_entry[:type]
      when 'url' then source_entry[:sha256] || source_hash || raise('No sha256 for URL source')
      when 'git' then source_hash || raise('No commit hash for git source')
      when 'local' then source_hash || raise('No source hash for local source')
      end
    end

    def cache_dir(key)
      RULEPACK_ROOT.join(Rulepack::Config.cache_dir_name, key.to_s)
    end

    # Calculates the total size of a directory in bytes
    def directory_size(path)
      sum = 0
      path.find { |entry| sum += entry.size if entry.file? }
      sum
    end

    # Total size of the cache root directory in bytes.
    def cache_total_bytes
      root = RULEPACK_ROOT.join(Rulepack::Config.cache_dir_name)
      return 0 unless root.exist?

      directory_size(root)
    end

    # Evict least-recently-used cache entries until total size is under the limit.
    # LRU key: entry directory mtime (oldest = least recently used).
    # Called automatically from cache_source after every write.
    def enforce_cache_limit!
      max_mb = Rulepack::Config.cache_max_size_mb
      return if max_mb <= 0 # 0 = disabled

      limit_bytes = max_mb * 1024 * 1024
      root = RULEPACK_ROOT.join(Rulepack::Config.cache_dir_name)
      return unless root.exist?

      total_bytes = cache_total_bytes
      return if total_bytes <= limit_bytes

      # Collect all top-level cache key directories with their mtime
      entries = root.children.select(&:directory?).map do |d|
        [d.mtime, d]
      end

      # Sort ascending: oldest mtime first
      entries.sort_by!(&:first)

      # OPTIMIZATION: Calculate initial cache total and sorted list once (O(N)),
      # then incrementally deduct removed directory sizes to avoid O(N^2) full rescans.
      while total_bytes > limit_bytes && !entries.empty?
        _mtime, oldest_dir = entries.shift

        dir_size = 0
        begin
          dir_size = directory_size(oldest_dir)
        rescue Errno::ENOENT => e
          Rulepack::Common.log_warn "Warning: File disappeared during eviction: #{oldest_dir} (#{e.message})"
          next # Skip this entry and continue
        end

        FileUtils.rm_rf(oldest_dir)
        total_bytes -= dir_size
      end
    end

    def source_cached?(key)
      dir = cache_dir(key)
      dir.exist? && (dir.join('extracted').exist? || dir.join('source.tar.gz').exist?)
    end

    def cache_source(key, content_or_path, source_type: 'file')
      dir = cache_dir(key)
      dir.mkpath
      extracted = dir.join('extracted')
      case source_type
      when 'content'
        extracted.mkpath
        extracted.join('source').write(content_or_path)
      when 'file'
        src = Pathname.new(content_or_path)
        if src.directory?
          FileUtils.cp_r(src, extracted, preserve: false)
        else
          extracted.mkpath
          extracted.join('source').write(src.read)
        end
      when 'git_archive'
        extracted.mkpath
        system('tar', '-xzf', Pathname.new(content_or_path).to_s, '-C', extracted.to_s)
      end
      enforce_cache_limit!
    end

    def get_cached_source(key, output_filename = nil)
      extracted = cache_dir(key).join('extracted')
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
      extracted = cache_dir(key).join('extracted')
      return nil unless extracted.exist?

      extracted
    end

    # ─── Cache-Aware Source Fetchers ────────────────────────────────────────

    # Fetch URL with cache support (follows 30x redirects via Source.fetch_with_redirects)
    def cached_fetch_url(url, expected_sha256)
      Rulepack::Common.log "  [cache] Fetching URL: #{url}"
      content = fetch_with_redirects(url)
      actual_sha256 = Digest::SHA256.hexdigest(content)

      if expected_sha256 && actual_sha256 != expected_sha256
        raise "SHA256 mismatch for #{url}: " \
              "expected #{expected_sha256}, got #{actual_sha256}. " \
              "Update the sha256 field in your PKGBUILD to: #{actual_sha256}"
      end

      # Store in cache
      cache_source(actual_sha256, content, source_type: 'content')

      [content, actual_sha256]
    end

    # Fetch git source with cache support (single file)
    # Returns [content, commit_hash]
    def cached_fetch_git_file(url, ref, git_path, depth: Rulepack::Config.git_clone_depth)
      require 'tmpdir'
      Dir.mktmpdir('rulepack-git-') do |tmp|
        commit_hash = fetch_git_source(url, ref, tmp, depth: depth)
        repo_base = Pathname.new(tmp).realpath
        source_in_repo = repo_base.join(git_path).cleanpath
        raise "Path not found in git repo: #{git_path}" unless source_in_repo.exist?
        resolved_source = source_in_repo.realpath
        unless resolved_source.to_s.start_with?(repo_base.to_s + File::SEPARATOR) || resolved_source == repo_base
          raise "Path traversal in git source path: #{git_path} escapes repository"
        end

        content = source_in_repo.read
        path_hash = Digest::SHA256.hexdigest(git_path.to_s)[0..7]
        cache_key = "#{commit_hash}-#{path_hash}"

        cache_source(cache_key, content, source_type: 'content')
        [content, commit_hash]
      end
    end

    # Fetch git source with cache support (directory / skill-bundle)
    # Returns [persistent_dir_path, commit_hash]
    def cached_fetch_git_dir(url, ref, git_path, depth: Rulepack::Config.git_clone_depth)
      commit_hash = nil
      cache_key = nil
      require 'tmpdir'
      Dir.mktmpdir('rulepack-git-') do |tmp|
        commit_hash = fetch_git_source(url, ref, tmp, depth: depth)
        repo_base = Pathname.new(tmp).realpath
        source_in_repo = repo_base.join(git_path).cleanpath
        raise "Path not found in git repo: #{git_path}" unless source_in_repo.exist?
        resolved_source = source_in_repo.realpath
        unless resolved_source.to_s.start_with?(repo_base.to_s + File::SEPARATOR) || resolved_source == repo_base
          raise "Path traversal in git source path: #{git_path} escapes repository"
        end

        path_hash = Digest::SHA256.hexdigest(git_path.to_s)[0..7]
        cache_key = "#{commit_hash}-#{path_hash}"

        cache_source(cache_key, source_in_repo, source_type: 'file')
      end
      # Return persistent cache dir + hash
      [cache_dir(cache_key).join('extracted'), commit_hash]
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
  end
end
