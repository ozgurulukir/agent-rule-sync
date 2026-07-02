# frozen_string_literal: true

# Custom transformer: Add a title header to content
# Usage in PKGBUILD: transformer: custom:transformers/add-header.rb
# Extracts title from YAML frontmatter or first H1 heading.

module RulepackTransformer
  module AddHeader
    def self.transform(content, _pkgname:)
      clean = content.strip

      title = extract_title(clean)
      header = "# #{title}\n\n"
      body = strip_existing_h1(clean)

      "#{header}#{body}"
    end

    def self.extract_title(content)
      if content.start_with?('---')
        end_idx = content.index("\n---\n") || content.index("\n---")
        if end_idx
          frontmatter = content[3...end_idx].strip
          if frontmatter =~ /title:\s*(.+)/
            return Regexp.last_match(1).strip
          end
        end
      end

      h1 = content.match(/^#\s+(.+)$/)
      h1 ? h1[1].strip : 'Rule'
    end

    def self.strip_existing_h1(content)
      body = content.sub(/\A---\n.*?---\n*/m, '')
      body = body.sub(/^#\s+.+\n*/, '').strip
      body
    end
  end
end
