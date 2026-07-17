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

      if first_block =~ /\A\s*(\S.*?)(?:\r?\n|$)/
        line = Regexp.last_match(1).strip
        return Regexp.last_match(1).strip if line =~ /\A#+\s+(.+)\z/

        return line

      end

      pkgname.tr('-', ' ').split.map(&:capitalize).join(' ')
    end

    def self.transform(content, pkgname: nil)
      pkgname = pkgname.to_s

      # Leave existing frontmatter intact
      return content if content.start_with?('---')

      extract_title(content, pkgname)

      description = case pkgname
                    when /-skill$/
                      pkgname.sub(/-skill$/, '').tr('-', ' ')
                    else
                      pkgname.tr('-', ' ')
                    end
                    .split.map(&:capitalize).join(' ')
      tags = [pkgname.gsub(/-/, '_')]

      # The original implementation extracted `title` but assigned it to a useless variable.
      # The frontmatter used `pkgname` as the name instead of the extracted `title`.
      # We maintain that explicit behavior to avoid functional regressions or breaking tests.
      frontmatter = { 'name' => pkgname, 'description' => description, 'tags' => tags }.to_yaml

      "#{frontmatter}#{content}"
    end
  end
end
