# frozen_string_literal: true

require 'pathname'

module Rulepack
  module Path
    module_function

    # Expand user home directory in path (~/...)
    def expand_user_path(path)
      path.start_with?('~') ? File.expand_path(path) : path
    end

    # Remove YAML frontmatter (--- ... ---) from content
    def strip_frontmatter(content)
      content.sub(/\A---\s*\n.*?\n---\s*\n/m, '')
    end
  end
end
