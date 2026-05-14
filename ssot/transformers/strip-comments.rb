#!/usr/bin/env ruby
# frozen_string_literal: true

# Custom transformer: Strip HTML comments and empty lines
# Usage: transformer: custom:transformers/strip-comments.rb

class Transform
  def self.transform(content, pkgname:)
    # Remove HTML comments (<!-- ... -->)
    result = content.gsub(/<!--.*?-->/m, '')

    # Remove empty lines at the beginning
    result = result.sub(/\A\n+/, '')

    # Normalize multiple blank lines to max 2
    result = result.gsub(/\n{3,}/, "\n\n")

    result
  end
end
