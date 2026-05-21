# frozen_string_literal: true

# Agent-to-Cursor Translator
# Converts agent prompt for Cursor's agents format.
# Creates agent.json manifest alongside the prompt file.
#
# INPUT:  Plain markdown agent prompt
# OUTPUT: Structured markdown (Cursor expects agent.json + prompt in same dir)
#
# Note: This translator transforms the markdown content. The agent.json manifest
# is generated separately by the build system from PKGBUILD's agent_config field.

module RulepackTranslator
  class Impl
    def self.translate(content, args: {})
      pkgname = args[:pkgname] || 'unknown'
      pkgdesc = args[:pkgdesc] || ''
      tags = args[:tags] || []

      clean = content.strip

      # Extract title from first H1 if present
      h1_match = clean.match(/^#\s+(.+)$/)
      title = h1_match ? h1_match[1].strip : pkgname.tr('-', ' ').split.map(&:capitalize).join(' ')

      # Cursor expects a clean markdown prompt — keep content as-is
      # The agent.json manifest is generated in build.rb from agent_config
      clean
    end
  end
end
