# frozen_string_literal: true

# Immutable value object for a Rulepack platform configuration.
#
# Wraps a platform registry entry with typed accessors and predicates.
# Use .from_hash to construct from YAML-parsed data; #to_h for serialization.
module Rulepack
  class Platform < Data.define(
    :id, :type, :base_path, :scope, :rules_dir, :rules_file, :skill_file,
    :skills_dir, :agents_dir, :format_profile, :rule_install, :skill_install,
    :vendor_header, :display_name, :config_file
  )
    # rubocop:disable Lint/StructNewOverride

    def self.from_hash(id, hash)
      new(
        id:             id.to_s,
        type:           hash[:type],
        base_path:      hash[:base_path],
        scope:          hash[:scope] || 'user',
        rules_dir:      hash[:rules_dir],
        rules_file:     hash[:rules_file],
        skill_file:     hash[:skill_file],
        skills_dir:     hash[:skills_dir],
        agents_dir:     hash[:agents_dir],
        format_profile: hash[:format_profile],
        rule_install:   hash[:rule_install],
        skill_install:  hash[:skill_install],
        vendor_header:  hash[:vendor_header],
        display_name:   hash[:display_name],
        config_file:    hash[:config_file]
      )
    end

    def to_h
      {
        type: type, base_path: base_path, scope: scope,
        rules_dir: rules_dir, rules_file: rules_file,
        skill_file: skill_file, skills_dir: skills_dir,
        agents_dir: agents_dir, format_profile: format_profile,
        rule_install: rule_install, skill_install: skill_install,
        vendor_header: vendor_header, display_name: display_name,
        config_file: config_file
      }.compact
    end

    # ── Predicates ──────────────────────────────────────────────────────────

    def project_scoped? = scope == 'project'
    def user_scoped?    = scope == 'user'
  end
end
