# frozen_string_literal: true

require 'net/http'
require 'tempfile'
require 'yaml'
require 'pathname'
require 'digest'
require 'json'

module Ssot
  module Lib
    module Config
      module_function

      def max_redirects
        Integer(ENV.fetch('SSOT_MAX_REDIRECTS', '3'))
      end

      def read_timeout
        Integer(ENV.fetch('SSOT_READ_TIMEOUT', '30'))
      end

      def cache_dir_name
        ENV.fetch('SSOT_CACHE_DIR', 'cache')
      end

      def git_clone_depth
        Integer(ENV.fetch('SSOT_GIT_DEPTH', '1'))
      end

      def log_level
        ENV.fetch('SSOT_LOG_LEVEL', 'info').to_sym
      end
    end

    module Common
      SSOT_ROOT = Pathname.new(__dir__).expand_path.join('..').cleanpath
      BUILD_DIR = SSOT_ROOT.join('build')
      BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')
      INDEX_YAML_PATH = SSOT_ROOT.join('index.yaml')
      INDEX_JSON_PATH = SSOT_ROOT.join('index.json')
      LOG_PATH = BUILD_DIR.join('install.log')

      @_default_log_file = LOG_PATH

      module_function

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

        Tempfile.create(['ssot', path.extname], path.dirname) do |tmp|
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
require_relative 'uninstall'
