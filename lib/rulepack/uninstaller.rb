# frozen_string_literal: true

module Rulepack
  module Common
    module_function

    def validate_pkgbuild(pkg, _pkgdir)
      errors = []
      validate_pkgname(pkg, errors)
      validate_version_fields(pkg, errors)
      validate_descriptive_fields(pkg, errors)
      validate_source_entries(pkg, errors)
      validate_target_entries(pkg, errors)
      errors.empty? || errors.join('; ')
    end

    def validate_pkgname(pkg, errors)
      return if pkg[:pkgname] =~ /\A[a-z0-9][a-z0-9_-]*\z/

      errors << "Invalid pkgname '#{pkg[:pkgname]}': must be lowercase alphanumeric with - or _"
    end

    def validate_version_fields(pkg, errors)
      errors << 'Invalid pkgver: must be non-empty string' unless pkg[:pkgver].is_a?(String) && !pkg[:pkgver].empty?
      if pkg.key?(:pkgver_func) && !(pkg[:pkgver_func].is_a?(String) && !pkg[:pkgver_func].empty?)
        errors << 'pkgver_func must be a non-empty string'
      end
      errors << 'Invalid epoch: must be integer >= 0' unless pkg[:epoch].is_a?(Integer) && pkg[:epoch] >= 0
      errors << 'Invalid pkgrel: must be integer >= 1' unless pkg[:pkgrel].is_a?(Integer) && pkg[:pkgrel] >= 1
    end

    def validate_descriptive_fields(pkg, errors)
      errors << 'Invalid pkgdesc: must be non-empty string' unless pkg[:pkgdesc].is_a?(String) && !pkg[:pkgdesc].empty?
      errors << "Invalid arch: only 'any' supported" unless pkg[:arch] == 'any'
      order_val = pkg[:order] || 0
      errors << 'Invalid order: must be integer >= 0' unless order_val.is_a?(Integer) && order_val >= 0
    end

    def validate_source_entries(pkg, errors)
      errors << 'source must be a non-empty array' unless pkg[:source].is_a?(Array) && !pkg[:source].empty?
      pkg[:source]&.each_with_index do |src, i|
        errors << "source[#{i}] missing type or path/url" unless src[:type] && (src[:path] || src[:url])
        case src[:type]
        when 'local'
          unless src[:path].is_a?(String) && !src[:path].empty?
            errors << "source[#{i}] local type requires non-empty path"
          end
        when 'url'
          errors << "source[#{i}] url type requires url" unless src[:url].is_a?(String) && !src[:url].empty?
          errors << "source[#{i}] url type requires valid sha256" unless src[:sha256] =~ /\A[0-9a-f]{64}\z/i
        when 'git'
          errors << "source[#{i}] git type requires url" unless src[:url].is_a?(String) && !src[:url].empty?
          errors << "source[#{i}] git ref must be string" if src.key?(:ref) && !src[:ref].is_a?(String)
          errors << "source[#{i}] git path must be string" if src.key?(:path) && !src[:path].is_a?(String)
          errors << "source[#{i}] git depth must be integer" if src.key?(:depth) && !src[:depth].is_a?(Integer)
        else
          errors << "source[#{i}] unknown type: #{src[:type]}"
        end
      end
    end

    def validate_target_entries(pkg, errors)
      errors << 'targets must be a non-empty array' unless pkg[:targets].is_a?(Array) && !pkg[:targets].empty?
      return unless pkg[:targets].is_a?(Array)

      valid_formats = %w[directory import skill skill-bundle]
      pkg[:targets].each_with_index do |t, i|
        errors << "targets[#{i}]: missing platform" unless t[:platform].is_a?(String)
        unless valid_formats.include?(t[:format])
          errors << "targets[#{i}]: invalid format '#{t[:format]}' (must be #{valid_formats.join('/')})"
        end
        begin
          validate_target_entry_output(t, i, pkg, errors)
        rescue StandardError => e
          errors << "targets[#{i}]: #{e.message}"
        end
        tf = t[:transformer]
        if tf && tf != 'copy' && tf != 'strip-frontmatter' && tf !~ /\Acustom:.+\z/
          errors << "targets[#{i}]: invalid transformer '#{tf}'"
        end
        if t[:install]
          inst = t[:install]
          unless %w[symlink copy inject append].include?(inst[:type])
            errors << "targets[#{i}]: invalid install.type '#{inst[:type]}'"
          end
          validate_target_dir(inst[:target_dir], pkg[:pkgname]) if inst[:target_dir]
        end
        next unless t[:format] == 'skill-bundle'

        inst = t[:install] || {}
        unless inst[:target_dir].is_a?(String) && !inst[:target_dir].empty?
          errors << "targets[#{i}]: skill-bundle requires install.target_dir"
        end
        errors << "targets[#{i}]: skill-bundle install.type must be 'copy'" unless (inst[:type] || 'copy') == 'copy'
      end
    end

    def validate_target_entry_output(t, i, pkg, errors)
      if t[:output].nil? || t[:output].empty?
        errors << "targets[#{i}]: output cannot be empty"
      else
        validate_output_filename(t[:output], pkg[:pkgname])
      end
    end

    # Uninstall packages from a platform, modifying index in-place.
    # Returns array of uninstalled package names.
    # Does NOT write index to disk.
    def uninstall_packages(index, platform_id, dry_run: false, project_root: nil,
                           specific_packages: nil)
      platform_cfg = platform_config(platform_id, load_platform_registry)
      base_path = project_root || Pathname.new(expand_user_path(platform_cfg[:base_path]))
      build_index = load_yaml(BUILD_INDEX_PATH)
      pkg_names = resolve_uninstall_targets(index, platform_id, specific_packages)

      uninstalled = []
      pkg_names.each do |pkgname|
        result = uninstall_single_package(pkgname, index, build_index, platform_id,
                                          platform_cfg, base_path, dry_run)
        uninstalled << result if result
      end
      uninstalled.uniq
    end

    def resolve_uninstall_targets(index, platform_id, specific_packages)
      return specific_packages if specific_packages

      index[:packages].select do |_name, pkg|
        pkg[:installed]&.any? { |i| i[:platform] == platform_id }
      end.keys
    end

    def uninstall_single_package(pkgname, index, build_index, platform_id,
                                 platform_cfg, base_path, dry_run)
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
        uninstall_record(rec, target_by_output, platform_cfg, base_path, pkgname, dry_run)
        records.delete(rec)
      end
      pkgname
    end

    def uninstall_record(rec, target_by_output, platform_cfg, base_path, pkgname, dry_run)
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
      remove_target_file(target, platform_cfg, base_path, pkgname)
    end

    def remove_target_file(target, platform_cfg, base_path, pkgname)
      install_cfg = target[:install] || {}
      case target[:format]
      when 'skill-bundle'
        target_dir = install_cfg[:target_dir] || raise("Missing target_dir: #{pkgname}")
        dest_dir = base_path.join(platform_cfg[:skills_dir]).join(target_dir)
        remove_path(dest_dir)
      else
        install_path = resolve_install_path(platform_cfg, target, nil)
        remove_path(install_path)
      end
    end

    def remove_path(path)
      if path.exist?
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
      return unless pkg_index[:installed].is_a?(Array)

      pkg_index[:installed].each do |rec|
        rec[:pkgrel] ||= 1
        rec[:epoch] ||= 0
      end
    end
  end
end
