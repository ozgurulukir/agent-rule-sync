# frozen_string_literal: true

require 'fileutils'

module Rulepack
  module Transaction
    module_function

    # Returns the restore outcome so callers can surface it in their Result:
    # { index_restored: true|false, backup: String|nil }. A failing restore
    # is caught and reported — it must never raise out of a rollback.
    def transaction_rollback(error, backup_path, journal = nil)
      restored = false
      if backup_path
        begin
          restored = Rulepack::InstalledIndex.restore(backup_path)
          Rulepack::Common.log_error "Transaction failed (#{error.message}). Index restored from backup: #{backup_path.basename}" if restored
        rescue StandardError => e
          Rulepack::Common.log_error "Index restore from #{backup_path} FAILED: #{e.message}"
        end
      end
      unless restored
        reason = backup_path ? 'restore failed' : 'no backup available'
        Rulepack::Common.log_error "Transaction failed (#{error.message}). Index NOT restored (#{reason})."
      end
      rollback_journal(journal) if journal
      { index_restored: restored, backup: backup_path&.to_s }
    end

    def record_journal(ctx, entry)
      return unless ctx&.respond_to?(:journal) && ctx.journal
      ctx.journal << entry
    end

    def rollback_journal(journal)
      return unless journal && !journal.empty?
      Rulepack::Common.log "  🔄 Rolling back #{journal.size} filesystem change(s)..."

      # Revert changes in REVERSE order of application
      journal.reverse_each do |entry|
        path = entry[:path]
        action = entry[:action]
        backup = entry[:backup]

        case action
        when :create_file
          if path.exist? || path.symlink?
            path.delete
            Rulepack::Common.log "    ✓ Deleted created file: #{path}"
          end
        when :create_dir
          if path.exist? && path.directory?
            FileUtils.rm_rf(path)
            Rulepack::Common.log "    ✓ Deleted created directory: #{path}"
          end
        when :replace_file, :modify_file
          if backup && backup.exist?
            path.delete if path.exist? || path.symlink?
            if backup.directory?
              FileUtils.cp_r(backup, path)
            else
              FileUtils.cp(backup, path)
            end
            Rulepack::Common.log "    ✓ Restored file: #{path} (from backup)"
          end
        when :replace_dir
          if backup && backup.exist?
            FileUtils.rm_rf(path) if path.exist?
            FileUtils.cp_r(backup, path)
            Rulepack::Common.log "    ✓ Restored directory: #{path} (from backup)"
          end
        end
      end
    end
  end
end
