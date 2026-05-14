# Rule-to-Skill Translator
# Converts a flat rule file into a single-file skill format.
#
# INPUT  (rule format):  Flat markdown with ## sections, no H1 title
# OUTPUT (skill format): H1 title + "## Overview" + "## Capabilities" + "## Usage"
#
# Example:
#   Input:  "# Title\n## Constraints\n- item\n## Rationale\n..."
#   Output: "# Title\n\n## Overview\n\nTitle describes...\n\n## Capabilities\n\n- item\n\n## Usage\n\nApply this rule when..."

class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname] || 'unknown'

    # Strip any YAML frontmatter
    clean = content.sub(/\A---\s*\n.*?\n---\s*\n/m, '').strip

    # Extract H1 title (first # heading)
    h1_match = clean.match(/^#\s+(.+)$/)
    title = h1_match ? h1_match[1].strip : pkgname.tr('-', ' ').capitalize

    # Remove the H1 from content (we'll re-add it)
    body = h1_match ? clean.sub(/^#\s+.+\n/, '').strip : clean

    # Identify ## sections and their content
    sections = parse_sections(body)

    # Build skill structure
    lines = []
    lines << "# #{title}"
    lines << ""

    # Overview: use Rationale section if present, otherwise first paragraph
    if sections['Rationale'] || sections['Overview']
      overview = sections['Rationale'] || sections['Overview']
      lines << "## Overview"
      lines << ""
      lines << overview.strip
      lines << ""
    elsif first_para = extract_first_paragraph(body)
      lines << "## Overview"
      lines << ""
      lines << first_para
      lines << ""
    end

    # Capabilities: use Constraints or Content sections
    cap_section = sections['Constraints'] || sections['Capabilities'] || sections['Content']
    if cap_section
      lines << "## Capabilities"
      lines << ""
      lines << cap_section.strip
      lines << ""
    end

    # Usage: use Strategy, Examples, or Usage section
    usage_section = sections['Strategy'] || sections['Examples'] || sections['Usage'] || sections['Implementation']
    if usage_section
      lines << "## Usage"
      lines << ""
      lines << usage_section.strip
      lines << ""
    end

    # Append any remaining sections not already included
    included = %w[Overview Rationale Capabilities Constraints Content Usage Strategy Examples Implementation]
    sections.each do |heading, text|
      next if included.include?(heading)
      lines << "## #{heading}"
      lines << ""
      lines << text.strip
      lines << ""
    end

    lines.join("\n")
  end

  private

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
    first_section.split(/\n\n/).first&.strip
  end
end
