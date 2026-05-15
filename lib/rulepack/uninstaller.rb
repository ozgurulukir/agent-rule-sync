# frozen_string_literal: true

module Rulepack
  module Common
    module_function

      def validate_pkgbuild(pkg, pkgdir)
        errors = []

        # pkgname: lowercase alphanumeric + hyphens/underscores, min 2 char
        unless pkg[:pkgname] =~ /\A[a-z0-9][a-z0-9_-]*\z/
          errors << "Invalid pkgname '#{pkg[:pkgname]}': must be lowercase alphanumeric with - or _"
        end

        # pkgver: non-empty string (can be overridden by pkgver_func)
        unless pkg[:pkgver].is_a?(String) && !pkg[:pkgver].empty?
          errors << "Invalid pkgver: must be non-empty string"
        end

        # pkgver_func: optional command string
        if pkg.key?(:pkgver_func)
          unless pkg[:pkgver_func].is_a?(String) && !pkg[:pkgver_func].empty?
            errors << "pkgver_func must be a non-empty string"
          end
        end

        # epoch: integer >= 0 (defaulted before call)
        unless pkg[:epoch].is_a?(Integer) && pkg[:epoch] >= 0
          errors << "Invalid epoch: must be integer >= 0"
        end

        # pkgrel: integer >= 1 (defaulted before call)
        unless pkg[:pkgrel].is_a?(Integer) && pkg[:pkgrel] >= 1
          errors << "Invalid pkgrel: must be integer >= 1"
        end

        # pkgdesc: non-empty string
        unless pkg[:pkgdesc].is_a?(String) && !pkg[:pkgdesc].empty?
          errors << "Invalid pkgdesc: must be non-empty string"
        end

        # arch: currently only 'any'
        unless pkg[:arch] == 'any'
          errors << "Invalid arch: only 'any' supported"
        end

        # order: integer >= 0
        order_val = pkg[:order] || 0
        unless order_val.is_a?(Integer) && order_val >= 0
          errors << "Invalid order: must be integer >= 0"
        end

        # source: array, at least one entry
        unless pkg[:source].is_a?(Array) && !pkg[:source].empty?
          errors << "source must be a non-empty array"
        end

        # Guard each_with_index against nil source; empty arrays still iterate (zero times)
        pkg[:source]&.each_with_index do |src, i|
            unless src[:type] && (src[:path] || src[:url])
              errors << "source[#{i}] missing type or path/url"
            end
          case src[:type]
          when 'local'
            unless src[:path].is_a?(String) && !src[:path].empty?
              errors << "source[#{i}] local type requires non-empty path"
            end
          when 'url'
            unless src[:url].is_a?(String) && !src[:url].empty?
              errors << "source[#{i}] url type requires url"
            end
            unless src[:sha256] =~ /\A[0-9a-f]{64}\z/i
              errors << "source[#{i}] url type requires valid sha256"
            end
          when 'git'
            unless src[:url].is_a?(String) && !src[:url].empty?
              errors << "source[#{i}] git type requires url"
            end
            # ref, path, depth optional
            if src.key?(:ref) && !src[:ref].is_a?(String)
              errors << "source[#{i}] git ref must be string"
            end
            if src.key?(:path) && !src[:path].is_a?(String)
              errors << "source[#{i}] git path must be string"
            end
            if src.key?(:depth) && !src[:depth].is_a?(Integer)
              errors << "source[#{i}] git depth must be integer"
            end
          else
            errors << "source[#{i}] unknown type: #{src[:type]}"
          end
        end  # each_with_index

        # targets: array, at least one
        unless pkg[:targets].is_a?(Array) && !pkg[:targets].empty?
          errors << "targets must be a non-empty array"
        end

        if pkg[:targets].is_a?(Array)
          valid_formats = %w[directory import skill skill-bundle]
          pkg[:targets].each_with_index do |t, i|
          unless t[:platform] && t[:platform].is_a?(String)
            errors << "targets[#{i}]: missing platform"
          end
          unless valid_formats.include?(t[:format])
            errors << "targets[#{i}]: invalid format '#{t[:format]}' (must be #{valid_formats.join('/')})"
          end
          # output validation
          output = t[:output]
          if output.nil? || output.empty?
            errors << "targets[#{i}]: output cannot be empty"
          else
            begin
              validate_output_filename(output, pkg[:pkgname])
            rescue => e
              errors << "targets[#{i}]: #{e.message}"
            end
          end
          # transformer validation
          if t[:transformer] && t[:transformer] != 'copy' && t[:transformer] != 'strip-frontmatter'
            unless t[:transformer] =~ /\Acustom:.+\z/
              errors << "targets[#{i}]: invalid transformer '#{t[:transformer]}'"
            end
          end
          # install validation
          if t[:install]
            inst = t[:install]
            unless %w[symlink copy inject append].include?(inst[:type])
              errors << "targets[#{i}]: invalid install.type '#{inst[:type]}'"
            end
            if inst[:target_dir]
              validate_target_dir(inst[:target_dir], pkg[:pkgname])
            end
          end
          # skill-bundle requires install.target_dir even when no install block present
          if t[:format] == 'skill-bundle'
            inst = t[:install] || {}
            unless inst[:target_dir] && inst[:target_dir].is_a?(String) && !inst[:target_dir].empty?
              errors << "targets[#{i}]: skill-bundle requires install.target_dir"
            end
            unless (inst[:type] || 'copy') == 'copy'
              errors << "targets[#{i}]: skill-bundle install.type must be 'copy'"
            end
          end
        end  # each_with_index
        end  # if pkg[:targets].is_a?(Array)

        # checksums: auto, skip

        # dependencies, conflicts, provides, tags, maintainer, license: optional types
        # No strict validation on these

        errors.empty? ? true : errors.join('; ')
      end

       # Uninstall packages from a platform, modifying index in-place.
       # Returns array of uninstalled package names.
       # Does NOT write index to disk.
       def uninstall_packages(index, platform_id, dry_run: false, project_root: nil, specific_packages: nil)
         platform_cfg = platform_config(platform_id, load_platform_registry)
         base_path = if project_root
                       project_root
                     else
                       Pathname.new(expand_user_path(platform_cfg[:base_path]))
                     end

         # Load build index for target info
         build_index = load_yaml(BUILD_INDEX_PATH)
         packages_to_uninstall = if specific_packages
                                   specific_packages
                                 else
                                   index[:packages].select { |name, pkg| pkg[:installed]&.any? { |i| i[:platform] == platform_id } }.keys
                                 end

         uninstalled = []

         packages_to_uninstall.each do |pkgname|
           pkg_index = index[:packages][pkgname]
           next unless pkg_index

           records = pkg_index[:installed] || []
           platform_records = records.select { |r| r[:platform] == platform_id }

           if platform_records.empty?
             log "  ⚠ #{pkgname} not installed on #{platform_id}, skipping uninstall" unless dry_run
             next
           end

           pkgdata = build_index[:packages][pkgname]
           unless pkgdata
             log_error "Package not found in build index: #{pkgname}"
             next
           end
           targets = pkgdata[:targets]&.select { |t| t[:platform] == platform_id } || []
           target_by_output = {}
           targets.each { |t| target_by_output[t[:output]] = t }

           platform_records.each do |rec|
             output = rec[:output]
             target = target_by_output[output]
             unless target
               log_warn "  ⚠ No target found for output '#{output}' in #{pkgname}, skipping uninstall"
               next
             end

             if dry_run
               log "    [DRY-RUN] Would remove: #{output}"
               uninstalled << pkgname
               next
             end

             format = target[:format]
             install_cfg = target[:install] || {}
             case format
             when 'skill-bundle'
               target_dir = install_cfg[:target_dir] || raise("Missing target_dir for skill-bundle uninstall: #{pkgname}")
               dest_dir = base_path.join(platform_cfg[:skills_dir]).join(target_dir)
               if dest_dir.exist?
                 FileUtils.rm_rf(dest_dir)
                 log "    ✓ Removed directory: #{dest_dir}"
               else
                 log "    ✓ Already removed: #{dest_dir}"
               end
             else
               install_path = resolve_install_path(platform_cfg, target, project_root)
               if install_path.exist?
                 FileUtils.rm(install_path) if install_path.file? || install_path.symlink?
                 FileUtils.rm_rf(install_path) if install_path.directory?
                 log "    ✓ Removed: #{install_path}"
               else
                 log "    ✓ Already removed: #{install_path}"
               end
             end

             # Mark record for removal
             records.delete(rec)
             uninstalled << pkgname
           end
         end

         uninstalled.uniq
       end

       # Migrate installed records to include pkgrel/epoch if missing (for old index)
       def migrate_installed_records(pkg_index)
         return unless pkg_index[:installed].is_a?(Array)
         pkg_index[:installed].each do |rec|
           rec[:pkgrel] ||= 1
           rec[:epoch] ||= 0
          end
       end
    end
end
