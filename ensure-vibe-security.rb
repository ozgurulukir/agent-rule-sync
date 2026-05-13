#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

schema = YAML.load_file('ssot/schema.yaml')

# Add vibe-security source (if not exists)
schema['sources'] ||= {}
unless schema['sources'].key?('vibe-security')
  schema['sources']['vibe-security'] = {
    'platform' => 'generic',
    'type' => 'url',
    'base_url' => 'https://github.com/raroque/vibe-security-skill/raw/main/',
    'default_transformer' => 'copy'
  }
end

# Add vibe-security rule (if not exists)
rules = schema['rules'] || []
unless rules.any? { |r| r['id'] == 'vibe-security' }
  # Find max order
  max_order = rules.map { |r| r['order'] || 0 }.max || 0
  vibe_rule = {
    'id' => 'vibe-security',
    'title' => 'Vibe Security Skill',
    'order' => max_order + 1,
    'filename' => 'vibe-security.md',
    'source' => 'vibe-security',
    'upstream_path' => 'vibe-security/SKILL.md',
    'transformer' => 'copy'
  }
  rules << vibe_rule
  schema['rules'] = rules
end

File.write('ssot/schema.yaml', schema.to_yaml)
puts "✅ Ensured vibe-security source and rule exist"
