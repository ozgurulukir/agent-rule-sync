# frozen_string_literal: true

require 'net/http'
require 'tempfile'
require 'yaml'
require 'pathname'
require 'digest'
require 'json'

module Rulepack
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

  module Common
    RULEPACK_ROOT = Pathname.new(__dir__).parent.parent.expand_path
    BUILD_DIR = RULEPACK_ROOT.join('build')
    BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')
    INDEX_YAML_PATH = RULEPACK_ROOT.join('data', 'index.yaml')
    INDEX_JSON_PATH = RULEPACK_ROOT.join('data', 'index.json')
    LOG_PATH = BUILD_DIR.join('install.log')

    @_build_index_override = nil
    module_function

    # Overrideable paths (test seam)
    def build_index_path
      @_build_index_override || BUILD_INDEX_PATH
    end

    def build_index_path=(val)
      @_build_index_override = val
    end

    def index_yaml_path
      @_index_yaml_override || INDEX_YAML_PATH
    end

    def index_yaml_path=(val)
      @_index_yaml_override = val
    end

    def build_dir
      @_build_dir_override || BUILD_DIR
    end

    def build_dir=(val)
      @_build_dir_override = val
    end

    # Facade — delegates to submodules
    Logging.methods(false).each { |m| define_singleton_method(m, &Logging.method(m)) }
    IO.methods(false).each { |m| define_singleton_method(m, &IO.method(m)) }
    Validation.methods(false).each { |m| define_singleton_method(m, &Validation.method(m)) }
    Path.methods(false).each { |m| define_singleton_method(m, &Path.method(m)) }
    InstallHelpers.methods(false).each { |m| define_singleton_method(m, &InstallHelpers.method(m)) }
  end
end

# Load uninstaller after Common is fully defined to avoid circular dependency
require_relative 'uninstaller'
