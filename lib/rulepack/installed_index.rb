# frozen_string_literal: true

# InstalledIndex — the single owner of data/index.yaml.
#
# Owns: existence, load (ALWAYS schema- and record-migrated), the fresh-index
# literal, the :generated stamp, atomic save, and the index backup/restore/
# cleanup choreography. Load is never memoized (Query and install_all mutate
# the returned hash in place); the store is silent by design — narration
# belongs to callers.
#
# Division of labor: this module owns the file lifecycle, InstalledRecord
# owns the record schema, InstalledState owns disk verdicts. Callers mutate
# the loaded hash in place (raw hashes deliberately — this is not the
# models-everywhere refactor) and hand it back to #save.

require 'fileutils'
require_relative 'common'
require_relative 'schema_migration'
require_relative 'models/installed_record'

module Rulepack
  module InstalledIndex
    module_function

    def exist?
      Common.paths.index_yaml_path.exist?
    end

    # Strict load. Raises Rulepack::IndexNotFound when the file is missing.
    # Guarantees migrated data: SchemaMigration plus legacy record
    # normalization run on EVERY load, so no caller can forget them.
    def load
      path = Common.paths.index_yaml_path
      unless path.exist?
        raise Rulepack::IndexNotFound,
              "Installed index not found at #{path}. Nothing is installed."
      end
      migrate(Rulepack::IO.load_yaml(path) || {})
    end

    # Lenient load: a missing index is a fresh install, not an error.
    def load_or_fresh
      path = Common.paths.index_yaml_path
      path.exist? ? migrate(Rulepack::IO.load_yaml(path) || {}) : fresh
    end

    # Stamps :generated and writes atomically. Backup is a separate verb on
    # purpose: install/uninstall must back up BEFORE mutating and save AFTER,
    # which a save(backup: true) flag would get backwards.
    def save(index)
      index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      Rulepack::IO.write_yaml_atomic(Common.paths.index_yaml_path, index)
      index
    end

    # Returns the backup Pathname, or nil when there is nothing to back up.
    def backup
      path = Common.paths.index_yaml_path
      return nil unless path.exist?

      @_backup_mutex ||= Monitor.new
      @_backup_mutex.synchronize { @_backup_counter ||= 0; @_backup_counter += 1 }
      backup_path = path.parent.join("#{path.basename}.bak.#{@_backup_counter}")
      FileUtils.cp(path, backup_path)
      backup_path
    end

    def restore(backup_path)
      path = Common.paths.index_yaml_path
      return false unless backup_path&.exist?

      FileUtils.cp(backup_path, path)
      true
    end

    def cleanup_backups
      path = Common.paths.index_yaml_path
      pattern = path.parent.join("#{path.basename}.bak.*")
      Pathname.glob(pattern.to_s).each(&:delete) rescue nil
      Common.cleanup_old_backups
      true
    end

    # ─── Internal ───────────────────────────────────────────────────────────────

    def migrate(index)
      index[:packages] ||= {}
      SchemaMigration.migrate!(index)
      index[:packages].each_value { |pkg| InstalledRecord.migrate_legacy!(pkg) }
      index
    end

    def fresh
      { version: SchemaMigration::CURRENT_VERSION, packages: {} }
    end

    private_class_method :migrate, :fresh
  end
end
