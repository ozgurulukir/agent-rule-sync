# frozen_string_literal: true

# Agent-to-OpenCode Translator
# Wraps agent prompt in YAML frontmatter required by OpenCode.
#
# INPUT:  Plain markdown agent prompt (no frontmatter)
# OUTPUT: YAML frontmatter + markdown body
#
# Example output:
#   ---
#   name: Ruby Update Signatures
#   description: Auto-detect Ruby type-signature system...
#   ---
#   # Ruby Update Signatures
#   ...prompt body...

module RulepackTranslator
  module AgentToOpencode
    def self.translate(content, args: {})
      pkgname = args[:pkgname] || 'unknown'
      pkgdesc = args[:pkgdesc] || ''
      tags = args[:tags] || []

      clean = content.strip

      # Extract title from first H1 if present
      h1_match = clean.match(/^#\s+(.+)$/)
      title = h1_match ? h1_match[1].strip : pkgname.tr('-', ' ').split.map(&:capitalize).join(' ')

      # Build frontmatter
      name = title
      description = pkgdesc.to_s.strip.empty? ? title : pkgdesc.strip

      frontmatter = <<~YAML
        ---
        name: #{name}
        description: #{description.tr("\n", ' ').strip}
        #{tags.any? ? "tags:\n#{tags.map { |t| "  - #{t}" }.join("\n")}" : ''}
        ---
      YAML

      # Strip existing frontmatter if present
      body = clean.sub(/\A---\n.*?---\n*/m, '')

      "#{frontmatter}\n#{body}"
    end
  end
end
