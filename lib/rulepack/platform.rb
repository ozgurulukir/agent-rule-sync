# frozen_string_literal: true

module Rulepack
  module Common
    module_function

      # Load YAML from path (symbol keys)
      def load_yaml(path)
        pathname = Pathname.new(path)
        return {} unless pathname.exist?
        content = pathname.read
        YAML.safe_load(content, permitted_classes: [Symbol, Pathname], symbolize_names: true)
      end

      # Write YAML atomically
      def write_yaml_atomic(path, data)
        yaml_content = data.to_yaml
        atomic_write(path, yaml_content)
      end

      # Append to file atomically (create if doesn't exist)
      def atomic_append(path, content)
        path = Pathname.new(path)
        path.dirname.mkpath

        File.open(path.to_s, 'a') { |f| f.write(content) }
      end

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

        # Single glob pass: collect all files, group by top-level dir
        all_files = Dir.glob("#{build_pkg_dir}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }
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

        raw.each { |id, cfg| validate_platform_config(id, cfg) }

        @_platform_registry = raw
      end

      # Clear the platform registry cache (useful for testing)
      def clear_platform_registry_cache!
        @_platform_registry = nil
      end

      # Validate a single platform configuration
      def validate_platform_config(id, cfg)
        [:type, :base_path].each do |req|
          unless cfg[req]
            raise "Platform '#{id}' missing required field: #{req}"
          end
        end

        case cfg[:type]
        when 'directory'
          unless cfg[:rules_dir]
            raise "Platform '#{id}' (directory) missing :rules_dir"
          end
        when 'import'
          unless cfg[:config_file]
            raise "Platform '#{id}' (import) missing :config_file"
          end
        when 'skill'
          unless cfg[:skill_file]
            raise "Platform '#{id}' (skill) missing :skill_file"
          end
        else
          raise "Platform '#{id}' has unknown type: #{cfg[:type]}"
        end
      end

      # Find a platform config by name (string or symbol key)
      def platform_config(name, registry)
        key = name.to_sym
        cfg = registry[key] || registry[name.to_s]
        raise "Unknown platform: #{name}" unless cfg
        cfg
      end

       # Resolve install path for a platform/target
       # base_override: for project-level platforms, the actual project root Pathname
       def resolve_install_path(platform_cfg, target_cfg, base_override = nil)
         base = if base_override
                  base_override.to_s
                else
                  expand_user_path(platform_cfg[:base_path])
                end

         case platform_cfg[:type]
         when 'directory'
           dir = if target_cfg[:format] == 'skill'
                   platform_cfg[:skills_dir] || platform_cfg[:rules_dir]
                 else
                   platform_cfg[:rules_dir]
                 end
           Pathname.new(base).join(dir, target_cfg[:output])
         when 'import'
           Pathname.new(base).join(platform_cfg[:config_file])
         when 'skill'
           Pathname.new(base).join(platform_cfg[:skill_file])
         else
           raise "Unknown platform type: #{platform_cfg[:type]}"
         end
       end

      # Safe relative path (no escaping parent)
      def safe_relative(path, base)
        relative = Pathname.new(path).relative_path_from(base).to_s
        if relative.start_with?('..')
          raise "Path escapes base: #{path} relative to #{base}"
        end
        relative
      end

      # Get build directory for a platform
      def build_dir_for_platform(platform)
        Pathname.new('build').join(platform)
      end

      # Resolve project root for project-scoped platforms.
      # Returns nil for user-scoped platforms.
      def project_root_for(platform_cfg, project_arg)
        scope = platform_cfg[:scope] || 'user'
        if scope == 'project'
          project_arg ? Pathname.new(project_arg).expand_path : Pathname.pwd
        else
          nil
        end
      end
    end
end
