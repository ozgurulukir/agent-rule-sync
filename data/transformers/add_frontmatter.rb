# frozen_string_literal: true

# OpenCode skill frontmatter injector.
# Adds YAML frontmatter to SKILL.md files if missing.
#
# Transformer API (class method):
#   RulepackTransformer::AddFrontmatter.transform(content, pkgname: nil) → transformed content string

require 'yaml'

module RulepackTransformer
  module AddFrontmatter
    # Return content without any leading YAML frontmatter block
    def self.strip_frontmatter(content)
      return content unless content.start_with?('---')
      end_marker = "\n---\n"
      idx = content.index(end_marker, 3)
      idx ? content[(idx + 4)..] : ''
    end

    # Extract title: first ATX heading, then first non-empty line, then fallback
    def self.extract_title(content, pkgname)
      body = strip_frontmatter(content)
      body.each_line do |line|
        stripped = line.strip
        next if stripped.empty?
        if stripped =~ /^#+\s+(.+)$/
          return Regexp.last_match(1).strip
        end
        return stripped
      end
      pkgname.tr('-', ' ').split.map(&:capitalize).join(' ')
    end

    def self.transform(content, pkgname: nil)
      pkgname = pkgname.to_s

      # Leave existing frontmatter intact
      return content if content.start_with?('---')

      title = extract_title(content, pkgname)
      description = case pkgname
                    when /-skill$/
                      pkgname.sub(/-skill$/, '').tr('-', ' ')
                    else
                      pkgname.tr('-', ' ')
                    end
                    .split.map(&:capitalize).join(' ')
      tags = [pkgname.gsub(/-/, '_')]

      frontmatter = { 'name' => pkgname, 'description' => description, 'tags' => tags }.to_yaml

      "#{frontmatter}#{content}"
    end
  end
end
