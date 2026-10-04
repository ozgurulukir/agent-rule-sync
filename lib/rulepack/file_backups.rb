# frozen_string_literal: true

# FileBackups — the one implementation of copy-aside backup choreography.
#
# Three flavors used to be hand-copied across Common.backup_file,
# InstalledIndex and BuildIndex (same mutex/counter, same copy, same
# best-effort cleanup rescue list). This module owns them all; anchors are
# passed in by the caller, and the session-journal anchor resolves through
# the scoped Paths — a relocated-Paths scope (tests, sandboxes) keeps its
# backups inside that scope instead of the repo tree (P-AR d).
#
#   numbered_backup / restore / cleanup   — single-file backups (the stores)
#   backup_file / cleanup_dead_sessions   — session-scoped journal backups
#                                           (install/uninstall transactions)

require 'fileutils'
require 'monitor'

module Rulepack
  module FileBackups
    # Created at load, not lazily: a racy ||= here would let two threads
    # synchronize on different monitors and mint duplicate backup names.
    @_mutex = Monitor.new

    module_function

    # Numbered copy of one file under anchor_dir. Returns the backup
    # Pathname, or nil when there is nothing to back up. The anchor is the
    # caller's decision (InstalledIndex backs up beside the index; BuildIndex
    # backs up at the scoped root because Build.run wipes build/).
    def numbered_backup(path, anchor_dir)
      path = Pathname.new(path)
      return nil unless path.exist?

      counter = next_counter
      backup_path = Pathname.new(anchor_dir).join("#{path.basename}.bak.#{counter}")
      FileUtils.cp(path, backup_path)
      backup_path
    end

    def restore(backup_path, path)
      return false unless backup_path&.exist?

      path = Pathname.new(path)
      path.parent.mkpath
      FileUtils.cp(backup_path, path)
      true
    end

    # Best-effort by design: a backup that cannot be deleted (AV lock, busy
    # file) must not fail the operation that already succeeded — but it is
    # logged, not swallowed.
    def cleanup(pattern, label: 'file')
      Pathname.glob(pattern.to_s).each do |backup|
        backup.delete
      rescue Errno::EACCES, Errno::EBUSY, Errno::EPERM, Errno::ENOENT => e
        Common.log_warn "Could not remove #{label} backup #{backup}: #{e.message}"
      end
      true
    end

    # Session-scoped journal backup of one file or directory, numbered within
    # the session. Anchored at the scoped Paths root.
    def backup_file(file_path)
      file_path = Pathname.new(file_path)
      return nil unless file_path.exist?

      counter = next_counter
      backup_dir = Common.paths.root.join('data', 'backups', "session-#{$$}")
      backup_dir.mkpath

      backup_path = backup_dir.join("#{counter}-#{file_path.basename}")
      if file_path.directory?
        FileUtils.cp_r(file_path, backup_path)
      else
        FileUtils.cp(file_path, backup_path)
      end
      backup_path
    end

    # Removes session backup directories whose owning process is gone.
    def cleanup_dead_sessions
      backup_root = Common.paths.root.join('data', 'backups')
      return unless backup_root.exist?

      backup_root.children.select(&:directory?).each do |d|
        next unless d.basename.to_s.start_with?('session-')
        pid = d.basename.to_s.sub('session-', '').to_i
        next if pid <= 0
        begin
          Process.kill(0, pid)
        rescue Errno::ESRCH
          FileUtils.rm_rf(d)
          Common.log_warn "Could not remove dead session backup dir #{d}" if d.exist?
        rescue Errno::EPERM, Errno::ENOENT
          # EPERM: the session's owner is alive but signal-protected — keep
          # the session. ENOENT: already gone. Either way, keep scanning.
          next
        end
      end
    end

    # ─── Internal ─────────────────────────────────────────────────────────────

    # One counter backs every backup flavor: each namespace (anchor dir and
    # name pattern) only needs names unique within itself, and a global
    # monotonic counter guarantees that.
    def next_counter
      @_mutex.synchronize { @_counter ||= 0; @_counter += 1 }
    end
  end
end
