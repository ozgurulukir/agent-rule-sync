# frozen_string_literal: true

# File-level backup choreography for the install journal (session-scoped
# backups of individual files/directories before they are replaced).
#
# The INDEX backup/restore/cleanup lifecycle moved to InstalledIndex —
# that module owns data/index.yaml end to end. This file stays in Common
# because Transaction and the uninstall journal call it as Common.backup_file.

module Rulepack
  module Common
    module_function

    def backup_file(file_path)
      file_path = Pathname.new(file_path)
      return nil unless file_path.exist?

      @_backup_mutex ||= Monitor.new
      @_backup_mutex.synchronize { @_backup_counter ||= 0; @_backup_counter += 1 }

      backup_dir = RULEPACK_ROOT.join('data', 'backups', "session-#{$$}")
      backup_dir.mkpath

      backup_path = backup_dir.join("#{@_backup_counter}-#{file_path.basename}")
      if file_path.directory?
        FileUtils.cp_r(file_path, backup_path)
      else
        FileUtils.cp(file_path, backup_path)
      end
      backup_path
    end

    def cleanup_old_backups(_keep = nil)
      backup_root = RULEPACK_ROOT.join('data', 'backups')
      return unless backup_root.exist?

      backup_root.children.select(&:directory?).each do |d|
        next unless d.basename.to_s.start_with?('session-')
        pid = d.basename.to_s.sub('session-', '').to_i
        next if pid <= 0
        begin
          Process.kill(0, pid)
        rescue Errno::ESRCH
          FileUtils.rm_rf(d)
        end
      end
    end
  end
end
