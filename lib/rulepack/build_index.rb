# frozen_string_literal: true

# BuildIndex — the single owner of build/index.yaml.
#
# Read-mostly: one writer (Build via BuildWriter#write_build_index), one
# remover (Bump before a rebuild). Strict reads raise the typed
# Rulepack::BuildIndexNotFound ("run build first"); soft reads use
# #load_or_nil. Like InstalledIndex, load is never memoized — Query mutates
# the returned hash — and the store is silent.

require 'fileutils'
require 'monitor'
require_relative 'common'
require_relative 'schema_migration'

module Rulepack
  module BuildIndex
    module_function

    def exist?
      Common.paths.build_index_path.exist?
    end

    # Strict load. Raises Rulepack::BuildIndexNotFound when the file is
    # missing and Rulepack::BuildIndexCorrupt when it holds no YAML mapping.
    def load
      path = Common.paths.build_index_path
      unless path.exist?
        raise Rulepack::BuildIndexNotFound,
              "Build index not found at #{path}. Run `rulepack build` first."
      end
      data = Rulepack::IO.load_yaml(path)
      if data.nil?
        raise Rulepack::BuildIndexCorrupt,
              "Build index at #{path} is empty or not a YAML mapping. Run `rulepack build` to regenerate it."
      end
      data.tap { |idx| idx[:packages] ||= {} }
    end

    # Soft read for optional consumers (Bump.cached_commit_for, Query).
    def load_or_nil
      exist? ? load : nil
    end

    # The single writer. Owns the build-index envelope: callers pass the
    # package map, the store adds version and the :generated stamp.
    def write(index_data)
      payload = {
        version: SchemaMigration::CURRENT_VERSION,
        generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        packages: index_data[:packages]
      }
      Rulepack::IO.write_yaml_atomic(Common.paths.build_index_path, payload)
      payload
    end

    # Used by bump before a rebuild; idempotent (rm_f no-ops on a missing file).
    def remove
      FileUtils.rm_f(Common.paths.build_index_path)
      true
    end
  end
end
