# frozen_string_literal: true

require 'tmpdir'

module Rulepack
  module Common
    module_function

    def backup_tmpdir
      @_backup_tmpdir ||= Dir.mktmpdir('rulepack-backup-')
    end

    def backup_index(index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
      return nil unless index_path.exist?

      @_backup_mutex ||= Monitor.new
      @_backup_mutex.synchronize { @_backup_counter ||= 0; @_backup_counter += 1 }
      backup_path = Pathname.new(backup_tmpdir).join("index.bak.#{@_backup_counter}")
      FileUtils.cp(index_path, backup_path)
      backup_path
    end

    def restore_index(backup_path, index_path = RULEPACK_ROOT.join('data', 'index.yaml'))
      return false unless backup_path&.exist?

      FileUtils.cp(backup_path, index_path)
      true
    end

    def cleanup_backups(_index_path = nil)
      return true unless @_backup_tmpdir

      FileUtils.rm_rf(@_backup_tmpdir)
      @_backup_tmpdir = nil
      true
    end

    def backup_file(file_path)
      file_path = Pathname.new(file_path)
      return nil unless file_path.exist?

      @_backup_mutex ||= Monitor.new
      @_backup_mutex.synchronize { @_backup_counter ||= 0; @_backup_counter += 1 }
      backup_path = Pathname.new(backup_tmpdir).join("#{@_backup_counter}-#{file_path.basename}")
      if file_path.directory?
        FileUtils.cp_r(file_path, backup_path)
      else
        FileUtils.cp(file_path, backup_path)
      end
      backup_path
    end

    def cleanup_old_backups(_keep: 10)
      cleanup_backups
    end

    at_exit { cleanup_backups }
  end
end
