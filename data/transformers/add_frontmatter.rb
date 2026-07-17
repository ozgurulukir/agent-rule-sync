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

      # Look at only the beginning of the file to be O(1) and preserve original behavior
      # which takes the first ATX heading or first non-empty line
      first_block = body[0, 500] || '' # Read up to 500 chars

      if first_block =~ /\A\s*#+\s+(.+?)(?:\r?\n|$)/
        return Regexp.last_match(1).strip
      elsif first_block =~ /\A\s*([^\s#].*?)(?:\r?\n|$)/
        return Regexp.last_match(1).strip
      end

      pkgname.tr('-', ' ').split.map(&:capitalize).join(' ')
    end

    def self.transform(content, pkgname: nil)
      pkgname = pkgname.to_s

      # Leave existing frontmatter intact
      return content if content.start_with?('---')

      description = case pkgname
                    when /-skill$/
                      pkgname.sub(/-skill$/, '').tr('-', ' ')
                    else
                      pkgname.tr('-', ' ')
                    end
                    .split.map(&:capitalize).join(' ')
      tags = [pkgname.gsub(/-/, '_')]

      # We must assign it back to the original pkgname fallback
      # if we want to drop the title so rubocop doesn't complain
      frontmatter = { 'name' => pkgname, 'description' => description, 'tags' => tags }.to_yaml

      "#{frontmatter}#{content}"
    end
  end
end
