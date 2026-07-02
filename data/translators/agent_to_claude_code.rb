# frozen_string_literal: true

# Agent-to-Claude-Code Translator
# Converts agent prompt into Claude Code's markdown section schema.
#
# INPUT:  Plain markdown agent prompt
# OUTPUT: Structured markdown with ## Metadata, ## System Prompt, ## Capabilities sections
#
# Claude Code expects agents in .claude/agents/ as markdown files with
# specific section headings that the parser extracts.

module RulepackTranslator
  module AgentToClaudeCode
    def self.translate(content, args: {})
      pkgname = args[:pkgname] || 'unknown'
      pkgdesc = args[:pkgdesc] || ''
      tags = args[:tags] || []

      clean = content.strip

      # Extract title from first H1 if present
      h1_match = clean.match(/^#\s+(.+)$/)
      title = h1_match ? h1_match[1].strip : pkgname.tr('-', ' ').split.map(&:capitalize).join(' ')

      # Body without H1
      body = h1_match ? clean.sub(/^#\s+.+\n*/, '').strip : clean

      # Build structured sections
      lines = []
      lines << "# #{title}"
      lines << ''

      # Metadata section
      lines << '## Metadata'
      lines << ''
      lines << "- **ID**: #{pkgname}"
      lines << "- **Name**: #{title}"
      description = pkgdesc.to_s.strip.empty? ? title : pkgdesc.strip.tr("\n", ' ')
      lines << "- **Description**: #{description}"
      lines << (tags.any? ? "- **Tags**: #{tags.join(', ')}" : '')
      lines << ''

      # System Prompt section
      lines << '## System Prompt'
      lines << ''
      lines << body
      lines << ''

      lines.join("\n")
    end
  end
end
