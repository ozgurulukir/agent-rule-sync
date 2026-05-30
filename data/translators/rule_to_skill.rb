# frozen_string_literal: true

require 'set'

# Rule-to-Skill Translator
# Converts a flat rule file into a single-file skill format.
#
# INPUT  (rule format):  Flat markdown — may have ## sections, may not
# OUTPUT (skill format): "# <Title>" + structured body with
#                         ## Overview, ## Capabilities, ## Usage (if applicable)
#
# Behavior:
#   1. Extracts title from H1 or derives from pkgname
#   2. Analyzes existing sections and maps them to skill sections:
#      - Overview ← Rationale | Overview | first paragraph
#      - Capabilities ← Constraints | Capabilities | Content | Rules
#      - Usage ← Strategy | Examples | Usage | Implementation | Guidelines
#   3. Unmapped sections preserved in original order
#   4. If source has no ## sections, generates all three skill sections
#      from the raw content

module RulepackTranslator
  class Impl
    OVERVIEW_ALIASES = %w[Rationale Overview Context Background Purpose].freeze
    CAPABILITY_ALIASES = %w[Constraints Capabilities Content Rules Requirements].freeze
    USAGE_ALIASES = %w[Strategy Examples Usage Implementation Guidelines Instructions].freeze

    def self.translate(content, args: {})
      pkgname = args[:pkgname] || 'unknown'

      clean = content.strip
      h1_match = clean.match(/^#\s+(.+)$/)
      title = h1_match ? h1_match[1].strip : titleize(pkgname)
      body = h1_match ? clean.sub(/^#\s+.+\n/, '').strip : clean

      sections = parse_sections(body)

      if sections.empty?
        build_skill_from_flat(title, body)
      else
        build_skill_from_sections(title, sections)
      end
    end

    def self.build_skill_from_sections(title, sections)
      lines = []
      lines << "# #{title}"
      lines << ''

      mapped = Set.new

      overview = find_section(sections, OVERVIEW_ALIASES)
      if overview
        lines << '## Overview'
        lines << ''
        lines << overview.strip
        lines << ''
        mapped.merge(OVERVIEW_ALIASES & sections.keys)
      end

      capabilities = find_section(sections, CAPABILITY_ALIASES)
      if capabilities
        lines << '## Capabilities'
        lines << ''
        lines << capabilities.strip
        lines << ''
        mapped.merge(CAPABILITY_ALIASES & sections.keys)
      end

      usage = find_section(sections, USAGE_ALIASES)
      if usage
        lines << '## Usage'
        lines << ''
        lines << usage.strip
        lines << ''
        mapped.merge(USAGE_ALIASES & sections.keys)
      end

      sections.each do |heading, text|
        next if mapped.include?(heading)

        lines << "## #{heading}"
        lines << ''
        lines << text.strip
        lines << ''
      end

      lines.join("\n")
    end

    def self.build_skill_from_flat(title, body)
      lines = []
      lines << "# #{title}"
      lines << ''

      paragraphs = split_paragraphs(body)

      first = paragraphs.first
      if first
        lines << '## Overview'
        lines << ''
        lines << first.strip
        lines << ''
      end

      bullet_items = extract_bullet_items(body)
      if bullet_items.any?
        lines << '## Capabilities'
        lines << ''
        lines << bullet_items.join("\n")
        lines << ''
      elsif paragraphs.size > 1
        lines << '## Capabilities'
        lines << ''
        lines << paragraphs[1..].join("\n\n").strip
        lines << ''
      end

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

    def self.find_section(sections, aliases)
      aliases.each do |name|
        return sections[name] if sections.key?(name)
      end
      nil
    end

    def self.split_paragraphs(text)
      text.split(/\n{2,}/).reject(&:strip.empty?)
    end

    def self.extract_bullet_items(text)
      items = []
      text.each_line do |line|
        items << line.rstrip if line =~ /^[-*+]\s+/
      end
      items
    end

    def self.titleize(pkgname)
      pkgname.tr('-', ' ').split.map(&:capitalize).join(' ')
    end
  end
end
