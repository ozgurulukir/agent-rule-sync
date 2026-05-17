# frozen_string_literal: true

module Rulepack
  module Common
    module_function

    # ─── Index Backup / Restore (L4.3 Transaction Rollback) ─────────────────

    # Create a backup of the current index file.
    # Returns the backup Pathname.
    def backup_index(index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
      return nil unless index_path.exist?

      # Use monotonic counter to ensure unique backup filenames even when called rapidly
      @_backup_counter ||= 0
      @_backup_counter += 1
      ts = Time.now.utc.strftime('%Y%m%dT%H%M%S')
      backup_path = index_path.parent.join("#{index_path.basename}.bak.#{ts}.#{@_backup_counter}")
      FileUtils.cp(index_path, backup_path)
      backup_path
    end

    # Restore index from backup, removing the backup afterwards.
    # Returns true if restored, false if backup not found.
    def restore_index(backup_path, index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
      return false unless backup_path&.exist?

      FileUtils.cp(backup_path, index_path)
      backup_path.delete
      true
    end

    # Remove all index backup files (cleanup helper).
    def cleanup_backups(index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
      pattern = index_path.parent.join("#{index_path.basename}.bak.*")
      Pathname.glob(pattern.to_s).each(&:delete) rescue nil
      cleanup_old_backups
      true
    end

    # Create a backup of a generic file or directory.
    def backup_file(file_path)
      file_path = Pathname.new(file_path)
      return nil unless file_path.exist?

      ts = Time.now.utc.strftime('%Y%m%dT%H%M%S')
      backup_dir = RULEPACK_ROOT.join('data', 'backups', 'files', ts)
      backup_dir.mkpath

      backup_path = backup_dir.join(file_path.basename)
      if file_path.directory?
        FileUtils.cp_r(file_path, backup_path)
      else
        FileUtils.cp(file_path, backup_path)
      end
      backup_path
    end

    # Cleanup old file backups (keep only most recent N directories)
    def cleanup_old_backups(keep: 10)
      backup_root = RULEPACK_ROOT.join('data', 'backups', 'files')
      return unless backup_root.exist?

      dirs = backup_root.children.select(&:directory?).sort_by(&:mtime).reverse
      if dirs.size > keep
        dirs[keep..-1].each { |d| FileUtils.rm_rf(d) }
      end
    end
  end
end
