# frozen_string_literal: true

require 'fileutils'
require_relative 'transaction'

module Rulepack
  module InstallHandlers
    module_function

    def perform_file_install(built_path, install_path, content, content_sha256, install_type, platform_cfg, output,
                             pkgname, ctx)
      case install_type
      when 'symlink'
        if ctx.dry_run
          Rulepack::Common.log "    [DRY-RUN] Would symlink: #{built_path} → #{install_path}" unless ctx.quiet
        else
          do_symlink(built_path, install_path, pkgname, ctx)
        end
      when 'copy'
        if ctx.dry_run
          Rulepack::Common.log "    [DRY-RUN] Would copy: #{built_path} → #{install_path}" unless ctx.quiet
        else
          do_copy(built_path, install_path, content_sha256, pkgname, ctx)
        end
      when 'inject', 'append'
        if ctx.dry_run
          Rulepack::Common.log "    [DRY-RUN] Would #{install_type}: #{output} → #{install_path}" unless ctx.quiet
        else
          do_inject_append(install_path, content, install_type, platform_cfg, output, pkgname, ctx)
        end
      else
        Rulepack::Common.log_error "Unknown install type: #{install_type}. Valid types: symlink, copy, inject, append."
      end
    end

    def do_symlink(built_path, install_path, pkgname, ctx)
      strategy = ctx.collision_strategy
      if install_path.symlink?
        if install_path.readlink == built_path.relative_path_from(install_path.parent)
          Rulepack::Common.log '    ↺ Already symlinked'
          return
        end
      end

      if install_path.exist? || install_path.symlink?
        case strategy
        when 'overwrite', 'append' # append doesn't make sense for symlinks, treat as overwrite
          backup_path = Rulepack::Common.backup_file(install_path) if install_path.file? && !install_path.symlink?
          Rulepack::Transaction.record_journal(ctx, { action: :replace_file, path: install_path, backup: backup_path })
          FileUtils.rm_f(install_path)
          target_rel = built_path.realpath.relative_path_from(install_path.parent.realpath)
          FileUtils.ln_s(target_rel, install_path)
          Rulepack::Common.log "    ✓ Replaced symlink (strategy: #{strategy})"
        when 'ignore'
          Rulepack::Common.log "    ⚠ Collision: #{install_path} exists, skipping"
        else # stop
          Rulepack::Common.log_error "Collision detected: #{install_path} exists. Use --on-collision to proceed."
          raise "Collision at #{install_path}"
        end
      else
        Rulepack::Transaction.record_journal(ctx, { action: :create_file, path: install_path })
        target_rel = built_path.realpath.relative_path_from(install_path.parent.realpath)
        FileUtils.ln_s(target_rel, install_path)
        Rulepack::Common.log '    ✓ Symlinked'
      end
    rescue StandardError => e
      Rulepack::Common.log_error "Symlink failed: #{e.message}"
      raise e
    end

    def do_copy(built_path, install_path, content_sha256, pkgname, ctx)
      strategy = ctx.collision_strategy
      if install_path.exist?
        return Rulepack::Common.log '    ↺ Already up-to-date' if Rulepack::Common.verify_checksum(install_path, content_sha256, pkgname)

        case strategy
        when 'append'
          backup_path = Rulepack::Common.backup_file(install_path)
          Rulepack::Transaction.record_journal(ctx, { action: :modify_file, path: install_path, backup: backup_path })
          result = Rulepack::Common.update_marked_content(install_path, pkgname, built_path.read)
          Rulepack::Common.log "    ✓ #{result.capitalize} (marker-based append with backup)"
        when 'overwrite'
          backup_path = Rulepack::Common.backup_file(install_path)
          Rulepack::Transaction.record_journal(ctx, { action: :replace_file, path: install_path, backup: backup_path })
          FileUtils.cp(built_path, install_path)
          Rulepack::Common.log '    ✓ Updated (with backup)'
        when 'ignore'
          Rulepack::Common.log "    ⚠ Collision: #{install_path} exists, skipping"
        else # stop
          Rulepack::Common.log_error "Collision detected: #{install_path} exists. Use --on-collision to proceed."
          raise "Collision at #{install_path}"
        end
      else
        Rulepack::Transaction.record_journal(ctx, { action: :create_file, path: install_path })
        FileUtils.cp(built_path, install_path)
        Rulepack::Common.log '    ✓ Copied'
      end
    rescue StandardError => e
      Rulepack::Common.log_error "Copy failed: #{e.message}"
      raise e
    end

    def do_inject_append(install_path, content, install_type, platform_cfg, output, pkgname, ctx)
      strategy = ctx.collision_strategy
      if install_type == 'append' || strategy == 'append'
        if content_already_present?(install_path, content)
          Rulepack::Common.log '    ↺ Already present (skipping duplicate append)'
        else
          backup_path = nil
          if install_path.exist?
            backup_path = Rulepack::Common.backup_file(install_path)
            Rulepack::Transaction.record_journal(ctx, { action: :modify_file, path: install_path, backup: backup_path })
          else
            Rulepack::Transaction.record_journal(ctx, { action: :create_file, path: install_path })
          end
          result = Rulepack::Common.update_marked_content(install_path, pkgname, content)
          Rulepack::Common.log "    ✓ #{result.capitalize} (with backup)"
        end
      elsif install_type == 'inject'
        directive = platform_cfg[:rule_install]&.[](:directive) || '@import'
        import_line = "#{directive} \"#{output}\"\n"
        if install_path.exist?
          existing = install_path.read
          if existing.start_with?(import_line)
            Rulepack::Common.log '    ↺ Already injected'
          else
            case strategy
            when 'overwrite', 'append'
              backup_path = Rulepack::Common.backup_file(install_path)
              Rulepack::Transaction.record_journal(ctx, { action: :modify_file, path: install_path, backup: backup_path })
              Rulepack::Common.atomic_write(install_path, import_line + existing)
              Rulepack::Common.log "    ✓ Injected (with backup, strategy: #{strategy})"
            when 'ignore'
              Rulepack::Common.log "    ⚠ Collision: #{install_path} exists, skipping"
            else # stop
              Rulepack::Common.log_error "Collision detected: #{install_path} exists. Use --on-collision to proceed."
              raise "Collision at #{install_path}"
            end
          end
        else
          Rulepack::Transaction.record_journal(ctx, { action: :create_file, path: install_path })
          Rulepack::Common.atomic_write(install_path, import_line)
          Rulepack::Common.log '    ✓ Injected (created config)'
        end
      end
    rescue StandardError => e
      Rulepack::Common.log_error "Install failed (#{install_type}): #{e.message}"
      raise e
    end

    def content_already_present?(path, content)
      return false unless path.exist?

      path.read.include?(content)
    end
  end
end
