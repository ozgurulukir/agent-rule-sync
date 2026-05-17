# frozen_string_literal: true

require 'net/http'
require 'tempfile'
require 'yaml'
require 'pathname'
require 'digest'
require 'json'

module Rulepack
  module Config
    module_function

    def max_redirects
      Integer(ENV.fetch('RULEPACK_MAX_REDIRECTS', '3'))
    end

    def read_timeout
      Integer(ENV.fetch('RULEPACK_READ_TIMEOUT', '30'))
    end

    def cache_dir_name
      ENV.fetch('RULEPACK_CACHE_DIR', 'cache')
    end

    def git_clone_depth
      Integer(ENV.fetch('RULEPACK_GIT_DEPTH', '1'))
    end

    def log_level
      ENV.fetch('RULEPACK_LOG_LEVEL', 'info').to_sym
    end
  end

  module Common
    RULEPACK_ROOT = Pathname.new(__dir__).parent.parent.expand_path
    BUILD_DIR = RULEPACK_ROOT.join('build')
    BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')
    INDEX_YAML_PATH = RULEPACK_ROOT.join('data', 'index.yaml')
    INDEX_JSON_PATH = RULEPACK_ROOT.join('data', 'index.json')
    LOG_PATH = BUILD_DIR.join('install.log')

    @_default_log_file = LOG_PATH
    @_log_level = nil
    @_show_timing = false

    module_function

    # Overrideable log level (falls back to Rulepack::Config.log_level)
    def log_level
      @_log_level || Rulepack::Config.log_level
    end

    def log_level=(val)
      @_log_level = val
    end

    # Show timing flag for operation timing
    def show_timing
      @_show_timing
    end

    def show_timing=(val)
      @_show_timing = val
    end

    # ─── Basic IO Utilities ──────────────────────────────────────────────────────

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

    # Atomic write: write content to temp file then rename
    def atomic_write(path, content)
      path = Pathname.new(path)
      path.dirname.mkpath

      Tempfile.create(['rulepack', path.extname], path.dirname) do |tmp|
        tmp.write(content)
        tmp.flush
        FileUtils.mv(tmp.path, path.to_s)
      end
    end

    # Append to file atomically (create if doesn't exist)
    def atomic_append(path, content)
      path = Pathname.new(path)
      path.dirname.mkpath

      File.open(path.to_s, 'a') { |f| f.write(content) }
    end

    # Update content wrapped in markers (idempotent)
    def update_marked_content(path, pkgname, content)
      path = Pathname.new(path)
      start_marker = "<!-- rulepack:#{pkgname} start -->"
      end_marker = "<!-- rulepack:#{pkgname} end -->"

      new_block = "#{start_marker}\n#{content}\n#{end_marker}"

      if path.exist?
        existing = path.read
        if existing.include?(start_marker) && existing.include?(end_marker)
          # Replace existing block
          pattern = /#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}/m
          updated = existing.sub(pattern, new_block)
          atomic_write(path, updated)
          :updated
        else
          # Append new block (with separation if file not empty)
          sep = existing.empty? || existing.end_with?("\n\n") ? '' : (existing.end_with?("\n") ? "\n" : "\n\n")
          atomic_append(path, sep + new_block)
          :appended
        end
      else
        # Create new file
        atomic_write(path, new_block)
        :created
      end
    end

    # Remove content wrapped in markers (surgical excision)
    # Returns :removed if content was excised, :file_removed if file was empty and deleted, :not_found if markers missing
    def remove_marked_content(path, pkgname)
      path = Pathname.new(path)
      return :not_found unless path.exist?

      start_marker = "<!-- rulepack:#{pkgname} start -->"
      end_marker = "<!-- rulepack:#{pkgname} end -->"

      content = path.read
      unless content.include?(start_marker) && content.include?(end_marker)
        return :not_found
      end

      # Excise the block
      pattern = /#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}/m
      updated = content.gsub(pattern, '').gsub(/\n{3,}/, "\n\n").strip

      if updated.empty?
        path.unlink
        :file_removed
      else
        atomic_write(path, updated + "\n")
        :removed
      end
    end

    # Verify checksum of file, supporting marker-based content
    def verify_checksum(path, expected_checksum, pkgname)
      path = Pathname.new(path)
      return false unless path.exist?

      content = path.read
      start_marker = "<!-- rulepack:#{pkgname} start -->"
      end_marker = "<!-- rulepack:#{pkgname} end -->"

      if content.include?(start_marker) && content.include?(end_marker)
        pattern = /#{Regexp.escape(start_marker)}\n(.*?)\n#{Regexp.escape(end_marker)}/m
        if content =~ pattern
          extracted = $1
          return Digest::SHA256.hexdigest(extracted) == expected_checksum
        end
      end

      Digest::SHA256.hexdigest(content) == expected_checksum
    end

    # Expand user home directory in path (~/...)
    def expand_user_path(path)
      path.start_with?('~') ? File.expand_path(path) : path
    end

    # Remove YAML frontmatter (--- ... ---) from content
    def strip_frontmatter(content)
      content.sub(/\A---\s*\n.*?\n---\s*\n/m, '')
    end
  end
end

# ─── Load modular components ─────────────────────────────────────────────────────

require_relative 'logging'
require_relative 'cache'
require_relative 'backup'
require_relative 'version'
require_relative 'source'
require_relative 'transform'
require_relative 'validation'
require_relative 'platform'
require_relative 'uninstaller'
