#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require 'net/http'
require 'uri'
require 'json'
require_relative 'lib/common'

SSOT_ROOT = Pathname.new(__dir__).expand_path
BUILD_DIR = SSOT_ROOT.join('build')
BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')
INDEX_JSON_PATH = SSOT_ROOT.join('index.json')
LOG_PATH = BUILD_DIR.join('build.log')

# ─── Logging ────────────────────────────────────────────────────────────────────

def log(msg)
  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
  line = "[#{timestamp}] #{msg}"
  puts line
  FileUtils.mkpath(BUILD_DIR)
  File.open(LOG_PATH, 'a') { |f| f.puts(line) }
end

def log_error(msg)
  warn "❌ #{msg}"
  log("ERROR: #{msg}")
end

def log_warn(msg)
  warn "⚠️  #{msg}"
  log("WARN: #{msg}")
end

# ─── Helpers (delegated to Common) ────────────────────────────────────────────

def fetch_url(url_str, expected_sha256 = nil, max_redirects: 3)
  uri = URI.parse(url_str)
  max_redirects.times do
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 30) do |http|
      http.request_get(uri.request_uri)
    end

    case response
    when Net::HTTPSuccess
      content = response.body
      computed = Digest::SHA256.hexdigest(content)

      if expected_sha256 && expected_sha256 != computed
        log_warn "SHA256 mismatch for #{url_str}: expected #{expected_sha256[0..7]}, got #{computed[0..7]}"
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

def apply_transformer(content, transformer_cfg, pkgname:)
  Ssot::Lib::Common.apply_transformer(transformer_cfg, content, pkgname: pkgname)
end

def validate_output_filename(output, pkgname)
  Ssot::Lib::Common.validate_output_filename(output, pkgname)
end

# ─── Load registry and index ───────────────────────────────────────────────────

log "🔧 Loading platform registry..."
platforms = Ssot::Lib::Common.load_platform_registry

index_data = if SSOT_ROOT.join('index.yaml').exist?
               Ssot::Lib::Common.load_yaml(SSOT_ROOT.join('index.yaml'))
             else
               { version: 3.0, generated: nil, packages: {} }
             end

index_data[:version] = 3.0
index_data[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
index_data[:packages] ||= {}

# ─── Discover PKGBUILDs ────────────────────────────────────────────────────────

pkgbuilds = SSOT_ROOT.join('packages').glob('*/PKGBUILD')
log "📦 Found #{pkgbuilds.size} package(s)"
puts "📦 Found #{pkgbuilds.size} package(s)\n\n"

# ─── Build each package ────────────────────────────────────────────────────────

  pkgbuilds.each do |pkgbuild_path|
    pkg_dir = pkgbuild_path.dirname
  pkg = Ssot::Lib::Common.load_pkgbuild(pkg_dir)

  pkgname = pkg[:pkgname].to_sym
  # Set default epoch/pkgrel before validation (PKGBUILD may omit them)
  pkg[:epoch] = 0 unless pkg.key?(:epoch)
  pkg[:pkgrel] = 1 unless pkg.key?(:pkgrel)

  # Validate PKGBUILD
  validation_error = Ssot::Lib::Common.validate_pkgbuild(pkg, pkg_dir)
  if validation_error != true
    log_error "PKGBUILD validation failed for #{pkgname}: #{validation_error}"
    next
  end

  log "Building: #{pkgname} (#{pkg[:pkgver]}:#{pkg[:pkgrel]})"
  puts "Building: #{pkgname} (#{pkg[:pkgver]}:#{pkg[:pkgrel]})"

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

       # Determine if we need to read source content (for any non-skill-bundle target)
       all_skill_bundle = pkg[:targets].all? { |t| t[:format] == 'skill-bundle' }

       skip_pkg = false

       if all_skill_bundle
        # ─── skill-bundle: source must be a directory (local or git) ──────────────────
        src_cfg = pkg[:source].first
        unless src_cfg
          log_error "No source defined for #{pkgname} (skill-bundle)"
          next
        end

        case src_cfg[:type]
        when 'local'
          src_path = src_cfg[:path]
          source_dir = if src_path.start_with?('/') || src_path.start_with?('~')
                         Pathname.new(Ssot::Lib::Common.expand_user_path(src_path))
                       else
                         pkg_dir.join(src_path)
                       end
          source_dir = source_dir.cleanpath
          unless source_dir.directory?
            log_error "Source path must be a directory for skill-bundle: #{source_dir}"
            next
          end
           pkg_index[:source_dir] = source_dir
           pkg_index[:source_sha256] = nil

           # Run pkgver_func if defined
           if pkg[:pkgver_func]
             log "  Running pkgver_func: #{pkg[:pkgver_func]}"
             new_pkgver = nil
             Dir.chdir(source_dir) do
               new_pkgver = `#{pkg[:pkgver_func]}`.strip
             end
            if new_pkgver.empty?
                log_error "pkgver_func returned empty version for #{pkgname}"
                skip_pkg = true
              else
                log "  pkgver updated: #{pkg[:pkgver]} → #{new_pkgver}"
                pkg[:pkgver] = new_pkgver
                pkg_index[:pkgver] = new_pkgver
                log "  DEBUG: after update pkg_index[:pkgver]=#{pkg_index[:pkgver]} pkg[:pkgver]=#{pkg[:pkgver]}"
              end
           end

           log "  ✓ Source directory verified: #{source_dir}"
           puts "  ✓ Source directory verified: #{source_dir}"
      when 'git'
        git_url = src_cfg[:url]
        git_ref = src_cfg[:ref] || 'main'
        git_path = Pathname.new(src_cfg[:path] || '.')
        git_depth = src_cfg[:depth] || 1
        log "  Fetching git repo (cached): #{git_url} (ref: #{git_ref})"
        cached_dir, commit_hash = Ssot::Lib::Common.cached_fetch_git_dir(git_url, git_ref, git_path, depth: git_depth)
        persistent_dir = BUILD_DIR.join("git-sources", pkgname.to_s)
        FileUtils.rm_rf(persistent_dir)
        FileUtils.mkpath(persistent_dir.parent)
        FileUtils.cp_r(cached_dir, persistent_dir)
        pkg_index[:source_dir] = persistent_dir
        pkg_index[:source_sha256] = commit_hash
        log "  ✓ Git source cached/build dir (#{commit_hash[0..7]})"
        puts "  ✓ Git source cached/build dir (#{commit_hash[0..7]})"

        if pkg[:pkgver_func]
          log "  Running pkgver_func: #{pkg[:pkgver_func]}"
          new_pkgver = nil
          Dir.chdir(persistent_dir) do
            new_pkgver = `#{pkg[:pkgver_func]}`.strip
          end
          if new_pkgver.empty?
            log_error "pkgver_func returned empty version for #{pkgname}"
            skip_pkg = true
          else
            log "  pkgver updated: #{pkg[:pkgver]} → #{new_pkgver}"
            pkg[:pkgver] = new_pkgver
            pkg_index[:pkgver] = new_pkgver
            log "  DEBUG: after update pkg_index[:pkgver]=#{pkg_index[:pkgver]} pkg[:pkgver]=#{pkg[:pkgver]}"
          end
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
          log_warn "  ⚠ No source defined for #{pkgname}, skipping"
          next
        end

        case src_cfg[:type]
        when 'local'
          source_content, source_sha256 = Ssot::Lib::Common.read_source(src_cfg, pkg_dir)
        when 'url'
          url = src_cfg[:url]
          expected = src_cfg[:sha256]
          source_content, source_sha256 = Ssot::Lib::Common.cached_fetch_url(url, expected)
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
           log "  Fetching git file (cached): #{git_url} (#{git_path})"
           source_content, source_sha256 = Ssot::Lib::Common.cached_fetch_git_file(git_url, git_ref, git_path, depth: git_depth)
        else
          log_warn "  ⚠ Unknown source type: #{src_cfg[:type]} for #{pkgname}"
          next
        end

        pkg_index[:checksums][:source] = source_sha256
        log "  ✓ Fetched source (#{source_sha256[0..7]})"
        puts "  ✓ Fetched source (#{source_sha256[0..7]})"

        # For URL sources, update PKGBUILD with fetched sha256
        if src_cfg[:type] == 'url' && src_cfg[:sha256] != source_sha256
          src_cfg[:sha256] = source_sha256
          pkgbuild_path.write({ **pkg, source: sources }.to_yaml)
        end
      end  # if all_skill_bundle

    # ─── Process each target ──────────────────────────────────────────────────────
  targets = pkg[:targets]
  targets = [targets] unless targets.is_a?(Array)

   targets.each do |tgt|
     platform_id = tgt[:platform]
     format = tgt[:format]
     output = tgt[:output]
     transformer = tgt[:transformer] || 'copy'
     install_cfg = tgt[:install] || {}

      if format == 'skill-bundle'
        log "  → Building for #{platform_id} (skill-bundle: #{pkgname})"
        puts "  → Building for #{platform_id} (skill-bundle: #{pkgname})"

         # skill-bundle: copy entire source directory tree
         source_dir = pkg_index[:source_dir] || raise("internal error: source_dir not set for skill-bundle")
         # Build directory: build/<platform>/<pkgname>/
         build_platform_dir = BUILD_DIR.join(platform_id)
         begin
           build_pkg_dir = build_platform_dir.join(pkgname.to_s)
           FileUtils.mkpath(build_pkg_dir)
           # Copy all contents recursively, preserving hidden files and empty directories
           FileUtils.cp_r("#{source_dir}/.", build_pkg_dir, preserve: false)
         rescue => e
           log_error "Failed to copy skill-bundle source: #{e.message}"
           next
         end

        log "    ✓ Built skill-bundle (directory copied)"
        puts "    ✓ Built skill-bundle (directory copied)"

        # Record in package index (no single checksum for bundle; use source_sha256 i.e. commit hash or nil)
        unless pkg_index[:available_targets].include?(platform_id)
          pkg_index[:available_targets] << platform_id
        end
        pkg_index[:checksums][:built][platform_id] = pkg_index[:source_sha256]
       else
         # Single-file formats: directory, import, skill
         log "  → Building for #{platform_id} (#{output})"
         puts "  → Building for #{platform_id} (#{output})"

         # Validate output filename (path traversal protection)
         begin
           validate_output_filename(output, pkgname)
         rescue => e
           log_error e.message
           next
         end

         # Transform
         begin
           transformed = apply_transformer(source_content, transformer, pkgname: pkgname)
         rescue => e
           log_error "Transformer failed for #{pkgname}/#{platform_id}: #{e.message}"
           next
         end

         built_sha256 = Digest::SHA256.hexdigest(transformed)

         # Write to build directory
         begin
           build_platform_dir = BUILD_DIR.join(platform_id)
           build_platform_dir.mkpath
           build_output_path = build_platform_dir.join(output)
           build_output_path.parent.mkpath
           Ssot::Lib::Common.atomic_write(build_output_path, transformed)
         # Check for empty content after transform
         if transformed.strip.empty?
           log_warn "Empty content after transform: #{build_output_path}"
           puts "    ⚠️  Empty content after transform: #{build_output_path}"
         end
         rescue => e
           log_error "Failed to write build artifact: #{e.message}"
           next
         end

         log "    ✓ Built (#{built_sha256[0..7]})"
         puts "    ✓ Built (#{built_sha256[0..7]})"

         # Record in package index
         unless pkg_index[:available_targets].include?(platform_id)
           pkg_index[:available_targets] << platform_id
         end
         pkg_index[:checksums][:built][platform_id] = built_sha256
       end  # if format == 'skill-bundle'
    end  # targets.each

   # Clean temporary build-time fields before writing indexes
   pkg_index.delete(:source_dir)
   pkg_index.delete(:source_sha256)

   index_data[:packages][pkgname] = pkg_index
end

# ─── Write build index ─────────────────────────────────────────────────────────

   begin
     BUILD_INDEX_PATH.parent.mkpath
     build_index_data = {
       version: 3.0,
       generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
       packages: index_data[:packages]
     }
     Ssot::Lib::Common.write_yaml_atomic(BUILD_INDEX_PATH, build_index_data)
     log "📝 Build index written: #{BUILD_INDEX_PATH}"
     puts "\n📝 Build index written: #{BUILD_INDEX_PATH}"
   rescue => e
     log_error "Failed to write build index: #{e.message}"
     exit 1
   end

   # ─── Write master index (ssot/index.yaml) ─────────────────────────────────────
   begin
     Ssot::Lib::Common.write_yaml_atomic(SSOT_ROOT.join('index.yaml'), index_data)
     log "📝 Master index written: #{SSOT_ROOT.join('index.yaml')}"
   rescue => e
     log_error "Failed to write master index: #{e.message}"
     exit 1
   end

# ─── Write derived JSON index ──────────────────────────────────────────────────

begin
  INDEX_JSON_PATH.write(JSON.pretty_generate(index_data))
  log "📝 JSON index written: #{INDEX_JSON_PATH}"
rescue => e
  log_error "Failed to write JSON index: #{e.message}"
end

puts "✅ Build complete. Run `ruby ssot/install.rb <platform>` to install packages."
