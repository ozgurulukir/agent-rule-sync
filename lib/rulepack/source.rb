# frozen_string_literal: true


require 'open3'
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

    def fetch_git_source(url, ref, dest_dir, depth: nil)
      # Try main first, fallback to master if ref not specified

      # We'll try main, then master during clone
      ref ||= 'main'

      # Build git clone command
      cmd = %w[git clone]
      cmd << '--depth=1' if depth
      # Determine if ref is a full commit hash (40 hex chars) → cannot use --branch
      is_commit = ref =~ /^[0-9a-f]{40}$/i
      cmd << "--branch=#{ref}" if ref && !is_commit
      cmd << '--quiet'
      cmd << url
      cmd << dest_dir

      unless system(*cmd)
        # If main failed, try master (only when ref was default 'main')
        if ref == 'main' && !is_commit && !system('git', 'clone', '--depth=1', '--branch=master', '--quiet', url,
                                                  dest_dir)
          raise "git clone failed for #{url} (tried main and master). " \
                'Check the URL is correct and you have network access.'
        else
          raise "git clone failed for #{url}"
        end
      end

      # If ref is a commit hash (full), we need to checkout that exact commit
      if is_commit
        Dir.chdir(dest_dir) do
          unless system('git', 'checkout', '--quiet', ref)
            raise "git checkout #{ref} failed. Verify the ref (branch/tag/commit) exists in the repository."
          end
        end
      end

      # Get the commit hash we ended up on
      commit_hash = Dir.chdir(dest_dir) { `git rev-parse HEAD`.strip }
      stdout, status = Dir.chdir(dest_dir) { Open3.capture2e('git', 'rev-parse', 'HEAD') }
      commit_hash = stdout.strip
      raise 'Failed to get commit hash from cloned repo' if commit_hash.empty? || commit_hash.length < 40

      commit_hash
    end

    def fetch_with_redirects(url, limit = Rulepack::Config.max_redirects)
      raise "HTTP Redirect Loop: too many redirects for #{url}" if limit <= 0

      uri = URI.parse(url)
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
        raise "Failed to fetch #{url}: #{response.code} #{response.message}"
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

        content = path.read
        checksum = Digest::SHA256.hexdigest(content)
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
