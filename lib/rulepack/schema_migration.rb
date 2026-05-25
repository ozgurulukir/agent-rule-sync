# frozen_string_literal: true

# Schema Migration Framework — data/index.yaml version upgrades.
#
# P-C: Schema Migration Framework (OPEN-ITEMS.md)
# Idempotent — safe to call on already-migrated data.

require 'yaml'

module Rulepack
  module SchemaMigration
    CURRENT_VERSION = 3.0

    module_function

    def migrate!(index)
      v = index[:version] || 1.0
      while v < CURRENT_VERSION
        case v
        when 1.0 then migrate_1_to_2!(index); v = 2.0
        when 2.0 then migrate_2_to_3!(index); v = 3.0
        else raise "Unknown schema version: #{v}"
        end
      end
      index[:version] = CURRENT_VERSION
    end

    # ─── 1.0 → 2.0 ────────────────────────────────────────────────────────────────
    # Add checksums.built field (per-platform build checksums).
    # Prior to 2.0 only checksums.source existed.

    def migrate_1_to_2!(index)
      index[:packages]&.each_value do |pkg_idx|
        checksums = pkg_idx[:checksums] || { source: pkg_idx[:source_sha256] }
        checksums[:built] ||= {}
        pkg_idx[:checksums] = checksums
      end
    end

    # ─── 2.0 → 3.0 ────────────────────────────────────────────────────────────────
    # Add pkg_type field (rule / skill / hybrid / agent).
    # Prior to 3.0 only pkg_type via targets; top-level field missing.
    # Also normalise any packages whose targets mix skill-bundle + file formats
    # into 'hybrid'.

    def migrate_2_to_3!(index)
      index[:packages]&.each_value do |pkg_idx|
        pkg_idx[:pkg_type] ||= derive_pkg_type(pkg_idx)
      end
    end

    def derive_pkg_type(pkg_idx)
      targets = pkg_idx[:targets] || []
      formats = targets.map { |t| t[:format] }.compact.uniq
      if formats.empty?
        'rule'
      elsif formats.include?('skill-bundle') || formats.include?('agent')
        formats.size > 1 ? 'hybrid' : 'skill'
      else
        'rule'
      end
    end
  end
end
