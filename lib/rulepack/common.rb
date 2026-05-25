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

    # Expand user home directory in path (~/...)
    def expand_user_path(path)
      path.start_with?('~') ? File.expand_path(path) : path
    end

    # Remove YAML frontmatter (--- ... ---) from content
    def strip_frontmatter(content)
      content.sub(/\A---\s*\n.*?\n---\s*\n/m, '')
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

    # ─── Delegation to Validation ─────────────────────────────────────────────────
    # Maintains backward compatibility: Rulepack::Common.verify_checksum(...) etc. still works

    Rulepack::Validation.public_methods(false).each do |m|
      define_singleton_method(m, &Rulepack::Validation.method(m))
    end

  end

# Load uninstaller after Common is fully defined to avoid circular dependency
require_relative 'uninstaller'
end
