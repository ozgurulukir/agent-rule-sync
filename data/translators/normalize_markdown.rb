# frozen_string_literal: true

class Translator
  def self.translate(content, _args: {})
    lines = content.each_line.map do |line|
      line = line.gsub(/\t+/, ' ')
      line = line.gsub(/^[ \t]+$/, '')
      line.rstrip
    end

    result = []
    blank_count = 0
    lines.each do |line|
      if line.empty?
        blank_count += 1
        result << line if blank_count <= 1
      else
        blank_count = 0
        result << line
      end
    end

    result.pop while !result.empty? && result.last.empty?
    "#{result.join("\n")}\n"
  end
end
