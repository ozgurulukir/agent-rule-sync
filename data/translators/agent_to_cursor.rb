# frozen_string_literal: true

# Agent-to-Cursor Translator
# Converts agent prompt for Cursor's agents format.
# Cursor agents live in .cursor/agents/<name>/ with agent.json + prompt.md
#
# INPUT:  Plain markdown agent prompt
# OUTPUT: Clean markdown with Cursor-compatible structure
#
# Cursor expects:
#   - A clear markdown prompt file
#   - agent.json manifest (generated separately from PKGBUILD agent_config)
#
# This translator normalizes the prompt structure and adds context sections
# if the source doesn't already follow a structured format.

module RulepackTranslator
  module AgentToCursor
    def self.translate(content, args: {})
      pkgname = args[:pkgname] || 'unknown'
      pkgdesc = args[:pkgdesc] || ''

      clean = content.strip

      h1_match = clean.match(/^#\s+(.+)$/)
      title = h1_match ? h1_match[1].strip : titleize(pkgname)
      body = h1_match ? clean.sub(/^#\s+.+\n/, '').strip : clean

      sections = parse_sections(body)

      if sections.empty?
        build_cursor_agent(title, pkgdesc, body)
      else
        clean
      end
    end

    def self.build_cursor_agent(title, pkgdesc, body)
      lines = []
      lines << "# #{title}"
      lines << ''
      unless pkgdesc.to_s.strip.empty?
        lines << pkgdesc.strip.tr("\n", ' ')
        lines << ''
      end
      lines << body.strip
      lines << ''
      lines.join("\n")
    end

    def self.parse_sections(body)
      sections = {}
      current_heading = nil
      current_lines = []

      body.each_line do |line|
        if line =~ /^##\s+(.+)$/
          sections[current_heading] = current_lines.join("\n").strip if current_heading
          current_heading = Regexp.last_match(1).strip
          current_lines = []
        else
          current_lines << line.chomp
        end
      end

      sections[current_heading] = current_lines.join("\n").strip if current_heading
      sections
    end

    def self.titleize(pkgname)
      pkgname.tr('-', ' ').split.map(&:capitalize).join(' ')
    end
  end
end
