#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'yaml'

REPO_ROOT = Pathname.new(__dir__).join('..').expand_path
SSOT_DIR = REPO_ROOT.join('ssot')
RULES_DIR = SSOT_DIR.join('rules')
SKILLS_DIR = SSOT_DIR.join('skills')
VENDOR_DIR = SSOT_DIR.join('vendor')
VENDOR_SKILLS_DIR = SKILLS_DIR.join('vendor')

schema = YAML.load_file(SSOT_DIR.join('schema.yaml'))
FileUtils.mkdir_p(VENDOR_SKILLS_DIR)

# ─── PROCESS RULES (read-only from ssot/rules/) ─────────────────────────────
rule_contents = {}

if schema.key?('rules')
  schema['rules'].sort_by { |r| r['order'].to_i }.each do |rule|
    rule_id = rule['id']
    filename = rule['filename']
    source_file = RULES_DIR.join(filename)

    unless source_file.exist?
      warn "  ⚠ Rule missing: #{filename} (run 'make transform' to fetch/generate)"
      next
    end

    content = source_file.read
    # Strip YAML frontmatter if present (upstream files often have it)
    content = content.sub(/\A---\s*\n.*?\n---\s*\n/m, '')
    rule_contents[rule_id] = content
    puts "  ✓ rules/#{filename}"
  end
end

# ─── LOAD SKILL CONTENT ────────────────────────────────────────────────────
def load_skill_content(skill_id, schema, skills_dir, vendor_dir)
  custom_file = skills_dir.join("#{skill_id}.md")
  return File.read(custom_file) if File.exist?(custom_file)

  common_file = skills_dir.join('common', "#{skill_id}.md")
  return File.read(common_file) if File.exist?(common_file)

  if schema['skills'] && schema['skills']['upstream']
    upstream_config = schema['skills']['upstream'][skill_id]
    if upstream_config
      upstream_file = vendor_dir.join(upstream_config['filename'])
      return File.read(upstream_file) if upstream_file.exist?
    end
  end

  warn "Skill not found: #{skill_id}.md"
  nil
end

# ─── GENERATE VENDOR SKILLS ───────────────────────────────────────────────
schema['agents'].each do |agent_name, config|
  next unless config['format'] == 'skill'

  content_parts = []

  # Header: inline from schema, or first agent-specific skill
  if config['header'] && !config['header'].to_s.strip.empty?
    content_parts << config['header'].strip
  else
    header_skill = schema.dig('skills', 'agent-specific', agent_name)&.first
    if header_skill
      header_content = load_skill_content(header_skill, schema, SKILLS_DIR, VENDOR_DIR)
      content_parts << header_content if header_content
    end
  end

  # Rules (in order)
  schema['rules'].sort_by { |r| r['order'].to_i }.each do |rule|
    content = rule_contents[rule['id']]
    content_parts << content if content
  end

  # Agent-specific skills (skip the one used as header)
  agent_skills = schema.dig('skills', 'agent-specific', agent_name) || []
  header_skill_id = if config['header'] && !config['header'].to_s.strip.empty?
                      nil
                    else
                      agent_skills.first
                    end

  agent_skills.each do |skill_id|
    next if skill_id == header_skill_id
    skill_content = load_skill_content(skill_id, schema, SKILLS_DIR, VENDOR_DIR)
    content_parts << skill_content if skill_content
  end

  # Common skills
  if schema['skills'] && schema['skills']['common']
    schema['skills']['common'].each do |common_skill|
      common_content = load_skill_content(common_skill, schema, SKILLS_DIR, VENDOR_DIR)
      content_parts << common_content if common_content
    end
  end

  # Footer
  if config['footer'] && !config['footer'].to_s.strip.empty?
    content_parts << config['footer'].strip
  end

  final = content_parts.join("\n\n") + "\n"
  vendor_file = VENDOR_SKILLS_DIR.join("#{agent_name}.md")
  vendor_file.write(final)
  puts "  ✓ ssot/skills/vendor/#{agent_name}.md"
end

puts "\n✅ Vendor skills generated in ssot/skills/vendor/"
