# frozen_string_literal: true

# BuildIndex — the single owner of build/index.yaml.
#
# Read-mostly: one writer (Build via BuildWriter#write_build_index). Bump
# backs the index up before a post-apply rebuild and restores it if the
# rebuild fails — Build.run wipes build/ and writes the new index only at
# the end, so a failed rebuild would otherwise leave no index at all.
# Strict reads raise the typed Rulepack::BuildIndexNotFound ("run build
# first"); soft reads use #load_or_nil. Like InstalledIndex, load is never
# memoized — Query mutates the returned hash — and the store is silent.

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
    # missing and Rulepack::BuildIndexCorrupt when it holds no YAML mapping
    # or is unparseable.
    def load
      path = Common.paths.build_index_path
      unless path.exist?
        raise Rulepack::BuildIndexNotFound,
              "Build index not found at #{path}. Run `rulepack build` first."
      end
      data = begin
        Rulepack::IO.load_yaml(path)
      rescue Psych::SyntaxError => e
        raise Rulepack::BuildIndexCorrupt,
              "Build index at #{path} is not valid YAML (#{e.message}). Run `rulepack build` to regenerate it."
      end
      if data.nil? || !data.is_a?(Hash)
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

    # Removes the index file. Idempotent (rm_f no-ops on a missing file).
    # The safe-rebuild path (Bump) uses backup/restore instead.
    def remove
      FileUtils.rm_f(Common.paths.build_index_path)
      true
    end

    # Returns the backup Pathname, or nil when there is nothing to back up.
    # Stored under the scoped root, NOT next to the index: Build.run wipes
    # the whole build/ directory at the start of a rebuild, which would
    # destroy a sibling backup before it could ever be restored.
    def backup
      path = Common.paths.build_index_path
      return nil unless path.exist?

      @_backup_mutex ||= Monitor.new
      @_backup_mutex.synchronize { @_backup_counter ||= 0; @_backup_counter += 1 }
      backup_path = Common.paths.root.join("#{path.basename}.bak.#{@_backup_counter}")
      FileUtils.cp(path, backup_path)
      backup_path
    end

    def restore(backup_path)
      path = Common.paths.build_index_path
      return false unless backup_path&.exist?

      path.parent.mkpath
      FileUtils.cp(backup_path, path)
      true
    end

    # Best-effort by design: a backup that cannot be deleted (AV lock, busy
    # file) must not fail the rebuild that already succeeded — but it is
    # logged, not swallowed.
    def cleanup_backups
      path = Common.paths.build_index_path
      pattern = Common.paths.root.join("#{path.basename}.bak.*")
      Pathname.glob(pattern.to_s).each do |backup|
        backup.delete
      rescue Errno::EACCES, Errno::EBUSY, Errno::EPERM, Errno::ENOENT => e
        Common.log_warn "Could not remove build-index backup #{backup}: #{e.message}"
      end
      true
    end
  end
end
