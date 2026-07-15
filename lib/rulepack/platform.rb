# frozen_string_literal: true

module Rulepack
  module Common
    module_function


    # Generate skill-bundle manifest JSON for a built package directory.
    # build_pkg_dir: Pathname to the built package directory
    # pkgname: package name (string)
    # platform_id: platform identifier (string)
    # Returns the parsed manifest hash.
    def generate_skill_bundle_manifest(build_pkg_dir, pkgname, platform_id)
      build_pkg_dir = Pathname.new(build_pkg_dir)
      manifest = {
        generated_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        pkgname: pkgname.to_s,
        platform: platform_id.to_s,
        sub_skills: []
      }

      # Single glob pass: collect all files, group by top-level dir.
      # Security: reject symlinks — path.read below follows them and could read
      # arbitrary host files if a symlink was planted by an untrusted source.
      all_files = Dir.glob("#{build_pkg_dir}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) && !File.symlink?(f) }
                                                                       .reject { |f| f.end_with?('/manifest.json') }

      # Group files into sub-skills (top-level directory = sub-skill name)
      groups = { '.' => [] }
      all_files.each do |f|
        rel = Pathname.new(f).relative_path_from(build_pkg_dir).to_s
        top = rel.include?('/') ? rel.split('/').first : '.'
        (groups[top] ||= []) << rel
      end

      groups.each do |name, files|
        next if name == '..'

        sub_files = {}
        files.sort.each do |rel|
          path = build_pkg_dir.join(rel)
          sub_files[rel] = Digest::SHA256.hexdigest(path.read)
        end
        next if sub_files.empty?

        agg_sha = Digest::SHA256.hexdigest(sub_files.sort.to_h.to_s)
        manifest[:sub_skills] << { path: name, name: name, sha256: agg_sha, files: sub_files }
      end

      manifest_path = build_pkg_dir.join('manifest.json')
      manifest_path.write(JSON.pretty_generate(manifest))
      manifest
    end

    # Load platform registry (memoized — cached after first call)
    def load_platform_registry
      return @_platform_registry if @_platform_registry

      registry_path = RULEPACK_ROOT.join('data', 'registry', 'platforms.yaml')
      raw = load_yaml(registry_path)

      # ─── Load Local Overrides ───────────────────────────────────────────────
      local_path = RULEPACK_ROOT.join('.rulepack.local.yaml')
      user_local_path = Pathname.new(expand_user_path('~/.config/rulepack/config.yaml'))

      overrides = nil
      begin
        if local_path.exist?
          overrides = load_yaml(local_path)
        end
        if user_local_path.exist?
          user_overrides = load_yaml(user_local_path)
          overrides = overrides ? deep_merge(overrides, user_overrides) : user_overrides
        end
      rescue StandardError => e
        Rulepack::Common.log_warn "Failed to load local registry overrides: #{e.message}"
      end

      if overrides && (over_platforms = overrides[:platforms] || overrides['platforms'])
        over_platforms.each do |id, over_cfg|
          next unless over_cfg.is_a?(Hash)
          sym_over_cfg = over_cfg.transform_keys(&:to_sym)
          raw_key = raw.keys.find { |k| k.to_s == id.to_s }
          if raw_key
            raw[raw_key] = raw[raw_key].merge(sym_over_cfg)
          end
        end
      end
      # ────────────────────────────────────────────────────────────────────────

      raw.each do |id, cfg|
        validate_platform_config(id, cfg)
        profile_path = RULEPACK_ROOT.join('data', 'platforms', "#{id}.yaml")
        cfg[:format_profile] = profile_path.exist? ? load_yaml(profile_path) : {}
        validate_format_profile(cfg[:format_profile], id)
      end

      @_platform_registry = raw
    end

    # Clear the platform registry cache (useful for testing)
    def clear_platform_registry_cache!
      @_platform_registry = nil
    end

    # Validate a single platform configuration
    def validate_platform_config(id, cfg)
      %i[type base_path].each do |req|
        raise "Platform '#{id}' missing required field: #{req}" unless cfg[req]
      end

      case cfg[:type]
      when 'directory'
        unless cfg[:rules_dir] || cfg[:rules_file]
          raise "Platform '#{id}' (directory) missing :rules_dir or :rules_file"
        end
      when 'import'
        raise "Platform '#{id}' (import) missing :config_file" unless cfg[:config_file]
      when 'skill'
        raise "Platform '#{id}' (skill) missing :skill_file" unless cfg[:skill_file]
      else
        raise "Platform '#{id}' has unknown type: #{cfg[:type]}"
      end
    end

    VALID_PROFILE_KEYS = %w[frontmatter heading_style bullet_style emoji_policy max_heading_depth
                            format content_type code_block section_separator link_style
                            code_highlight sections_order references_format file_name note
                            injection_method config_file content no_frontmatter_required
                            no_code_blocks special].freeze

    def validate_format_profile(profile, platform_id)
      return if profile.nil? || profile.empty?

      %w[rules skills].each do |section|
        section_data = profile[section.to_sym] || profile[section]
        next unless section_data.is_a?(Hash)

        section_data.each_key do |key|
          key_s = key.to_s
          next if VALID_PROFILE_KEYS.include?(key_s)

          log_warn "Platform #{platform_id}: unknown key '#{key_s}' in format_profile.#{section}"
        end
      end
    end

    # Find a platform config by name (string or symbol key)
    def platform_config(name, registry)
      key = name.to_sym
      cfg = registry[key] || registry[name.to_s]
      raise "Unknown platform: #{name}" unless cfg

      cfg
    end

    # Resolve install path for directory-type platforms
    def resolve_directory_path(platform_cfg, target_cfg, base)
      raise ArgumentError, "resolve_directory_path called for non-directory platform: #{platform_cfg[:type]}" unless platform_cfg[:type] == 'directory'

      install_cfg = target_cfg[:install] || {}
      target_dir = install_cfg[:target_dir]

      if target_dir
        target_subdir = expand_user_path(target_dir)
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
               expand_user_path(platform_cfg[:base_path])
             end

      install_cfg = target_cfg[:install] || {}
      target_dir = install_cfg[:target_dir]

      if target_dir
        if target_cfg[:format] == 'agent' && platform_cfg[:agents_dir]
          resolve_agent_install_path(platform_cfg, target_cfg, base)
        else
          target_subdir = expand_user_path(target_dir)
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
          raise "Unknown platform type: #{platform_cfg[:type]}"
        end
        end # agent format check
      end
    end
    # Safe relative path (no escaping parent)
    def safe_relative(path, base)
      relative = Pathname.new(path).relative_path_from(base).to_s
      raise "Path escapes base: #{path} relative to #{base}" if relative.start_with?('..')

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
        raise StandardError, "Platform '#{platform_cfg[:display_name]}' is project-scoped. You must explicitly specify the project path with --project <path>."
      end

      Pathname.new(project_arg).expand_path
    end
  end
end
