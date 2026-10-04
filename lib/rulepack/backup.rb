# frozen_string_literal: true

# Session-journal backup entry points on Common. Transaction and the
# uninstall journal call these as Common.backup_file; the implementation
# lives in FileBackups and anchors at the scoped Paths root (P-AR d) — a
# relocated-Paths scope keeps its backups inside that scope.

module Rulepack
  module Common
    module_function

    def backup_file(file_path)
      FileBackups.backup_file(file_path)
    end

    def cleanup_old_backups(_keep = nil)
      FileBackups.cleanup_dead_sessions
    end
  end
end
