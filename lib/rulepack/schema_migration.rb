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
      # A hand-edited or future index must not be silently re-stamped to the
      # current version: every command now migrates on load AND saves after,
      # so downgrading here would rewrite the user's state behind their back.
      unless v.is_a?(Numeric)
        raise Rulepack::StateError,
              "Installed index has a non-numeric schema version (#{v.inspect}). " \
              'Fix or remove the :version field in data/index.yaml.'
      end
      if v > CURRENT_VERSION
        raise Rulepack::StateError,
              "Installed index schema version #{v} is newer than this Rulepack supports (#{CURRENT_VERSION}). " \
              'Upgrade Rulepack to work with this index.'
      end
      while v < CURRENT_VERSION
        case v
        when 1.0 then migrate_1_to_2!(index); v = 2.0
        when 2.0 then migrate_2_to_3!(index); v = 3.0
        else raise Rulepack::StateError, "Unknown schema version: #{v}"
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
      # Fresh build indexes always carry :pkg_type (BuildRecord writes it);
      # derive_pkg_type is only a fallback for pre-3.0 installed indexes.
      index[:packages]&.each_value do |pkg_idx|
        pkg_idx[:pkg_type] ||= derive_pkg_type(pkg_idx)
      end
    end

    def derive_pkg_type(pkg_idx)
      targets = pkg_idx[:targets] || []
      formats = targets.map { |t| t[:format] }.compact.uniq
      return 'rule' if formats.empty?

      # A skill-bundle-only package is classified as 'skill'; an agent-only
      # package is classified as 'agent'. Any mix of formats is 'hybrid'.
      if formats.include?('skill-bundle') || formats.include?('agent')
        return 'hybrid' if formats.size > 1
        return 'agent' if formats.include?('agent')
        return 'skill'
      end

      'rule'
    end
  end
end
