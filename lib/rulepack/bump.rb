# frozen_string_literal: true

require_relative 'encoding_defaults'
require 'pathname'
require 'yaml'
require 'open3'
require_relative 'common'

module Rulepack
  module Bump
    module_function

    def run(argv)
      options = parse_args(argv)
      packages = discover_git_packages

      if packages.empty?
        puts 'No git-sourced packages found.'
        return 0
      end

      if options[:package_name]
        pkg_name = options[:package_name].to_sym
        unless packages.key?(pkg_name)
          warn "Package '#{pkg_name}' is not a git-sourced package."
          return 1
        end
        packages = { pkg_name => packages[pkg_name] }
      end

      results = check_upstream(packages)
      print_report(results)

      if options[:apply]
        apply_changes(results, packages)
      end

      any_changed = results.any? { |_n, r| r[:status] == :changed }
      any_changed ? 1 : 0
    end

    def parse_args(argv)
      { apply: false, package_name: nil }.tap do |opts|
        argv.each do |arg|
          case arg
          when '--apply'
            opts[:apply] = true
          else
            opts[:package_name] = arg unless arg.start_with?('-')
          end
        end
      end
    end

    def discover_git_packages
      result = {}

      Rulepack::PackageResolver.all_pkgbuilds(namespaces: :tracked).each do |pkgbuild_path|
        raw = pkgbuild_path.read
        pkg = YAML.safe_load(raw, permitted_classes: [Symbol, Pathname], symbolize_names: true) || {}
        pkgname = pkg[:pkgname]
        next unless pkgname

        sources = pkg[:source]
        next unless sources.is_a?(Array) && !sources.empty?

        src = sources.first
        next unless src[:type] == 'git'

        result[pkgname.to_sym] = {
          url: src[:url],
          ref: src[:ref] || 'main',
          path: src[:path],
          depth: src[:depth],
          pkgver: pkg[:pkgver],
          pkgver_func: pkg[:pkgver_func],
          pkgbuild_path: pkgbuild_path,
          pkg_data: pkg
        }
      end

      result
    end

    def check_upstream(packages)
      results = {}
      packages.each do |pkgname, info|
        results[pkgname] = check_single(pkgname, info)
      end
      results
    end

    def check_single(pkgname, info)
      cached_commit = cached_commit_for(pkgname)

      remote_result = fetch_remote_head(info[:url], info[:ref])
      if remote_result[:error]
        return { status: :error, message: remote_result[:error], cached: cached_commit }
      end

      remote_commit = remote_result[:commit]

      if cached_commit.nil?
        { status: :unknown, remote: remote_commit, cached: nil,
          message: 'No cached commit (build required)' }
      elsif cached_commit == remote_commit
        { status: :current, remote: remote_commit, cached: cached_commit,
          message: 'Up to date' }
      else
        { status: :changed, remote: remote_commit, cached: cached_commit,
          message: "New upstream: #{cached_commit[0..7]} → #{remote_commit[0..7]}" }
      end
    rescue StandardError => e
      { status: :error, message: e.message, cached: nil }
    end

    def cached_commit_for(pkgname)
      build_index_path = Rulepack::Common.build_index_path
      return nil unless build_index_path.exist?

      index = YAML.safe_load(build_index_path.read, permitted_classes: [Symbol], symbolize_names: true) || {}
      pkg = index.dig(:packages, pkgname.to_sym) || index.dig(:packages, pkgname.to_s)
      return nil unless pkg

      pkg[:source_sha256] || pkg.dig(:checksums, :source)
    end

    def fetch_remote_head(url, ref)
      if Rulepack::Common.git_available?
        fetch_remote_head_git(url, ref)
      else
        fetch_remote_head_http(url, ref)
      end
    end

    def fetch_remote_head_git(url, ref)
      stdout, stderr, status = Open3.capture3('git', 'ls-remote', '--', url, ref)
      unless status.success?
        return { error: "git ls-remote failed: #{stderr.strip}" }
      end

      commit = stdout.strip.split("\t").first
      if commit && commit.match?(/^[0-9a-f]{40}$/i)
        { commit: commit }
      else
        { error: "No matching ref '#{ref}' in #{url}" }
      end
    rescue StandardError => e
      { error: e.message }
    end

    def fetch_remote_head_http(url, ref)
      clean_url = url.sub(/\.git$/, '')
      unless clean_url =~ %r{github\.com/([^/]+)/([^/]+)} || clean_url =~ %r{gitlab\.com/([^/]+)/([^/]+)}
        return { error: "Cannot check remote HEAD without git for non-GitHub/GitLab URL: #{url}" }
      end

      owner = $1
      repo = $2
      api_url = "https://api.github.com/repos/#{owner}/#{repo}/commits/#{ref}"

      begin
        require 'json'
        content = Rulepack::Common.fetch_with_redirects(api_url)
        data = JSON.parse(content)
        sha = data['sha']
        if sha && sha.match?(/^[0-9a-f]{40}$/i)
          { commit: sha }
        else
          { error: "Could not parse commit SHA from API response for #{url}" }
        end
      rescue StandardError => e
        { error: "HTTP fallback failed: #{e.message}" }
      end
    end

    def print_report(results)
      puts "\n📦 Upstream Version Check"
      puts '━' * 60

      results.each do |pkgname, r|
        label = case r[:status]
                when :current then "\e[32m[CURRENT]\e[0m"
                when :changed then "\e[33m[CHANGED]\e[0m"
                when :unknown then "\e[36m[UNKNOWN]\e[0m"
                when :error   then "\e[31m[ERROR]\e[0m"
                end
        puts "  #{label} #{pkgname} — #{r[:message]}"
        if r[:remote]
          puts "           remote: #{r[:remote][0..11]}"
          puts "           cached: #{r[:cached] ? r[:cached][0..11] : 'none'}"
        end
      end

      changed = results.count { |_, r| r[:status] == :changed }
      current = results.count { |_, r| r[:status] == :current }
      errors = results.count { |_, r| r[:status] == :error }
      unknown = results.count { |_, r| r[:status] == :unknown }

      puts
      puts "  Summary: #{changed} changed, #{current} current, #{unknown} unknown, #{errors} error(s)"
    end

    def apply_changes(results, packages)
      changed = results.select { |_, r| r[:status] == :changed }
      if changed.empty?
        puts "\n  No changes to apply."
        return
      end

      puts "\n🔨 Applying upstream changes..."

      changed.each do |pkgname, result|
        info = packages[pkgname]
        new_ver = compute_new_version(info, result)
        update_pkgbuild(info, new_ver)
        invalidate_cache(pkgname, info, result)
        puts "  ✓ #{pkgname}: pkgver updated to '#{new_ver}'"
      end

      puts "\n  Rebuilding changed packages..."
      invoke_build
    end

    def compute_new_version(info, _result)
      if info[:pkgver_func]
        run_pkgver_func(info)
      else
        date_based_version
      end
    end

    def run_pkgver_func(info)
      Dir.mktmpdir('rulepack-bump-') do |tmp|
        Rulepack::Common.fetch_git_source(info[:url], info[:ref], tmp, depth: info[:depth] || 1)
        stdout, stderr, status = Dir.chdir(tmp) do
          Open3.capture2e(info[:pkgver_func])
        end
        unless status.success?
          warn "  ⚠ pkgver_func failed for #{info[:url]}: #{stderr.strip}"
          return date_based_version
        end
        ver = stdout.strip
        ver.empty? ? date_based_version : ver
      end
    rescue StandardError => e
      warn "  ⚠ pkgver_func error: #{e.message}"
      date_based_version
    end

    def date_based_version
      Time.now.utc.strftime('%Y.%m.%d')
    end

    def update_pkgbuild(info, new_ver)
      path = info[:pkgbuild_path]
      raw = path.read
      pkg = YAML.safe_load(raw, permitted_classes: [Symbol, Pathname], symbolize_names: true) || {}

      old_ver = pkg[:pkgver]
      return if old_ver == new_ver

      pkg[:pkgver] = new_ver
      pkg[:pkgrel] = 1

      stringified = deep_stringify_keys(pkg)
      path.write("#{stringified.to_yaml}\n")
      Rulepack::Common.log "  Updated #{path.basename}: #{old_ver} → #{new_ver}"
    end

    def deep_stringify_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), h|
          h[k.to_s] = deep_stringify_keys(v)
        end
      when Array
        obj.map { |v| deep_stringify_keys(v) }
      else
        obj
      end
    end

    def invalidate_cache(pkgname, info, result)
      cached = cached_commit_for(pkgname)
      return unless cached

      cache_dir = Rulepack::Common.cache_dir(cached)
      if cache_dir.exist?
        FileUtils.rm_rf(cache_dir)
        Rulepack::Common.log "  Invalidated cache for #{pkgname} (#{cached[0..7]})"
      end

      return unless result[:remote]

      path_hash = Digest::SHA256.hexdigest((info[:path] || '.').to_s)[0..7]
      cache_key = "#{result[:remote]}-#{path_hash}"
      new_cache = Rulepack::Common.cache_dir(cache_key)
      FileUtils.rm_rf(new_cache) if new_cache.exist?
    end

    def invoke_build
      build_index = Rulepack::Common::BUILD_INDEX_PATH
      FileUtils.rm_f(build_index) if build_index.exist?

      Rulepack::Build.run
      Rulepack::Aggregate.run
    end
  end
end

if __FILE__ == $PROGRAM_NAME || defined?(Rulepack::CLI)
  Rulepack::Bump.run(ARGV)
end
