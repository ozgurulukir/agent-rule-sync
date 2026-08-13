# frozen_string_literal: true

# Immutable value object for a Rulepack package descriptor.
#
# Wraps the raw PKGBUILD hash with typed accessors and predicates.
# Use .from_hash to construct from YAML-parsed data; #to_h for serialization.
module Rulepack
  class Package < Data.define(
    :pkgname, :pkgver, :pkgrel, :epoch, :pkgdesc, :pkg_type, :order,
    :arch, :source, :targets, :dependencies, :conflicts, :provides,
    :tags, :pkgver_func, :output
  )
    # rubocop:disable Lint/StructNewOverride

    VALID_TYPES = %w[rule skill skill-bundle agent hybrid].freeze

    def self.from_hash(hash)
      new(
        pkgname:       hash[:pkgname],
        pkgver:        hash[:pkgver],
        pkgrel:        hash.fetch(:pkgrel, 1),
        epoch:         hash.fetch(:epoch, 0),
        pkgdesc:       hash[:pkgdesc],
        pkg_type:      hash[:pkg_type],
        order:         hash.fetch(:order, 0),
        arch:          hash.fetch(:arch, 'any'),
        source:        hash[:source] || [],
        targets:       hash[:targets],
        dependencies:  hash.fetch(:dependencies, []),
        conflicts:     hash.fetch(:conflicts, []),
        provides:      hash.fetch(:provides, []),
        tags:          hash.fetch(:tags, []),
        pkgver_func:   hash[:pkgver_func],
        output:        hash[:output]
      )
    end

    def to_h
      h = {
        pkgname: pkgname, pkgver: pkgver, pkgrel: pkgrel, epoch: epoch,
        pkgdesc: pkgdesc, pkg_type: pkg_type, order: order, arch: arch,
        source: source, dependencies: dependencies, conflicts: conflicts,
        provides: provides, tags: tags
      }
      h[:targets] = targets if targets
      h[:pkgver_func] = pkgver_func if pkgver_func
      h[:output] = output if output
      h
    end

    # ── Predicates ──────────────────────────────────────────────────────────

    def rule?       = pkg_type == 'rule'
    def skill?      = pkg_type == 'skill'
    def skill_bundle? = pkg_type == 'skill-bundle'
    def agent?      = pkg_type == 'agent'
    def hybrid?     = pkg_type == 'hybrid'

    def source_is_dir?
      src = source.first
      src && src[:path]&.end_with?('/')
    end

    def source_basename
      src = source.first
      src ? File.basename(src[:path].to_s) : ''
    end
  end
end
