#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'fileutils'
require 'time'
require 'json'

REPO_ROOT = Pathname.new(__dir__).join('..').expand_path
SSOT_DIR = REPO_ROOT.join('ssot')
SCHEMA_PATH = SSOT_DIR.join('schema.yaml')
INDEX_PATH = SSOT_DIR.join('INDEX.md')
TRANSFORM_LOG = SSOT_DIR.join('transforms.log')

schema = YAML.load_file(SCHEMA_PATH)

# ─── Collect all entries ────────────────────────────────────────────────────
rules = (schema['rules'] || []).map do |r|
  {
    type: 'rule',
    id: r['id'],
    title: r['title'],
    order: r['order'],
    filename: r['filename'],
    source: r['source'],
    upstream_path: r['upstream_path'],
    transformer: r['transformer']
  }
end

docs = (schema['docs'] || []).map do |d|
  {
    type: 'doc',
    id: d['id'],
    filename: d['filename'],
    source: d['source'],
    upstream_path: d['upstream_path'],
    transformer: d['transformer']
  }
end

skills_common = (schema['skills'] && schema['skills']['common']) || []
skills_agent = {}
if schema['skills'] && schema['skills']['agent-specific']
  schema['skills']['agent-specific'].each do |agent, skills|
    skills_agent[agent] = skills || []
  end
end
skills_upstream = {}
if schema['skills'] && schema['skills']['upstream']
  schema['skills']['upstream'].each do |skill_id, entry|
    skills_upstream[skill_id] = {
      source: entry['source'],
      upstream_path: entry['upstream_path'],
      transformer: entry['transformer']
    }
  end
end

agents = (schema['agents'] || {}).map do |name, cfg|
  {
    name: name,
    display_name: cfg['display_name'],
    format: cfg['format'],
    platform: cfg['platform'],
    path: cfg['path'],
    rules: cfg['rules'],
    skills: cfg['skills'] || [],
    docs: cfg['docs'] || []
  }
end

sources = (schema['sources'] || {}).map do |id, cfg|
  {
    id: id,
    platform: cfg['platform'],
    type: cfg['type'],
    path: cfg['path'],
    default_transformer: cfg['default_transformer']
  }
end

platforms = (schema['platforms'] || {}).map do |id, cfg|
  {
    id: id,
    format: cfg['format'],
    rules_dir: cfg['rules_dir'],
    skills_dir: cfg['skills_dir'],
    docs_dir: cfg['docs_dir'],
    transforms_from: cfg['transforms'] && cfg['transforms']['from'],
    transforms_custom: cfg['transforms'] && cfg['transforms']['custom']
  }
end

# ─── Generate Markdown index ────────────────────────────────────────────────
md = +"# SSoT Index\n\n"
md << "**Generated:** #{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
md << "**Schema version:** #{schema['version']}\n\n"

md << "## Sources\n\n"
md << "| ID | Platform | Type | Path | Default Transformer |\n"
md << "|----|----------|------|------|---------------------|\n"
sources.each do |s|
  md << "| `#{s[:id]}` | #{s[:platform]} | #{s[:type]} | `#{s[:path]}` | #{s[:default_transformer]} |\n"
end

md << "\n## Platforms\n\n"
md << "| ID | Format | Rules Dir | Skills Dir | Docs Dir | Transforms From | Custom Transform |\n"
md << "|----|--------|-----------|------------|----------|-----------------|------------------|\n"
platforms.each do |p|
  md << "| `#{p[:id]}` | #{p[:format]} | `#{p[:rules_dir]}` | `#{p[:skills_dir]}` | `#{p[:docs_dir]}` | #{p[:transforms_from]} | #{p[:transforms_custom] || '—'} |\n"
end

md << "\n## Rules (#{rules.size})\n\n"
md << "| Order | ID | Title | Source | Upstream | Transformer |\n"
md << "|-------|----|-------|--------|----------|-------------|\n"
rules.sort_by { |r| r[:order] }.each do |r|
  md << "| #{r[:order]} | `#{r[:id]}` | #{r[:title]} | #{r[:source]} | `#{r[:upstream_path]}` | #{r[:transformer] || '—'} |\n"
end

md << "\n## Docs (#{docs.size})\n\n"
md << "| ID | Filename | Source | Upstream | Transformer |\n"
md << "|----|----------|--------|----------|-------------|\n"
docs.each do |d|
  md << "| `#{d[:id]}` | #{d[:filename]} | #{d[:source]} | `#{d[:upstream_path]}` | #{d[:transformer] || '—'} |\n"
end

md << "\n## Skills\n\n"
md << "### Common (#{skills_common.size})\n\n"
unless skills_common.empty?
  md << "- #{skills_common.join(', ')}\n"
end

md << "\n### Agent-Specific\n\n"
skills_agent.each do |agent, skills|
  md << "#### #{agent}\n\n"
  if skills.empty?
    md << "*None*\n"
  else
    md << "- #{skills.join(', ')}\n"
  end
  md << "\n"
end

md << "\n### Upstream (#{skills_upstream.size})\n\n"
md << "| ID | Source | Upstream | Transformer |\n"
md << "|----|--------|----------|-------------|\n"
skills_upstream.sort_by { |id, _| id }.each do |id, s|
  md << "| `#{id}` | #{s[:source]} | `#{s[:upstream_path]}` | #{s[:transformer] || '—'} |\n"
end

md << "\n## Agents (#{agents.size})\n\n"
md << "| Name | Display | Platform | Format | Path | Rules | Skills | Docs |\n"
md << "|------|---------|----------|--------|------|-------|--------|------|\n"
agents.each do |a|
  rules_list = if a[:rules] == 'all' then 'all' else a[:rules].join(', ') end
  skills_list = a[:skills].join(', ')
  docs_list = a[:docs].join(', ')
  md << "| `#{a[:name]}` | #{a[:display_name]} | #{a[:platform]} | #{a[:format]} | `#{a[:path]}` | #{rules_list} | #{skills_list} | #{docs_list} |\n"
end

md << "\n## Transform Log\n\n"
  if TRANSFORM_LOG.exist?
    log_entries = []
    File.read(TRANSFORM_LOG).split('---').each do |chunk|
      chunk = chunk.strip
      next if chunk.empty?
      begin
        entry = YAML.safe_load(chunk)
        log_entries << entry if entry
      rescue
        # skip malformed
      end
    end
    latest = log_entries.last
    if latest
      md << "**Last transform:** #{latest['timestamp']}\n\n"
      md << "- Transformed: #{latest['transformed'].size}\n"
      md << "- Skipped: #{latest['skipped'].size}\n"
      md << "- Errors: #{latest['errors'].size}\n"
    else
      md << "*No transform log found.*\n"
    end
  else
    md << "*No transform log found.*\n"
  end

md << "\n---\n*This index is auto-generated from `ssot/schema.yaml`. Do not edit manually.*\n"

# ─── Write index ─────────────────────────────────────────────────────────────
INDEX_PATH.write(md)
puts "✅ Index generated: #{INDEX_PATH}"
puts "   Rules: #{rules.size}, Docs: #{docs.size}, Skills (upstream): #{skills_upstream.size}, Agents: #{agents.size}"

# ─── Also generate JSON for programmatic access ─────────────────────────────
json_path = SSOT_DIR.join('index.json')
json_data = {
  version: schema['version'],
  generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
  sources: sources,
  platforms: platforms,
  rules: rules,
  docs: docs,
  skills: {
    common: skills_common,
    agent_specific: skills_agent,
    upstream: skills_upstream
  },
  agents: agents
}
json_path.write(JSON.pretty_generate(json_data))
puts "✅ JSON index: #{json_path}"
