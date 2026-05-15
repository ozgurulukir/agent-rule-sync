#!/usr/bin/env ruby
# frozen_string_literal: true

# Aggregate skills for skill-based agents
# Reads built skill fragments from BUILD_DIR and combines them with common/agent-specific skills
# Output: BUILD_DIR/<agent>/skills/vendor/<agent>.md

require 'yaml'
require 'pathname'
require 'fileutils'

SSOT_ROOT = Pathname.new(__dir__).expand_path
BUILD_DIR = SSOT_ROOT.join('build')
INDEX_PATH = SSOT_ROOT.join('index.yaml')
SKILLS_DIR = SSOT_ROOT.join('skills')
REGISTRY_PATH = SSOT_ROOT.join('registry/platforms.yaml')

# ─── Load data ─────────────────────────────────────────────────────────────────

unless INDEX_PATH.exist?
  abort "❌ Index not found: #{INDEX_PATH}. Run `ruby ssot/build.rb` first."
end

# Load index with symbolize_names: true to match index.yaml (symbol keys)
# Load index and registry with symbol keys
index = YAML.safe_load(INDEX_PATH.read, permitted_classes: [Symbol], symbolize_names: true)
platforms = YAML.safe_load(REGISTRY_PATH.read, permitted_classes: [Symbol], symbolize_names: true)

# Identify skill-based agents
skill_agents = platforms.select { |id, cfg| cfg[:type] == 'skill' }.keys

if skill_agents.empty?
  puts "ℹ️ No skill-based agents configured in registry."
  exit 0
end

puts "🔧 Aggregating vendor skills for: #{skill_agents.join(', ')}\n"

# ─── Process each skill agent ──────────────────────────────────────────────────

skill_agents.each do |agent_id|
  platform_cfg = platforms[agent_id]
  puts "Generating vendor skill for #{agent_id} (#{platform_cfg[:display_name]})..."

  content_parts = []

  # Header: optional inline header from platform config or agent-specific header file
  if platform_cfg[:vendor_header]
    content_parts << platform_cfg[:vendor_header]
    puts "  ✓ vendor header (from registry)"
  else
    header_file = SKILLS_DIR.join('agent-specific', agent_id.to_s, 'header.md')
    if header_file.exist?
      content_parts << header_file.read
      puts "  ✓ header from #{header_file.relative_path_from(SSOT_ROOT)}"
    end
  end
  
  # ─── Collect skill fragments from built packages ────────────────────────────
  # These are the rule/skill packages that target this agent with format 'skill'
  rule_skills = []
  
   index[:packages].each do |pkgname, pkgdata|
     # Check if this package has a built artifact for this agent
     built_checksum = pkgdata[:checksums] && pkgdata[:checksums][:built] && pkgdata[:checksums][:built][agent_id.to_s]
     next unless built_checksum

     # Find PKGBUILD to get target details
      pkgbuild_path = SSOT_ROOT.join('packages', pkgname.to_s, 'PKGBUILD')
     next unless pkgbuild_path.exist?

     pkgbuild = YAML.safe_load(pkgbuild_path.read, permitted_classes: [Symbol], symbolize_names: true)
     targets = pkgbuild[:targets]
     targets = [targets] unless targets.is_a?(Array)

     targets.each do |tgt|
       next unless tgt[:platform] == agent_id.to_s
       next unless tgt[:format] == 'skill'
       next unless tgt[:output]  # must have output

       fragment_path = BUILD_DIR.join(agent_id.to_s, tgt[:output])
       if fragment_path.exist?
         # Determine order: from pkgdata order if available (from index) or from pkgbuild?
         order = pkgdata[:order] || 0
         rule_skills << { pkgname: pkgname, order: order, path: fragment_path }
       else
         warn "  ⚠ Built artifact missing: #{fragment_path}"
       end
     end
   end
  
  # Sort by order (lower first)
  rule_skills.sort_by! { |r| r[:order] }
  
  rule_skills.each do |skill|
    content = skill[:path].read
    content_parts << content
    puts "  ✓ rule fragment: #{skill[:pkgname]} (#{skill[:path].basename})"
  end
  
  # ─── Include common skills ───────────────────────────────────────────────────
  common_skills_dir = SKILLS_DIR.join('common')
  if common_skills_dir.exist?
    common_files = Dir.glob(common_skills_dir.join('*.md')).sort
    common_files.each do |skill_file|
      content_parts << File.read(skill_file)
      puts "  ✓ common skill: #{Pathname.new(skill_file).basename}"
    end
  end
  
  # ─── Include agent-specific skills ──────────────────────────────────────────
  agent_skills_dir = SKILLS_DIR.join('agent-specific', agent_id.to_s)
  if agent_skills_dir.exist?
    agent_files = Dir.glob(agent_skills_dir.join('*.md')).sort
    agent_files.each do |skill_file|
      content_parts << File.read(skill_file)
      puts "  ✓ agent-specific skill: #{Pathname.new(skill_file).basename}"
    end
  end
  
  # ─── Combine and write vendor skill ─────────────────────────────────────────
  final_content = content_parts.join("\n\n---\n\n")
  
  # Determine output path: BUILD_DIR/<agent>/skills/vendor/<agent>.md
  vendor_dir = BUILD_DIR.join(agent_id.to_s, 'skills', 'vendor')
  vendor_dir.mkpath
  vendor_file = vendor_dir.join("#{agent_id}.md")
  
  vendor_file.write(final_content)
  puts "  🎯 Vendor skill written: #{vendor_file.relative_path_from(SSOT_ROOT)}\n"
end

puts "✅ Vendor skill aggregation complete for #{skill_agents.size} agent(s)."
