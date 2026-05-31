# frozen_string_literal: true

module Rulepack
  module Common
    module_function

    def backup_index(index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
      return nil unless index_path.exist?

      @_backup_mutex ||= Monitor.new
      @_backup_mutex.synchronize { @_backup_counter ||= 0; @_backup_counter += 1 }
      backup_path = index_path.parent.join("#{index_path.basename}.bak.#{@_backup_counter}")
      FileUtils.cp(index_path, backup_path)
      backup_path
    end

    def restore_index(backup_path, index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
      return false unless backup_path&.exist?

      FileUtils.cp(backup_path, index_path)
      true
    end

    def cleanup_backups(index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
      pattern = index_path.parent.join("#{index_path.basename}.bak.*")
      Pathname.glob(pattern.to_s).each(&:delete) rescue nil
      cleanup_old_backups
      true
    end

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
