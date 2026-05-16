# frozen_string_literal: true

module Rulepack
  module Common
    module_function

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
        found = ENV['PATH'].split(File::PATH_SEPARATOR).any? { |d| File.executable?("#{d}/#{tool}") }
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
      raise 'Failed to get commit hash from cloned repo' if commit_hash.empty? || commit_hash.length < 40

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
        raise "Local source not found: #{path}. Check that the path in PKGBUILD source is correct." unless path.exist?

        content = path.read
        checksum = Digest::SHA256.hexdigest(content)
        [content, checksum]
      when 'url'
        url = source_entry[:url]
        expected_sha256 = source_entry[:sha256]

        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)

        raise "Failed to fetch #{url}: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        content = response.body
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
