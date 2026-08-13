# frozen_string_literal: true

# Immutable value object for a Rulepack build target.
#
# Represents one (platform, format, output) tuple within a package's targets.
# Use .from_hash to construct; #to_h for serialization.
module Rulepack
  class Target < Data.define(
    :platform, :format, :output, :install, :transformer, :translate, :agent_config
  )
    # rubocop:disable Lint/StructNewOverride

    VALID_FORMATS = %w[directory import skill skill-bundle agent].freeze

    def self.from_hash(hash)
      new(
        platform:      hash[:platform].to_s,
        format:        hash[:format],
        output:        hash[:output],
        install:       hash[:install],
        transformer:   hash[:transformer],
        translate:     hash[:translate],
        agent_config:  hash[:agent_config]
      )
    end

    def to_h
      h = { platform: platform, format: format, output: output }
      h[:install] = install if install
      h[:transformer] = transformer if transformer
      h[:translate] = translate if translate
      h[:agent_config] = agent_config if agent_config
      h
    end

    # ── Predicates ──────────────────────────────────────────────────────────

    def skill_bundle? = format == 'skill-bundle'
    def agent?        = format == 'agent'
    def directory?    = format == 'directory'
    def import?       = format == 'import'
    def skill_format? = format == 'skill'
  end
end
