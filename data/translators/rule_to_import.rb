# frozen_string_literal: true

# Rule-to-Import Translator
# Normalizes rule content for import-based platforms (Qwen Code, GitHub Copilot).
#
# INPUT:  Flat markdown rule with arbitrary heading depths
# OUTPUT: Clean markdown with normalized heading depths,
#         trailing whitespace stripped, and frontmatter already removed by SchemaEngine
#
# This translator handles structural normalization that goes beyond what
# the Schema Engine's format profile covers. The Schema Engine handles
# frontmatter stripping, emoji removal, bullet style, and ATX heading conversion.
# This translator normalizes heading depth to fit within a single-file context
# where the rule content is embedded alongside other content.

module RulepackTranslator
  module RuleToImport
    def self.translate(content, args: {})
      clean = content.strip

      lines = clean.each_line.map do |line|
        normalized = line.rstrip

        # Flatten heading depth: ### and deeper → ##
        # Preserves ## (section) and # (title) as-is
        normalized = normalized.sub(/^(#{'#'}{3,})(\s+)/, '##\2')

        normalized
      end

      result = lines.join("\n")
      "#{result.strip}\n"
    end
  end
end
