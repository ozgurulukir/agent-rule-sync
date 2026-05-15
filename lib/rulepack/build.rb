#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require 'net/http'
require 'uri'
require 'json'
require_relative 'common'

RULEPACK_ROOT = Pathname.new(__dir__).parent.parent.expand_path
BUILD_DIR = RULEPACK_ROOT.join('build')
BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')
INDEX_JSON_PATH = RULEPACK_ROOT.join('data', 'index.json')
LOG_PATH = BUILD_DIR.join("build.log")
Rulepack::Common.set_log_file(LOG_PATH)

# ─── Helpers ────────────────────────────────────────────────────────────────────

def fetch_url(url_str, expected_sha256 = nil, max_redirects: Rulepack::Config.max_redirects)
  uri = URI.parse(url_str)
  max_redirects.times do
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: Rulepack::Config.read_timeout) do |http|
      http.request_get(uri.request_uri)
    end

    case response
    when Net::HTTPSuccess
      content = response.body
      computed = Digest::SHA256.hexdigest(content)

      if expected_sha256 && expected_sha256 != computed
        raise "SHA256 mismatch for #{url_str}: expected #{expected_sha256}, got #{computed}. Update the sha256 field in your PKGBUILD to: #{computed}"
      end

      return content
    when Net::HTTPRedirection
      location = response['location']
      uri = URI.parse(location)
      next
    else
      raise "HTTP #{response.code}: #{response.message} for #{url_str}"
    end
  end

  raise "Too many redirects for #{url_str}"
end

# ─── Load registry and index ────────────────────────────────────────────────────

Rulepack::Common.log "🔧 Loading platform registry..."
_platforms = Rulepack::Common.load_platform_registry

index_data = if RULEPACK_ROOT.join('data', 'index.yaml').exist?
               Rulepack::Common.load_yaml(RULEPACK_ROOT.join('data', 'index.yaml'))
             else
               { version: 3.0, generated: nil, packages: {} }
             end

index_data[:version] = 3.0
index_data[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
index_data[:packages] ||= {}

# ─── Discover PKGBUILDs ────────────────────────────────────────────────────────

pkgbuilds = RULEPACK_ROOT.join('data', 'packages').glob('*/PKGBUILD')
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

  Rulepack::Common.log "Building: #{pkgname} (#{Rulepack::Common.format_version(pkg[:epoch], pkg[:pkgver], pkg[:pkgrel])})"

  Rulepack::Common.time("build #{pkgname}") do
  puts "Building: #{pkgname} (#{Rulepack::Common.format_version(pkg[:epoch], pkg[:pkgver], pkg[:pkgrel])})"

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
  all_skill_bundle = pkg[:targets].all? { |t| t[:format] == 'skill-bundle' }

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
      if pkg[:pkgver_func]
        Rulepack::Common.log "  Running pkgver_func: #{pkg[:pkgver_func]}"
        new_pkgver = nil
        Dir.chdir(source_dir) do
          new_pkgver = `#{pkg[:pkgver_func]}`.strip
        end
        if new_pkgver.empty?
          Rulepack::Common.log_error "pkgver_func returned empty version for #{pkgname}"
          skip_pkg = true
        else
          Rulepack::Common.log "  pkgver updated: #{pkg[:pkgver]} → #{new_pkgver}"
          pkg[:pkgver] = new_pkgver
          pkg_index[:pkgver] = new_pkgver
        end
      end

      Rulepack::Common.log "  ✓ Source directory verified: #{source_dir}"
      puts "  ✓ Source directory verified: #{source_dir}"
    when 'git'
      git_url = src_cfg[:url]
      git_ref = src_cfg[:ref] || 'main'
      git_path = Pathname.new(src_cfg[:path] || '.')
      git_depth = src_cfg[:depth] || 1
      Rulepack::Common.log "  Fetching git repo (cached): #{git_url} (ref: #{git_ref})"
      cached_dir, commit_hash = Rulepack::Common.cached_fetch_git_dir(git_url, git_ref, git_path, depth: git_depth)
      persistent_dir = BUILD_DIR.join("git-sources", pkgname.to_s)
      FileUtils.rm_rf(persistent_dir)
      FileUtils.mkpath(persistent_dir.parent)
      FileUtils.cp_r(cached_dir, persistent_dir)
      pkg_index[:source_dir] = persistent_dir.to_s
      pkg_index[:source_sha256] = commit_hash
      Rulepack::Common.log "  ✓ Git source cached/build dir (#{commit_hash[0..7]})"
      puts "  ✓ Git source cached/build dir (#{commit_hash[0..7]})"

      if pkg[:pkgver_func]
        Rulepack::Common.log "  Running pkgver_func: #{pkg[:pkgver_func]}"
        new_pkgver = nil
        Dir.chdir(persistent_dir) do
          new_pkgver = `#{pkg[:pkgver_func]}`.strip
        end
        if new_pkgver.empty?
          Rulepack::Common.log_error "pkgver_func returned empty version for #{pkgname}"
          skip_pkg = true
        else
          Rulepack::Common.log "  pkgver updated: #{pkg[:pkgver]} → #{new_pkgver}"
          pkg[:pkgver] = new_pkgver
          pkg_index[:pkgver] = new_pkgver
        end
      end
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
      source_content, source_sha256 = Rulepack::Common.cached_fetch_git_file(git_url, git_ref, git_path, depth: git_depth)
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

  targets.each do |tgt|
    platform_id = tgt[:platform]
    format = tgt[:format]
    output = tgt[:output]
    translate = tgt[:translate] || nil   # optional translate step (before transformer)
    transformer = tgt[:transformer] || 'copy'
    _install_cfg = tgt[:install] || {}

    if format == 'skill-bundle'
      Rulepack::Common.log "  → Building for #{platform_id} (skill-bundle: #{pkgname})"
      puts "  → Building for #{platform_id} (skill-bundle: #{pkgname})"

      # skill-bundle: copy entire source directory tree
      source_dir = Pathname.new(pkg_index[:source_dir] || raise("internal error: source_dir not set for skill-bundle"))
      # Build directory: build/<platform>/<pkgname>/
      build_platform_dir = BUILD_DIR.join(platform_id)
      begin
        build_pkg_dir = build_platform_dir.join(pkgname.to_s)
        FileUtils.mkpath(build_pkg_dir)
        # Copy all contents recursively, preserving hidden files and empty directories
        FileUtils.cp_r("#{source_dir}/.", build_pkg_dir, preserve: false)
      rescue => e
        Rulepack::Common.log_error "Failed to copy skill-bundle source: #{e.message}"
        next
      end

      Rulepack::Common.log "    ✓ Built skill-bundle (directory copied)"
      puts "    ✓ Built skill-bundle (directory copied)"

       # ─── L4.4 Skill-bundle manifest ─────────────────────────────────────────────
       # Generate per-file SHA256 checksums for integrity verification
       manifest = Rulepack::Common.generate_skill_bundle_manifest(build_pkg_dir, pkgname, platform_id)
       Rulepack::Common.log "    ✓ Skill-bundle manifest generated: #{manifest[:sub_skills].size} sub-skill(s)"
       puts "    ✓ Skill-bundle manifest generated: #{manifest[:sub_skills].size} sub-skill(s)"

      # Record in package index (no single checksum for bundle; use source_sha256 i.e. commit hash or nil)
      unless pkg_index[:available_targets].include?(platform_id)
        pkg_index[:available_targets] << platform_id
      end
      pkg_index[:checksums][:built][platform_id.to_s] = pkg_index[:source_sha256]
    else
      # Single-file formats: directory, import, skill
      Rulepack::Common.log "  → Building for #{platform_id} (#{output})"
      puts "  → Building for #{platform_id} (#{output})"

      # Validate output filename (path traversal protection)
      begin
        Rulepack::Common.validate_output_filename(output, pkgname)
      rescue => e
        log_error e.message
        next
      end

      # ─── TRANSLATE step ────────────────────────────────────────────────────────
      # Platform-specific content conversion (markdown dialect, format family).
      # Runs BEFORE transformer. No-op if translate is nil or 'copy'.
      if translate
        Rulepack::Common.log "  → Translating for #{platform_id} (#{translate})"
        puts "  → Translating for #{platform_id} (#{translate})"
        begin
          source_content = Rulepack::Common.apply_translator(translate, source_content, pkgname: pkgname)
        rescue => e
          Rulepack::Common.log_error "Translator failed for #{pkgname}/#{platform_id}: #{e.message}"
          next
        end
        Rulepack::Common.log "    ✓ Translated (#{translate})"
        puts "    ✓ Translated (#{translate})"
      end

      # ─── TRANSFORM step ────────────────────────────────────────────────────────
      # Structural/format changes (copy, strip-frontmatter, custom)
      begin
        transformed = Rulepack::Common.apply_transformer(transformer, source_content, pkgname: pkgname)
      rescue => e
        Rulepack::Common.log_error "Transformer failed for #{pkgname}/#{platform_id}: #{e.message}"
        next
      end

      built_sha256 = Digest::SHA256.hexdigest(transformed)

      # Write to build directory
      begin
        build_platform_dir = BUILD_DIR.join(platform_id)
        build_platform_dir.mkpath
        build_file = build_platform_dir.join(output)
        build_file.write(transformed)
      rescue => e
        Rulepack::Common.log_error "Failed to write build artifact for #{pkgname}/#{platform_id}: #{e.message}"
        next
      end

      Rulepack::Common.log "    ✓ Built #{output} (#{built_sha256[0..7]})"
      puts "    ✓ Built #{output} (#{built_sha256[0..7]})"

      # Record in package index
      unless pkg_index[:available_targets].include?(platform_id)
        pkg_index[:available_targets] << platform_id
      end
      pkg_index[:checksums][:built][platform_id.to_s] = built_sha256
    end
  end

  # Update index
  index_data[:packages][pkgname] = pkg_index
  end  # time("build #{pkgname}")
end

# ─── Write build index ─────────────────────────────────────────────────────────

build_index_data = {
  version: 3.0,
  generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
  packages: index_data[:packages]
}
begin
  Rulepack::Common.write_yaml_atomic(BUILD_INDEX_PATH, build_index_data)
  Rulepack::Common.log "📝 Build index written: #{BUILD_INDEX_PATH}"
  puts "\n📝 Build index written: #{BUILD_INDEX_PATH}"
rescue => e
  Rulepack::Common.log_error "Failed to write build index: #{e.message}"
  exit 1
end

# ─── Write master index (data/index.yaml) ─────────────────────────────────────

begin
  Rulepack::Common.write_yaml_atomic(RULEPACK_ROOT.join('data', 'index.yaml'), index_data)
  Rulepack::Common.log "📝 Master index written: #{RULEPACK_ROOT.join('data', 'index.yaml')}"
rescue => e
  Rulepack::Common.log_error "Failed to write master index: #{e.message}"
  exit 1
end

# ─── Write derived JSON index ──────────────────────────────────────────────────

begin
  INDEX_JSON_PATH.write(JSON.pretty_generate(index_data))
  Rulepack::Common.log "📝 JSON index written: #{INDEX_JSON_PATH}"
rescue => e
  Rulepack::Common.log_error "Failed to write JSON index: #{e.message}"
end

# ─── Generate catalog.json ─────────────────────────────────────────────────────

begin
  system(RbConfig.ruby, RULEPACK_ROOT.join('lib', 'rulepack', 'generate-catalog.rb').to_s)
rescue => e
  Rulepack::Common.log_error "Failed to generate catalog: #{e.message}"
end

puts "✅ Build complete. Run `ruby lib/rulepack/install.rb <platform>` to install packages."
