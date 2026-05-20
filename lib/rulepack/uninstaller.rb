# frozen_string_literal: true
 
 module Rulepack
   module Common
     module_function
 
     # Uninstall packages from a platform, modifying index in-place.
     # Returns array of uninstalled package names.
     # Does NOT write index to disk.
     def uninstall_packages(index, platform_id, dry_run: false, project_root: nil,
                            specific_packages: nil, ctx: nil)
       platform_cfg = platform_config(platform_id, load_platform_registry)
       base_path = project_root || Pathname.new(expand_user_path(platform_cfg[:base_path]))
       build_index = load_yaml(build_index_path)
       pkg_names = resolve_uninstall_targets(index, platform_id, specific_packages)
 
       uninstalled = []
       pkg_names.each do |pkgname|
         result = uninstall_single_package(pkgname, index, build_index, platform_id,
                                           platform_cfg, base_path, dry_run, ctx)
         uninstalled << result if result
       end
       uninstalled.uniq
     end
 
     def resolve_uninstall_targets(index, platform_id, specific_packages)
       return specific_packages if specific_packages
 
       index[:packages].select do |_name, pkg|
         pkg[:installed].is_a?(Array) && pkg[:installed].any? { |i| i[:platform] == platform_id }
       end.keys
     end
 
     def uninstall_single_package(pkgname, index, build_index, platform_id,
                                  platform_cfg, base_path, dry_run, ctx = nil)
       pkg_index = index[:packages][pkgname]
       return nil unless pkg_index
 
       records = pkg_index[:installed] || []
       platform_records = records.select { |r| r[:platform] == platform_id }
       return nil if platform_records.empty?
 
       pkgdata = build_index[:packages][pkgname]
       unless pkgdata
         log_error "Package not found in build index: #{pkgname}"
         return nil
       end
       targets = pkgdata[:targets]&.select { |t| t[:platform] == platform_id } || []
       target_by_output = targets.to_h { |t| [t[:output], t] }
 
       platform_records.each do |rec|
         uninstall_record(rec, target_by_output, platform_cfg, base_path, pkgname, dry_run, ctx)
         records.delete(rec) unless dry_run
       end
       pkgname
     end
 
     def uninstall_record(rec, target_by_output, platform_cfg, base_path, pkgname, dry_run, ctx = nil)
       output = rec[:output]
       target = target_by_output[output]
       unless target
         log_warn "  ⚠ No target found for output '#{output}' in #{pkgname}, skipping uninstall"
         return
       end
       if dry_run
         log "    [DRY-RUN] Would remove: #{output}"
         return
       end
       remove_target_file(target, platform_cfg, base_path, pkgname, ctx)
     end
 
     def remove_target_file(target, platform_cfg, base_path, pkgname, ctx = nil)
       install_cfg = target[:install] || {}
       case target[:format]
       when 'skill-bundle'
         target_dir = install_cfg[:target_dir] || raise("Missing target_dir: #{pkgname}")
         dest_dir = base_path.join(platform_cfg[:skills_dir]).join(target_dir)
         remove_path(dest_dir, pkgname, ctx)
       else
         install_path = resolve_install_path(platform_cfg, target, base_path)
         remove_path(install_path, pkgname, ctx)
       end
     end
 
     def remove_path(path, pkgname = nil, ctx = nil)
       if path.exist?
         if ctx && !ctx.dry_run
           backup_path = backup_file(path)
           if path.directory?
             Transaction.record_journal(ctx, { action: :replace_dir, path: path, backup: backup_path })
           else
             Transaction.record_journal(ctx, { action: :replace_file, path: path, backup: backup_path })
           end
         end
 
         if path.file? && !path.symlink? && pkgname
           res = remove_marked_content(path, pkgname)
           if res == :removed
             log "    ✓ Excised package content from: #{path}"
             return
           elsif res == :file_removed
             log "    ✓ Removed empty file: #{path}"
             return
           end
         end
 
         if path.file? || path.symlink?
           FileUtils.rm(path)
         else
           FileUtils.rm_rf(path)
         end
         log "    ✓ Removed: #{path}"
       else
         log "    ✓ Already removed: #{path}"
       end
     end
 
     # Migrate installed records to include pkgrel/epoch if missing (for old index)
     def migrate_installed_records(pkg_index)
       return if pkg_index[:installed].nil?
 
       unless pkg_index[:installed].is_a?(Array)
         pkg_index[:installed] = []
         return
       end
 
       pkg_index[:installed].each do |rec|
         rec[:pkgrel] ||= 1
         rec[:epoch] ||= 0
       end
     end
   end
 end
