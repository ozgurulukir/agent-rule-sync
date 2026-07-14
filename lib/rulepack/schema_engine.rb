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
      if ruleset[:heading_style].to_s == 'atx'
        convert_setext_to_atx!(processed_content)
      end

      # 4. Normalization (bullets & heading depth)
      if ruleset[:bullet_style].to_s == 'dash'
        # Optimize: global substitution over the entire multi-line string
        processed_content.gsub!(/^([ \t]*)([*+])([ \t]+)/, '\1-\3')
      end

      if ruleset[:max_heading_depth]
        max_depth = ruleset[:max_heading_depth].to_i
        if max_depth > 0
          # Optimize: global substitution over the entire multi-line string
          processed_content.gsub!(/^([ \t]*)(#{Regexp.escape('#' * (max_depth + 1))}#*)([ \t]+)/) do
            "#{$1}#{'#' * max_depth}#{$3}"
          end
        end
      end

      processed_content
    end

    # Replaces Setext headings with ATX headings inline
    def convert_setext_to_atx!(content)
      # Match line with non-whitespace, followed by newline and then === or ---
      content.gsub!(/^([ \t]*\S.*)\n={3,}[ \t]*$/) { |m| "# #{$1.strip}" }
      content.gsub!(/^([ \t]*\S.*)\n-{3,}[ \t]*$/) { |m| "## #{$1.strip}" }
    end

    # Resolve effective translator:
    # 1. PKGBUILD explicit translate value wins
    # 2. Platform registry default_translator (from data/registry/platforms.yaml)
    # 3. nil (no translation)
    def resolve_translator(explicit_translate, _platform_id, _target_format, platform_cfg = nil)
      return explicit_translate unless explicit_translate.nil?
      return nil unless platform_cfg

      platform_cfg[:default_translator]
    end

    # Resolve effective transformer:
    # 1. PKGBUILD explicit transformer value wins
    # 2. Platform registry default_transformer (falls back to 'copy')
    def resolve_transformer(explicit_transformer, _platform_id, _target_format, platform_cfg = nil)
      return explicit_transformer unless explicit_transformer.nil?
      return 'copy' unless platform_cfg

      platform_cfg[:default_transformer] || 'copy'
    end

  end
end
