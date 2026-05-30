# frozen_string_literal: true

module Rulepack
  # Dynamic Schema Engine
  # Parses and applies constraints defined in data/platforms/<agent>.yaml
  module SchemaEngine
    module_function

    # Apply schema rules to content based on the target format profile
    # target_format: 'directory', 'import', 'skill', or 'skill-bundle'
    def apply(content, format_profile, target_format)
      return content if format_profile.nil? || format_profile.empty?

      # Determine which section of the schema to apply
      schema_section = %w[skill skill-bundle].include?(target_format) ? :skills : :rules
      ruleset = format_profile[schema_section]
      return content unless ruleset

      processed_content = content.dup

      # 1. Apply frontmatter policy
      if ruleset[:frontmatter] == 'strip'
        processed_content = Rulepack::Common.strip_frontmatter(processed_content)
      end

      # 2. Apply emoji policy
      if ruleset[:emoji_policy] == 'strip'
        # Simple regex to strip unicode emojis. 
        # Matches typical emoji ranges.
        emoji_regex = /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F700}-\u{1F77F}\u{1F780}-\u{1F7FF}\u{1F800}-\u{1F8FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/
        processed_content.gsub!(emoji_regex, '')
        processed_content.gsub!(/ {2,}/, ' ')  # collapse double spaces left by emoji removal
      end

      # 3. Apply heading style normalization
      lines = processed_content.split("\n")
      if ruleset[:heading_style].to_s == 'atx'
        lines = convert_setext_to_atx_lines(lines)
      end

      # 4. Line-by-line normalization (bullets & heading depth)
      lines.map! do |line|
        if ruleset[:bullet_style].to_s == 'dash'
          line = line.sub(/^(\s*)([*+])(\s+)/, '\1-\3')
        end

        if ruleset[:max_heading_depth]
          max_depth = ruleset[:max_heading_depth].to_i
          if max_depth > 0
            line = line.sub(/^(\s*)(#{'#' * (max_depth + 1)}#*)(\s+)/) do
              "#{$1}#{'#' * max_depth}#{$3}"
            end
          end
        end

        line
      end

      lines.join("\n")
    end

    def convert_setext_to_atx_lines(lines)
      result = []
      i = 0
      while i < lines.size
        line = lines[i]
        next_line = lines[i + 1]

        if next_line && line =~ /\S/ && next_line =~ /^={3,}\s*$/
          result << "# #{line.strip}"
          i += 2
        elsif next_line && line =~ /\S/ && next_line =~ /^-{3,}\s*$/
          result << "## #{line.strip}"
          i += 2
        else
          result << line
          i += 1
        end
      end
      result
    end

    # Auto-derive translator based on platform configuration and target format
    # Falls back to build_schema.yaml if no explicit translator in PKGBUILD
    def auto_derive_translator(platform_cfg, target_format)
      # If platform type is skill/skill-bundle and target format is skill, automatically use rule_to_skill
      if %w[skill skill-bundle].include?(target_format) && platform_cfg[:type].to_s == 'skill'
        'custom:data/translators/rule_to_skill.rb'
      else
        nil
      end
    end

    # Load build schema from data/build_schema.yaml (cached)
    def build_schema
      @build_schema ||= begin
        schema_path = Rulepack::Common::RULEPACK_ROOT.join('data', 'build_schema.yaml')
        if schema_path.exist?
          YAML.safe_load(schema_path.read, permitted_classes: [Symbol]) || {}
        else
          {}
        end
      end
    end

    # Derive default translator from build_schema.yaml for (platform, format)
    # Returns nil if schema has no entry or explicitly null
    def schema_translator(platform_id, target_format)
      entry = build_schema.dig('schema', platform_id.to_s, target_format.to_s)
      return nil unless entry
      entry['translate']
    end

    # Derive default transformer from build_schema.yaml for (platform, format)
    # Returns 'copy' (safe default) if schema has no entry
    def schema_transformer(platform_id, target_format)
      entry = build_schema.dig('schema', platform_id.to_s, target_format.to_s)
      return 'copy' unless entry
      entry['transformer'] || 'copy'
    end

    # Resolve effective translator: explicit PKGBUILD value overrides schema default
    def resolve_translator(explicit_translate, platform_id, target_format)
      return explicit_translate unless explicit_translate.nil?
      schema_translator(platform_id, target_format)
    end

    # Resolve effective transformer: explicit PKGBUILD value overrides schema default
    # explicit_transformer=nil means "not set in PKGBUILD" → fall back to schema
    # explicit_transformer='copy' means "PKGBUILD explicitly says copy" → no-op
    def resolve_transformer(explicit_transformer, platform_id, target_format)
      return explicit_transformer unless explicit_transformer.nil?
      schema_transformer(platform_id, target_format)
    end

  end
end
