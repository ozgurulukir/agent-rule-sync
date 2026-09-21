# frozen_string_literal: true

module Rulepack
  module Common
    module_function


    # Normalize a skill_exclude entry: to_s, strip trailing /, drop empties.
    def normalize_skill_exclude(entries)
      entries.to_a.map { |e| e.to_s.sub(/\/$/, '') }.reject(&:empty?)
    end

    # Pure helper: discover sub-skills from a source directory.
    # Returns an array of {path, name, files} hashes.
    # A sub-skill is any directory containing a SKILL.md (recursively found).
    # Files with no SKILL.md ancestor (including root-level SKILL.md) go to the `.` group.
    # The root dir is NEVER a sub-skill dir — a root-level SKILL.md belongs to the `.` group.
    # skill_exclude prefixes are matched against the sub-skill's relative path.
    def skill_bundle_sub_skills(build_pkg_dir, skill_exclude: [])
      build_pkg_dir = Pathname.new(build_pkg_dir)
      normalized_exclude = normalize_skill_exclude(skill_exclude)

      # Single glob pass: collect all files, reject symlinks and manifest.json
      all_files = Dir.glob("#{build_pkg_dir}/**/*", File::FNM_DOTMATCH).select do |f|
        File.file?(f) && !File.symlink?(f)
      end.reject { |f| f.end_with?('/manifest.json') }

      # Determine which files belong to which sub-skill directory.
      # A sub-skill = any directory containing a SKILL.md (recursively).
      # Files are owned by the DEEPEST SKILL.md-bearing ancestor directory.
      # Files with no such ancestor (loose top-level files, including root-level SKILL.md)
      # go to the `.` group.

      # Top-level dirs that contain a nested SKILL.md (category dirs, e.g.
      # mattpocock `engineering/`, `misc/`). Their loose files fall to the `.`
      # group so the category itself is not emitted as a sub-skill. A top-level
      # dir with NO nested SKILL.md (a leaf content dir like `scripts/`) keeps
      # its loose files as its own sub-skill (legacy behavior).
      category_dirs = Dir.children(build_pkg_dir).select do |entry|
        build_pkg_dir.join(entry).directory? &&
          Dir.glob("#{build_pkg_dir}/#{entry}/**/SKILL.md").any?
      end

      # First, find all directories that contain a SKILL.md (recursively).
      skill_dirs = {} # rel_path of dir => set of files owned by that dir
      all_files.each do |f|
        fpath = Pathname.new(f)
        rel = fpath.relative_path_from(build_pkg_dir).to_s

        # Walk up from the file to find the deepest directory containing SKILL.md
        owner = nil
        parts = rel.split('/')
        (1...parts.size).each do |depth|
          candidate = parts[0..depth-1].join('/')
          dir_path = build_pkg_dir.join(candidate)
          next unless dir_path.exist? && File.file?(dir_path.join('SKILL.md'))

          # Keep the deepest (longest) match
          owner = candidate if owner.nil? || candidate.count('/') > owner.count('/')
        end

        if owner
          # This file belongs to the deepest SKILL.md-bearing directory
          (skill_dirs[owner] ||= []) << rel
        else
          # No SKILL.md ancestor. A leaf top-level content dir (no nested
          # SKILL.md) keeps its loose files as its own sub-skill; a category
          # dir (has nested skills) sends them to the `.` group; root files
          # always go to `.`.
          top = parts.size > 1 ? parts[0] : '.'
          owner_dir = (top != '.' && category_dirs.include?(top)) ? '.' : top
          (skill_dirs[owner_dir] ||= []) << rel
        end
      end

      # Build the sub-skills array, excluding any that match skill_exclude prefixes
      sub_skills = []
      skill_dirs.each do |dir_path, files|
        # Normalize the dir path for comparison
        dir_rel = dir_path == '.' ? '.' : dir_path

        # Check if this dir matches any skill_exclude prefix
        excluded = normalized_exclude.any? do |prefix|
          dir_rel == prefix || dir_rel.start_with?(prefix + '/')
        end

        next if excluded

        sub_files = files.sort.each_with_object({}) do |rel, h|
          path = build_pkg_dir.join(rel)
          h[rel] = Digest::SHA256.hexdigest(path.read)
        end
        # Aggregate fingerprint over the sorted per-file map — preserved from
        # the pre-refactor manifest schema so existing consumers keep working.
        agg_sha = Digest::SHA256.hexdigest(sub_files.sort.to_h.to_s)
        sub_skills << {
          path: dir_rel,
          name: File.basename(dir_rel == '.' ? '.' : dir_rel),
          sha256: agg_sha,
          files: sub_files
        }
      end

      # Sort by path for deterministic output
      sub_skills.sort_by { |ss| ss[:path] }
    end

    # Generate skill-bundle manifest JSON for a built package directory.
    # build_pkg_dir: Pathname to the built package directory
    # pkgname: package name (string)
    # platform_id: platform identifier (string)
    # skill_exclude: YAML list of path prefixes (relative to source root) — optional
    # Returns the parsed manifest hash.
    def generate_skill_bundle_manifest(build_pkg_dir, pkgname, platform_id, skill_exclude: [])
      build_pkg_dir = Pathname.new(build_pkg_dir)
      manifest = {
        generated_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        pkgname: pkgname.to_s,
        platform: platform_id.to_s,
        sub_skills: skill_bundle_sub_skills(build_pkg_dir, skill_exclude: skill_exclude)
      }

      manifest_path = build_pkg_dir.join('manifest.json')
      manifest_path.write(JSON.pretty_generate(manifest))
      manifest
    end

    # load_platform_registry / clear_platform_registry_cache! delegators live
    # in common.rb (the composition root) ? do not redefine them here.


    # Find a platform config by name (string or symbol key)
    def platform_config(name, registry)
      key = name.to_sym
      cfg = registry[key] || registry[name.to_s]
      raise Rulepack::ConfigError, "Unknown platform: #{name}" unless cfg

      cfg
    end

    # Resolve install path for directory-type platforms
    def resolve_directory_path(platform_cfg, target_cfg, base)
      raise ArgumentError, "resolve_directory_path called for non-directory platform: #{platform_cfg[:type]}" unless platform_cfg[:type] == 'directory'

      install_cfg = target_cfg[:install] || {}
      target_dir = install_cfg[:target_dir]

      if target_dir
        target_subdir = Rulepack::Path.expand_user_path(target_dir)
        # If rules_file override (single-file platforms like antigravity)
        if !%w[skill skill-bundle].include?(target_cfg[:format]) && platform_cfg[:rules_file] && platform_cfg[:rule_install]&.[](:type) == 'append'
          Pathname.new(base).join(platform_cfg[:rules_file])
        else
          # skill/skill-bundle vs directory
          dir = if %w[skill skill-bundle].include?(target_cfg[:format])
                   platform_cfg[:skills_dir]
                 else
                   platform_cfg[:rules_dir]
                 end
          # Absolute or relative target_subdir
          resolved = if Pathname.new(target_subdir).absolute?
                       Pathname.new(target_subdir)
                     else
                       Pathname.new(base).join(dir, target_subdir)
                     end
          # Append output unless skill-bundle or rules_file override
          resolved = resolved.join(target_cfg[:output]) unless target_cfg[:format] == 'skill-bundle' || (!%w[skill skill-bundle].include?(target_cfg[:format]) && platform_cfg[:rules_file] && platform_cfg[:rule_install]&.[](:type) == 'append')
          resolved
        end
      else
        # No target_dir specified
        if !%w[skill skill-bundle].include?(target_cfg[:format]) && platform_cfg[:rules_file] && platform_cfg[:rule_install]&.[](:type) == 'append'
          Pathname.new(base).join(platform_cfg[:rules_file])
        else
          dir = if target_cfg[:format] == 'skill'
                   platform_cfg[:skills_dir] || platform_cfg[:rules_dir]
                 else
                   platform_cfg[:rules_dir]
                 end
          Pathname.new(base).join(dir, target_cfg[:output])
        end
      end
    end

    # Resolve install path for import-type platforms
    def resolve_import_path(platform_cfg, base)
      Pathname.new(base).join(platform_cfg[:config_file])
    end

    # Resolve install path for skill-type platforms
    def resolve_skill_path(platform_cfg, base)
      Pathname.new(base).join(platform_cfg[:skill_file])
    end

    def resolve_agent_install_path(platform_cfg, target_cfg, base)
      agents_dir = platform_cfg[:agents_dir]
      target_dir = (target_cfg[:install] && target_cfg[:install][:target_dir]) || target_cfg[:output]
      Pathname.new(base).join(agents_dir, target_dir)
    end


    def resolve_install_path(platform_cfg, target_cfg, base_override = nil)
      base = if base_override
               base_override.to_s
             else
               Rulepack::Path.expand_user_path(platform_cfg[:base_path])
             end

      install_cfg = target_cfg[:install] || {}
      target_dir = install_cfg[:target_dir]

      if target_dir
        if target_cfg[:format] == 'agent' && platform_cfg[:agents_dir]
          resolve_agent_install_path(platform_cfg, target_cfg, base)
        else
          target_subdir = Rulepack::Path.expand_user_path(target_dir)
          # Directory-type platforms have special handling
          if platform_cfg[:type] == 'directory'
            resolve_directory_path(platform_cfg, target_cfg, base)
          elsif Pathname.new(target_subdir).absolute?
            Pathname.new(target_subdir)
          else
            Pathname.new(base).join(target_subdir)
          end
        end
      else
        # No target_dir specified - agent format takes priority
        if target_cfg[:format] == 'agent' && platform_cfg[:agents_dir]
          resolve_agent_install_path(platform_cfg, target_cfg, base)
        else
          # Dispatch by platform type
          case platform_cfg[:type]
        when 'directory'
          resolve_directory_path(platform_cfg, target_cfg, base)
        when 'import'
          resolve_import_path(platform_cfg, base)
        when 'skill'
          resolve_skill_path(platform_cfg, base)
        else
          raise Rulepack::ConfigError, "Unknown platform type: #{platform_cfg[:type]}"
        end
        end # agent format check
      end
    end
    # Safe relative path (no escaping parent)
    def safe_relative(path, base)
      relative = Pathname.new(path).relative_path_from(base).to_s
      raise Rulepack::SecurityError, "Path escapes base: #{path} relative to #{base}" if relative.start_with?('..')

      relative
    end

    # Get build directory for a platform
    def build_dir_for_platform(platform)
      Rulepack::Common.build_dir.join(platform)
    end

    # Resolve project root for project-scoped platforms.
    # Returns nil for user-scoped platforms.
    def project_root_for(platform_cfg, project_arg)
      scope = platform_cfg[:scope] || 'user'
      return unless scope == 'project'

      unless project_arg
        raise Rulepack::ConfigError, "Platform '#{platform_cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>."
      end

      Pathname.new(project_arg).expand_path
    end
  end
end
