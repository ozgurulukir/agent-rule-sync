# frozen_string_literal: true

class Translator
  def self.translate(content, _args: {})
    clean = content.sub(/\A---\s*\n.*?\n---\s*\n/m, '').strip

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
