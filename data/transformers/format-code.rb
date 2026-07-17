# frozen_string_literal: true

# Custom transformer: Ensure code blocks have language identifiers
# Auto-detects language from heuristics (Ruby, Python, JavaScript, Go, Bash, TypeScript, Rust)
# Usage: transformer: custom:transformers/format-code.rb

module RulepackTransformer
  module FormatCode
    LANGUAGE_KEYWORDS = {
      'ruby' => %w[def class module require puts gets end do yield binding],
      'python' => %w[def class import from print return elif lambda yield self],
      'javascript' => %w[const let function console return export import async await],
      'typescript' => %w[interface type enum namespace declare readonly as extends implements],
      'go' => %w[func package import fmt return defer go chan select range],
      'bash' => %w[echo fi done esac then elif export source readonly local],
      'rust' => %w[fn let mut pub impl trait use mod crate async unsafe],
      'sql' => %w[SELECT FROM WHERE INSERT UPDATE DELETE CREATE TABLE ALTER],
      'yaml' => %w[--- true false null],
      'json' => %w[true false null]
    }.freeze

    def self.transform(content, _pkgname:)
      lines = content.lines
      result = []
      in_code_block = false
      block_content = []
      opening_fence = nil

      lines.each do |line|
        if line.start_with?('```')
          if in_code_block
            processed_lines = process_code_block(opening_fence, block_content)
            result.concat(processed_lines)
            result << line
            block_content = []
            opening_fence = nil
            in_code_block = false
          else
            opening_fence = line
            in_code_block = true
          end
        elsif in_code_block
          block_content << line
        else
          result << line
        end
      end

      result.concat(process_code_block(opening_fence, block_content)) if in_code_block && opening_fence

      result.join
    end

    def self.process_code_block(opening_fence, content_lines)
      stripped = opening_fence.strip
      return [opening_fence] + content_lines if stripped =~ /^```(\w+)$/

      content = content_lines.join
      tag = detect_language(content)
      if tag.empty?
        [opening_fence] + content_lines
      else
        ["```#{tag}\n"] + content_lines
      end
    end

    def self.detect_language(content)
      scores = LANGUAGE_KEYWORDS.map do |lang, keywords|
        score = keywords.count { |kw| content.include?(kw) }
        [lang, score]
      end

      best = scores.max_by(&:last)
      best && best.last >= 2 ? best.first : ''
    end
  end
end
