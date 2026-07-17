# frozen_string_literal: true

module RulepackTranslator
  module NormalizeMarkdown
    def self.translate(content, args: {})
      # Strip trailing whitespace on each line, replace tabs with spaces
      clean = content.dup

      # Normalize windows newlines
      clean.gsub!(/\r\n/, "\n")

      clean.gsub!(/\t+/, ' ')
      clean.gsub!(/[ \t]+$/, '')

      # Max out at 2 newlines (1 blank line)
      clean.gsub!(/\n{3,}/, "\n\n")

      # Strip trailing empty lines (preserve leading)
      clean.sub!(/\n+\z/, '')

      "#{clean}\n"
    end
  end
end
