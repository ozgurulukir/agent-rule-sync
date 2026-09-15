# frozen_string_literal: true

# Platform registry loading and validation.
#
# Load is a pure function of the registry files under a root:
#   data/registry/platforms.yaml  <- <root>/.rulepack.local.yaml
#                                 <- ~/.config/rulepack/config.yaml
# Results are memoized per root, so tests that build sandbox registries get
# their own cache slot without touching the repo registry's entry.
module Rulepack
  module Platforms
    module_function

    VALID_PROFILE_KEYS = %w[frontmatter heading_style bullet_style emoji_policy max_heading_depth
                            format content_type code_block section_separator link_style
                            code_highlight sections_order references_format file_name note
                            injection_method config_file content no_frontmatter_required
                            no_code_blocks special].freeze

    def load(root)
      root = Pathname.new(root).expand_path.cleanpath
      key = Gem.win_platform? ? root.to_s.downcase : root.to_s
      @_registry_cache ||= {}
      @_registry_cache[key] ||= load_uncached(root)
    end

    def clear_cache!(root = nil)
      if root
        root = Pathname.new(root).expand_path.cleanpath
        key = Gem.win_platform? ? root.to_s.downcase : root.to_s
        @_registry_cache&.delete(key)
      else
        @_registry_cache = {}
      end
    end

    def load_uncached(root)
      raw = Rulepack::IO.load_yaml(root.join('data', 'registry', 'platforms.yaml'))

      # ─── Load Local Overrides ───────────────────────────────────────────────
      local_path = root.join('.rulepack.local.yaml')
      user_local_path = Pathname.new(Rulepack::Path.expand_user_path('~/.config/rulepack/config.yaml'))

      overrides = nil
      begin
        overrides = Rulepack::IO.load_yaml(local_path) if local_path.exist?
        if user_local_path.exist?
          user_overrides = Rulepack::IO.load_yaml(user_local_path)
          overrides = overrides ? Rulepack::IO.deep_merge(overrides, user_overrides) : user_overrides
        end
      rescue StandardError => e
        Rulepack::Logging.log_warn "Failed to load local registry overrides: #{e.message}"
      end

      if overrides && (over_platforms = overrides[:platforms] || overrides['platforms'])
        over_platforms.each do |id, over_cfg|
          next unless over_cfg.is_a?(Hash)
          sym_over_cfg = over_cfg.transform_keys(&:to_sym)
          raw_key = raw.keys.find { |k| k.to_s == id.to_s }
          raw[raw_key] = raw[raw_key].merge(sym_over_cfg) if raw_key
        end
      end
      # ────────────────────────────────────────────────────────────────────────

      raw.each do |id, cfg|
        validate_platform_config(id, cfg)
        profile_path = root.join('data', 'platforms', "#{id}.yaml")
        cfg[:format_profile] = profile_path.exist? ? Rulepack::IO.load_yaml(profile_path) : {}
        validate_format_profile(cfg[:format_profile], id)
      end

      raw
    end

    # Validate a single platform configuration
    def validate_platform_config(id, cfg)
      %i[type base_path].each do |req|
        raise Rulepack::ConfigError, "Platform '#{id}' missing required field: #{req}" unless cfg[req]
      end

      case cfg[:type]
      when 'directory'
        unless cfg[:rules_dir] || cfg[:rules_file]
          raise Rulepack::ConfigError, "Platform '#{id}' (directory) missing :rules_dir or :rules_file"
        end
      when 'import'
        raise Rulepack::ConfigError, "Platform '#{id}' (import) missing :config_file" unless cfg[:config_file]
      when 'skill'
        raise Rulepack::ConfigError, "Platform '#{id}' (skill) missing :skill_file" unless cfg[:skill_file]
      else
        raise Rulepack::ConfigError, "Platform '#{id}' has unknown type: #{cfg[:type]}"
      end
    end

    def validate_format_profile(profile, platform_id)
      return if profile.nil? || profile.empty?

      %w[rules skills].each do |section|
        section_data = profile[section.to_sym] || profile[section]
        next unless section_data.is_a?(Hash)

        section_data.each_key do |key|
          key_s = key.to_s
          next if VALID_PROFILE_KEYS.include?(key_s)

          Rulepack::Logging.log_warn "Platform #{platform_id}: unknown key '#{key_s}' in format_profile.#{section}"
        end
      end
    end
  end
end
