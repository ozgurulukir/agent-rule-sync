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

require_relative 'logging'
require_relative 'io'
require_relative 'platform'
require_relative 'source'
require_relative 'cache'
require_relative 'version'
require_relative 'validation'
require_relative 'transform'
require_relative 'backup'

  module Common
    RULEPACK_ROOT = Pathname.new(__dir__).parent.parent.expand_path
    BUILD_DIR = RULEPACK_ROOT.join('build')
    BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')
    INDEX_YAML_PATH = RULEPACK_ROOT.join('data', 'index.yaml')
    INDEX_JSON_PATH = RULEPACK_ROOT.join('data', 'index.json')
    LOG_PATH = BUILD_DIR.join('install.log')

    @_build_index_override = nil
    module_function

    # Overrideable build index path (for testing)
    def build_index_path
      @_build_index_override || BUILD_INDEX_PATH
    end

    def build_index_path=(val)
      @_build_index_override = val
    end

    # Overrideable index yaml path (for testing)
    def index_yaml_path
      @_index_yaml_override || INDEX_YAML_PATH
    end

    def index_yaml_path=(val)
      @_index_yaml_override = val
    end

    # Overrideable build dir (for testing)
    def build_dir
      @_build_dir_override || BUILD_DIR
    end

    def build_dir=(val)
      @_build_dir_override = val
    end

    # ─── Basic IO Utilities ──────────────────────────────────────────────────────
    # (Moved to lib/rulepack/io.rb — loaded above)

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

    # Validate and resolve target platforms against the installed index.
    #
    # @param target_arg [String, nil] "all" or comma-separated platform IDs
    # @param package_arg [String, nil] optional package name to filter
    # @param packages [Hash] index[:packages] — the installed-package index
    # @param registry [Hash] platform registry from load_platform_registry
    # @param exit_on_failure [Boolean] abort on error (CLI mode) vs raise
    # @param project_arg [String, nil] --project path for project-scoped platforms
    # @param enforce_project_scope [Boolean] call project_root_for during validation
    # @return [Array(Array<String>, String|nil)] [targets, target_package]
    def validate_targets_and_packages(target_arg, package_arg, packages, registry,
                                      exit_on_failure: false, project_arg: nil,
                                      enforce_project_scope: false)
      # ── Package existence check ──────────────────────────────────────────────────
      target_package = nil
      if package_arg
        unless packages.key?(package_arg) || packages.key?(package_arg.to_sym)
          msg = "Package '#{package_arg}' is not registered as installed in index."
          exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
        end
        target_package = packages.keys.find { |k| k.to_s == package_arg }.to_s
      end

      # ── Target arg required ──────────────────────────────────────────────────────
      unless target_arg
        msg = "Please specify target platform(s) with --target <platform> (or --target all)."
        exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
      end

      # ── Expand targets ───────────────────────────────────────────────────────────
      targets = []
      if target_arg.to_s.downcase == 'all'
        if target_package
          pkg_idx = packages[target_package.to_sym] || packages[target_package.to_s] || {}
          targets = (pkg_idx[:installed] || []).map { |i| i[:platform] }.uniq
        else
          platform_set = Set.new
          packages.each_value do |pkg|
            (pkg[:installed] || []).each { |i| platform_set << i[:platform] }
          end
          targets = platform_set.to_a
        end
      else
        targets = target_arg.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      return [targets, target_package] if targets.empty?

      # ── Validate targets against registry ────────────────────────────────────────
      targets.each do |p|
        cfg = registry[p.to_sym] || registry[p.to_s]
        unless cfg
          msg = "Unknown target platform '#{p}'."
          exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
        end
        project_root_for(cfg, project_arg) if enforce_project_scope
      end

      [targets, target_package]
    end

    # ─── Uninstall Helpers (thin wrappers around Uninstaller) ────────────────────
    # Maintains backward compatibility: Rulepack::Common.uninstall_packages(...) still works

    def uninstall_packages(index, platform_id, dry_run: false, project_root: nil,
                           specific_packages: nil, ctx: nil)
      Rulepack::Uninstaller.uninstall_packages(index, platform_id,
                                                dry_run: dry_run,
                                                project_root: project_root,
                                                specific_packages: specific_packages,
                                                ctx: ctx)
    end

    def migrate_installed_records(pkg_index)
      Rulepack::Uninstaller.migrate_installed_records(pkg_index)
    end

    # ─── Delegation to Logging ──────────────────────────────────────────────────
    # Maintains backward compatibility: Rulepack::Common.log(...) still works

    Rulepack::Logging.public_methods(false).each do |m|
      define_singleton_method(m, &Rulepack::Logging.method(m))
    end

    # ─── Delegation to IO ─────────────────────────────────────────────────────────
    # Maintains backward compatibility: Rulepack::Common.load_yaml(...) etc. still works

    Rulepack::IO.public_methods(false).each do |m|
      define_singleton_method(m, &Rulepack::IO.method(m))
    end

  end

# Load uninstaller after Common is fully defined to avoid circular dependency
require_relative 'uninstaller'
end
