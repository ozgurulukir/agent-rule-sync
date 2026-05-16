# frozen_string_literal: true

# Rule-to-Skill Translator
# Converts a flat rule file into a single-file skill format.
#
# INPUT  (rule format):  Flat markdown with ## sections, no H1 title
# OUTPUT (skill format): H1 title + "## Overview" + "## Capabilities" + "## Usage"
#
# Example:
#   Input:  "# Title\n## Constraints\n- item\n## Rationale\n..."
#   Output: "# Title\n\n## Overview\n\nTitle describes..." \
#          "\n\n## Capabilities\n\n- item\n\n## Usage\n\nApply this rule when..."

class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname] || 'unknown'

    clean = content.sub(/\A---\s*\n.*?\n---\s*\n/m, '').strip
    h1_match = clean.match(/^#\s+(.+)$/)
    title = h1_match ? h1_match[1].strip : pkgname.tr('-', ' ').capitalize
    body = h1_match ? clean.sub(/^#\s+.+\n/, '').strip : clean

    sections = parse_sections(body)
    build_skill(title, sections, body)
  end

  def self.build_skill(title, sections, body)
    lines = []
    lines << "# #{title}"
    lines << ''

    add_overview(lines, sections, body)
    add_capabilities(lines, sections)
    add_usage(lines, sections)
    add_remaining_sections(lines, sections)

    lines.join("\n")
  end

  def self.add_overview(lines, sections, body)
    overview = sections['Rationale'] || sections['Overview'] ||
               extract_first_paragraph(body)
    return unless overview

    lines << '## Overview'
    lines << ''
    lines << overview.strip
    lines << ''
  end

  def self.add_capabilities(lines, sections)
    cap = sections['Constraints'] || sections['Capabilities'] || sections['Content']
    return unless cap

    lines << '## Capabilities'
    lines << ''
    lines << cap.strip
    lines << ''
  end

  def self.add_usage(lines, sections)
    usage = sections['Strategy'] || sections['Examples'] ||
            sections['Usage'] || sections['Implementation']
    return unless usage

    lines << '## Usage'
    lines << ''
    lines << usage.strip
    lines << ''
  end

  def self.add_remaining_sections(lines, sections)
    included = %w[Overview Rationale Capabilities Constraints Content Usage Strategy Examples
                  Implementation]
    sections.each do |heading, text|
      next if included.include?(heading)

      lines << "## #{heading}"
      lines << ''
      lines << text.strip
      lines << ''
    end
  end

  def self.parse_sections(body)
    sections = {}
    current_heading = nil
    current_lines = []

    body.each_line do |line|
      if line =~ /^##\s+(.+)$/
        # Save previous section
        sections[current_heading] = current_lines.join("\n").strip if current_heading
        current_heading = Regexp.last_match(1).strip
        current_lines = []
      else
        current_lines << line.chomp
      end
    end

    # Save last section
    sections[current_heading] = current_lines.join("\n").strip if current_heading
    sections
  end

  def self.extract_first_paragraph(body)
    # Get first non-empty paragraph before any ## heading
    first_section = body.split(/^## /).first.to_s.strip
    # Get first paragraph (up to double newline)
    first_section.split("\n\n").first&.strip
  end
end
