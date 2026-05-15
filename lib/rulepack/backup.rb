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
        return false unless backup_path && backup_path.exist?
        FileUtils.cp(backup_path, index_path)
        backup_path.delete
        true
      end

      # Remove all index backup files (cleanup helper).
      def cleanup_backups(index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
        pattern = index_path.parent.join("#{index_path.basename}.bak.*")
        Pathname.glob(pattern.to_s).each { |f| f.delete rescue nil }
      end
    end
end
