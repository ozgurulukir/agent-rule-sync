# frozen_string_literal: true

module RulepackTranslator
  class Impl
    def self.translate(content, _args: {})
      clean = content.strip

      lines = clean.each_line.map do |line|
        if line =~ /^###\s+(.+)$/
          "## #{Regexp.last_match(1)}"
        else
          line.rstrip
        end
      end

      "#{lines.join("\n")}\n"
    end
  end
end
