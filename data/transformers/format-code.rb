#!/usr/bin/env ruby
# frozen_string_literal: true

# Custom transformer: Ensure code blocks have language identifiers
# Adds 'ruby' language tag to untagged code blocks that look like Ruby
# Usage: transformer: custom:transformers/format-code.rb

class Transform
  RUBY_KEYWORDS = %w[def class module if else elsif end require puts gets].freeze

  def self.transform(content, pkgname:)
    lines = content.lines
    result = []
    in_code_block = false
    block_content = []
    opening_fence = nil

    lines.each do |line|
      if line.start_with?('```')
        if in_code_block
          # Closing fence - process block
          processed_lines = process_code_block(opening_fence, block_content)
          result.concat(processed_lines)
          result << line
          block_content = []
          opening_fence = nil
          in_code_block = false
        else
          # Opening fence
          opening_fence = line
          in_code_block = true
        end
      elsif in_code_block
        block_content << line
      else
        result << line
      end
    end

    # Handle unclosed block (shouldn't happen in valid markdown)
    if in_code_block && opening_fence
      result.concat(process_code_block(opening_fence, block_content))
    end

    result.join
  end

  # opening_fence: the line with ```
  # content_lines: lines inside the code block
  def self.process_code_block(opening_fence, content_lines)
    # Check if opening fence already has a language tag
    if opening_fence.strip =~ /^```(\w+)$/
      # Already tagged, keep as-is
      return [opening_fence] + content_lines
    end

    # No tag, guess language
    content = content_lines.join
    tag = looks_like_ruby?(content) ? 'ruby' : ''
    if tag.empty?
      [opening_fence] + content_lines
    else
      ["```#{tag}\n"] + content_lines
    end
  end

  def self.looks_like_ruby?(content)
    # Simple heuristic: contains Ruby keywords
    RUBY_KEYWORDS.any? { |kw| content.include?(kw) }
  end
end
