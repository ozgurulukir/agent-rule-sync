# frozen_string_literal: true

require 'net/http'
require 'tempfile'
require 'yaml'
require 'pathname'
require 'digest'
require 'json'

module Rulepack
  require_relative 'errors'
  require_relative 'paths'
  require_relative 'platforms'
  require_relative 'ui'
  require_relative 'config'
  require_relative 'logging'
  require_relative 'io'
  require_relative 'path_utils'
  require_relative 'validation'
  require_relative 'install_helpers'
  require_relative 'platform'
  require_relative 'source'
  require_relative 'cache'
  require_relative 'version'
  require_relative 'transform'
  require_relative 'backup'
  require_relative 'schema_migration'
  require_relative 'result'
  require_relative 'reporter'
  require_relative 'platform_scanner'
  require_relative 'processor_loader'
  require_relative 'package_resolver'

  # Explicit composition root.
  #
  # Three jobs, no metaprogramming:
  #   1. Owns RULEPACK_ROOT and the repo-level path constants.
  #   2. Scoped contexts for Paths and UI: backend entry points may accept
  #      `paths:` / `ui:` keywords and open a scope via with_paths / with_ui;
  #      readers resolve the innermost scope, defaulting to the process-wide
  #      values. This replaces the old global override setters and the
  #      ENV['RULEPACK_TEST'] branches.
  #   3. Explicit one-line re-exports of the submodule APIs that callers have
  #      not migrated off Common yet. Note: methods defined by files that
  #      reopen Common (source.rb, cache.rb, version.rb, platform.rb, …) are
  #      native here and need no re-export.
  module Common
    RULEPACK_ROOT = Pathname.new(__dir__).parent.parent.expand_path
    BUILD_DIR = RULEPACK_ROOT.join('build')
    BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')
    INDEX_YAML_PATH = RULEPACK_ROOT.join('data', 'index.yaml')
    LOG_PATH = BUILD_DIR.join('install.log')

    DEFAULT_PATHS = Paths.for_root(RULEPACK_ROOT)

    module_function

    # ─── Scoped contexts (strangler scaffold) ─────────────────────────────────
    #
    # Only entry points may open a scope. Deep layers read through `paths` /
    # `ui` so a scope opened at the top reaches them — the same reach the old
    # process-global overrides had, but thread-scoped and auto-restored.

    def paths
      Thread.current[:rulepack_paths] || DEFAULT_PATHS
    end

    # Opens a paths scope. Pass a Rulepack::Paths instance (entry points) or
    # partial overrides merged onto the current scope (tests):
    #   Common.with_paths(sandbox_paths) { ... }
    #   Common.with_paths(build_index_path: tmp.join('index.yaml')) { ... }
    def with_paths(paths = nil, **overrides)
      scoped = paths || self.paths.merge(**overrides)
      previous = Thread.current[:rulepack_paths]
      Thread.current[:rulepack_paths] = scoped
      yield
    ensure
      Thread.current[:rulepack_paths] = previous
    end

    def ui
      Thread.current[:rulepack_ui] || UI.default
    end

    def with_ui(ui)
      previous = Thread.current[:rulepack_ui]
      Thread.current[:rulepack_ui] = ui
      yield
    ensure
      Thread.current[:rulepack_ui] = previous
    end

    # ─── Path readers (resolve through the scoped Paths) ──────────────────────

    def build_dir
      paths.build_dir
    end

    def build_index_path
      paths.build_index_path
    end

    def index_yaml_path
      paths.index_yaml_path
    end

    # ─── Platforms delegators ─────────────────────────────────────────────────

    def load_platform_registry
      # Scoped root, not the repo constant — sandboxes that relocate paths
      # via with_paths get their own registry (memoized per root in
      # Platforms.load). A scoped root without registry files inherits the
      # repo registry — the sandbox opted into relocation, not isolation.
      root = paths.root
      if root.join('data', 'registry', 'platforms.yaml').exist?
        Platforms.load(root)
      else
        Platforms.load(RULEPACK_ROOT)
      end
    end

    def clear_platform_registry_cache!
      Platforms.clear_cache!
    end

    def validate_platform_config(*args, **kwargs, &block)
      Platforms.validate_platform_config(*args, **kwargs, &block)
    end

    def validate_format_profile(*args, **kwargs, &block)
      Platforms.validate_format_profile(*args, **kwargs, &block)
    end

    # ─── UI delegators (resolve through the scoped UI) ────────────────────────

    def spin(msg, &block)
      ui.spin(msg, &block)
    end

    def interactive_collision_prompt(install_path)
      ui.collision_prompt(install_path)
    end

    # ─── Logging re-exports ───────────────────────────────────────────────────

    def log(*args, **kwargs, &block)
      Logging.log(*args, **kwargs, &block)
    end

    def log_warn(*args, **kwargs, &block)
      Logging.log_warn(*args, **kwargs, &block)
    end

    def log_error(*args, **kwargs, &block)
      Logging.log_error(*args, **kwargs, &block)
    end

    def log_debug(*args, **kwargs, &block)
      Logging.log_debug(*args, **kwargs, &block)
    end

    def time(*args, **kwargs, &block)
      Logging.time(*args, **kwargs, &block)
    end

    # format_version is a native Common method (defined in version.rb, which
    # reopens this module) — no re-export needed.

    # ─── IO re-exports ────────────────────────────────────────────────────────

    def read_text(*args, **kwargs, &block)
      IO.read_text(*args, **kwargs, &block)
    end

    def read_binary(*args, **kwargs, &block)
      IO.read_binary(*args, **kwargs, &block)
    end

    def load_yaml(*args, **kwargs, &block)
      IO.load_yaml(*args, **kwargs, &block)
    end

    def write_yaml_atomic(*args, **kwargs, &block)
      IO.write_yaml_atomic(*args, **kwargs, &block)
    end

    def atomic_write(*args, **kwargs, &block)
      IO.atomic_write(*args, **kwargs, &block)
    end

    def safe_append(*args, **kwargs, &block)
      IO.safe_append(*args, **kwargs, &block)
    end

    def update_marked_content(*args, **kwargs, &block)
      IO.update_marked_content(*args, **kwargs, &block)
    end

    def remove_marked_content(*args, **kwargs, &block)
      IO.remove_marked_content(*args, **kwargs, &block)
    end

    def deep_merge(*args, **kwargs, &block)
      IO.deep_merge(*args, **kwargs, &block)
    end

    # ─── Path re-exports ──────────────────────────────────────────────────────

    def expand_user_path(*args, **kwargs, &block)
      Path.expand_user_path(*args, **kwargs, &block)
    end

    def strip_frontmatter(*args, **kwargs, &block)
      Path.strip_frontmatter(*args, **kwargs, &block)
    end

    # ─── Validation re-exports ────────────────────────────────────────────────

    def load_pkgbuild(*args, **kwargs, &block)
      Validation.load_pkgbuild(*args, **kwargs, &block)
    end

    def validate_pkgbuild(*args, **kwargs, &block)
      Validation.validate_pkgbuild(*args, **kwargs, &block)
    end

    def validate_output_filename(*args, **kwargs, &block)
      Validation.validate_output_filename(*args, **kwargs, &block)
    end

    def validate_target_dir(*args, **kwargs, &block)
      Validation.validate_target_dir(*args, **kwargs, &block)
    end

    def validate_targets_and_packages(*args, **kwargs, &block)
      Validation.validate_targets_and_packages(*args, **kwargs, &block)
    end

    def verify_checksum(*args, **kwargs, &block)
      Validation.verify_checksum(*args, **kwargs, &block)
    end

    # ─── InstallHelpers re-exports ────────────────────────────────────────────

    def uninstall_packages(*args, **kwargs, &block)
      InstallHelpers.uninstall_packages(*args, **kwargs, &block)
    end

    def migrate_installed_records(*args, **kwargs, &block)
      InstallHelpers.migrate_installed_records(*args, **kwargs, &block)
    end
  end
end

# Load uninstaller after Common is fully defined to avoid circular dependency
require_relative 'uninstaller'
