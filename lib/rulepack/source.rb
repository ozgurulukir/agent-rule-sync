# frozen_string_literal: true


require 'open3'
require 'zlib'
require 'rubygems/package'
require 'stringio'
module Rulepack
  module Common
    module_function

    # Check platform prerequisites (system tools) and warn if missing.
    # prerequisites format (from platforms.yaml):
    #   tools: [ruby, python, go, node]
    #   versions: { ruby: ">=2.7", python: ">=3.8" }
    # Returns array of missing tools (empty = all present).
    def check_prerequisites(platform_cfg)
      prereqs = platform_cfg[:prerequisites] || platform_cfg['prerequisites'] || {}
      tools = prereqs[:tools] || prereqs['tools']
      versions = prereqs[:versions] || prereqs['versions']

      missing = []

      # Check tools
      Array(tools).each do |tool|
        found = ENV['PATH'].split(File::PATH_SEPARATOR).any? { |d| File.executable?("#{d}/#{tool}") }
        missing << tool unless found
      end

      # Check versions (informational only, no enforcement)
      Array(versions).each do |tool, version_req|
        next if missing.include?(tool) # skip if tool isn't even installed

        version_output = ''
        begin
          flag = if tool.to_s == 'ruby'
                   '-v'
                 elsif tool.to_s == 'go'
                   'version'
                 else
                   '--version'
                 end
          version_output, = Open3.capture2e(tool, flag.to_s)
        rescue StandardError
          next
        end

        if version_output =~ /(\d+\.\d+(?:\.\d+)?)/
          active_version = $1
          if version_req.to_s =~ /^([>=<!]+)?\s*(.*)$/
            op = $1 || '>='
            req_ver = $2
            cmp = vercmp(active_version, req_ver)
            match = case op
                    when '>=' then cmp >= 0
                    when '<=' then cmp <= 0
                    when '>'  then cmp > 0
                    when '<'  then cmp < 0
                    when '==' then cmp.zero?
                    when '='  then cmp.zero?
                    when '!=' then cmp != 0
                    else
                      cmp >= 0
                    end

            unless match
              Rulepack::Common.log_warn "Tool version mismatch for #{tool}: active #{active_version}, required #{version_req}"
              puts "  ⚠️  Tool version mismatch for #{tool}: active #{active_version}, required #{version_req}"
            end
          end
        end
      end

      missing
    end

    def git_available?
      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |d|
        %w[git git.exe].any? { |f| File.executable?(File.join(d, f)) }
      end
    end

    def translate_git_to_tarball(url, ref)
      clean_url = url.sub(/^git@github\.com:/, 'https://github.com/').sub(/\.git$/, '')
      if clean_url =~ %r{github\.com/([^/]+)/([^/]+)}
        owner = $1
        repo = $2
        "https://github.com/#{owner}/#{repo}/archive/#{ref}.tar.gz"
      elsif clean_url =~ %r{gitlab\.com/([^/]+)/([^/]+)}
        owner = $1
        repo = $2
        "https://gitlab.com/#{owner}/#{repo}/-/archive/#{ref}/#{repo}-#{ref}.tar.gz"
      else
        nil
      end
    end

    def extract_tar_gz(tar_gz_content, dest_dir)
      FileUtils.mkdir_p(dest_dir)
      expanded_dest_dir = File.expand_path(dest_dir)

      Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(tar_gz_content))) do |tar|
        tar.each do |entry|
          parts = entry.full_name.split('/')
          next if parts.size <= 1 # skip top-level root directory inside tar

          rel_path = parts[1..-1].join('/')
          dest_path = File.expand_path(File.join(dest_dir, rel_path))

          unless dest_path.start_with?(expanded_dest_dir + File::SEPARATOR)
            raise "Path traversal detected in tarball entry: #{entry.full_name}"
          end

          if entry.directory?
            FileUtils.mkdir_p(dest_path)
          elsif entry.file?
            FileUtils.mkdir_p(File.dirname(dest_path))
            File.open(dest_path, 'wb') { |f| f.write(entry.read) }
          elsif entry.header.typeflag == '2' # Symlink — skip for safety (path traversal risk)
            Rulepack::Common.log_warn "Skipping symlink in tarball: #{entry.full_name} -> #{entry.header.linkname}"
          end
        end
      end
    end

    def fetch_git_source(url, ref, dest_dir, depth: nil)
      ref ||= 'main'
      is_commit = ref =~ /^[0-9a-f]{40}$/i

      if git_available?
        begin
          cmd = %w[git clone]
          cmd << '--depth=1' if depth && !is_commit
          cmd << "--branch=#{ref}" if ref && !is_commit
          cmd << '--quiet'
          cmd << url
          cmd << dest_dir

          if system(*cmd)
            if is_commit
              Dir.chdir(dest_dir) do
                system('git', 'checkout', '--quiet', ref)
              end
            end
            stdout, status = Dir.chdir(dest_dir) { Open3.capture2e('git', 'rev-parse', 'HEAD') }
            commit_hash = stdout.strip
            return commit_hash if status.success? && !commit_hash.empty? && commit_hash.length >= 40
          end
        rescue StandardError => e
          Rulepack::Common.log_warn "Git clone failed: #{e.message}. Trying HTTP fallback..."
        end
      end

      # HTTP Fallback
      Rulepack::Common.log_warn "Git command unavailable or clone failed. Initiating HTTP fallback for #{url}..."
      tarball_url = translate_git_to_tarball(url, ref)
      unless tarball_url
        raise "Git command unavailable and cannot auto-translate #{url} to a tarball URL."
      end

      Rulepack::Common.log "  → Downloading tarball from #{tarball_url}"
      begin
        tar_gz_content = fetch_with_redirects(tarball_url)
        extract_tar_gz(tar_gz_content, dest_dir)
        commit_hash = Digest::SHA256.hexdigest("#{url}-#{ref}")[0...40]
        Rulepack::Common.log "  ✓ HTTP fallback successful. Generated stable cache hash: #{commit_hash[0..7]}"
        commit_hash
      rescue StandardError => e
        raise "Git clone and HTTP fallback both failed for #{url}: #{e.message}"
      end
    end

    def fetch_with_redirects(url, limit = Rulepack::Config.max_redirects)
      raise "HTTP Redirect Loop: too many redirects for #{url}" if limit <= 0

      uri = URI.parse(url)
      raise URI::InvalidURIError, "Invalid URL (no host): #{url}" unless uri.host
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = Rulepack::Config.read_timeout
      http.open_timeout = Rulepack::Config.read_timeout

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        redirect_url = response['location']
        unless redirect_url.start_with?('http://', 'https://')
          redirect_url = URI.join(url, redirect_url).to_s
        end
        fetch_with_redirects(redirect_url, limit - 1)
      else
        response.body
      end
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
        raise "Local source not found: #{path}. Check that the path in PKGBUILD source is correct." unless path.exist?

        if path.directory?
          # Deterministic content hash: sort files by path, concatenate content, hash
          content = path.find.to_a.sort_by(&:to_s).select(&:file?).map(&:read).join
          checksum = Digest::SHA256.hexdigest(content)
        else
          content = path.read
          checksum = Digest::SHA256.hexdigest(content)
        end
        [content, checksum]
      when 'url'
        url = source_entry[:url]
        expected_sha256 = source_entry[:sha256]

        content = fetch_with_redirects(url)
        actual_sha256 = Digest::SHA256.hexdigest(content)

        if expected_sha256 && actual_sha256 != expected_sha256
          raise "SHA256 mismatch for #{url}: " \
                "expected #{expected_sha256}, got #{actual_sha256}. " \
                "Update the sha256 field in your PKGBUILD to: #{actual_sha256}"
        end

        [content, actual_sha256]
      else
        raise "Unknown source type: #{source_entry[:type]}"
      end
    end
  end
end
