# frozen_string_literal: true

# Security utilities for Rulepack.
#
# Centralizes security-critical operations that were previously duplicated
# across build_per_pkg.rb, skill_bundle_lazy.rb, and install_execute.rb.

module Rulepack
  module Security
    module_function

    # Recursively remove all symlinks (files and dirs) under a tree.
    # Used after cp_r to ensure untrusted git/url sources cannot plant symlinks
    # that later File.write / File.read calls would follow out of the build dir.
    def strip_symlinks_in_tree(root, log_prefix: nil)
      return unless Dir.exist?(root)

      Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH).each do |entry|
        next if entry == root

        next unless File.symlink?(entry)

        File.unlink(entry)
        if log_prefix
          Rulepack::Common.log "    #{log_prefix} Removed untrusted symlink from tree: #{entry}"
        end
      end
    end
  end
end
