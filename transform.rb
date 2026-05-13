#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'yaml'
require 'digest'
require 'net/http'
require 'uri'

REPO_ROOT = Pathname.new(__dir__).join('..').expand_path
SSOT_DIR = REPO_ROOT.join('ssot')
SCHEMA_PATH = SSOT_DIR.join('schema.yaml')
TRANSFORM_LOG = SSOT_DIR.join('transforms.log')

schema = YAML.load_file(SCHEMA_PATH)
sources = schema['sources'] || {}

source_by_id = sources # map: id → config

# Built-in transformers
BUILTIN_TRANSFORMERS = {
  'copy' => ->(content) { content },
  'strip-frontmatter' => ->(content) { content.sub(/\A---\s*\n.*?\n---\s*\n/m, '') }
}

# Helper: fetch URL following redirects
def fetch_url_with_redirects(url_str, max_redirects = 5)
  uri = URI.parse(url_str)
  max_redirects.times do
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 15) do |http|
      http.request_get(uri.request_uri)
    end

    case response
    when Net::HTTPSuccess
      return response.body
    when Net::HTTPRedirection
      uri = URI.parse(response['location'])
      next
    else
      raise "HTTP #{response.code}: #{response.message}"
    end
  end
  raise "Too many redirects for #{url_str}"
end

# Collect all entries (rules, docs, upstream skills)
entries = []

%w[rules docs].each do |section|
  next unless schema[section]
  schema[section].each do |entry|
    next unless entry['source'] && entry['upstream_path']
    entries << {
      type: section.sub('s', ''),
      id: entry['id'],
      filename: entry['filename'],
      source_id: entry['source'],
      upstream_path: entry['upstream_path'],
      transformer: entry['transformer']
    }
  end
end

if schema['skills'] && schema['skills']['upstream']
  schema['skills']['upstream'].each do |skill_id, entry|
    next unless entry['source'] && entry['upstream_path']
    entries << {
      type: 'skill',
      id: skill_id,
      filename: "#{skill_id}.md",
      source_id: entry['source'],
      upstream_path: entry['upstream_path'],
      transformer: entry['transformer']
    }
  end
end

puts "Transform: #{entries.size} entries to process"
puts ""

transformed = []
skipped = []
errors = []

# ─── Transform each entry to SSoT ──────────────────────────────────────────
entries.each do |entry|
  source_cfg = source_by_id[entry[:source_id]]
  unless source_cfg
    puts "  #{entry[:id]}: unknown source '#{entry[:source_id]}'"
    errors << entry[:id]
    next
  end

  # Resolve upstream content based on source type
  content = nil
  case source_cfg['type']
  when 'local', 'local-path'
    source_root = Pathname.new(source_cfg['path']).expand_path
    upstream_file = source_root.join(entry[:upstream_path])
    unless upstream_file.exist?
      puts "  #{entry[:id]}: upstream missing — #{entry[:upstream_path]} (in #{source_root})"
      errors << entry[:id]
      next
    end
    content = upstream_file.read
  when 'url'
    base_url = source_cfg['base_url']
    full_url = base_url + entry[:upstream_path]
    begin
      content = fetch_url_with_redirects(full_url)
    rescue => e
      puts "  #{entry[:id]}: fetch failed — #{e.message}"
      errors << entry[:id]
      next
    end
  else
    puts "  #{entry[:id]}: unknown source type '#{source_cfg['type']}'"
    errors << entry[:id]
    next
  end

  # Determine transformer: entry override → source default → copy
  transformer_name = entry[:transformer] || source_cfg['default_transformer'] || 'copy'

  if BUILTIN_TRANSFORMERS.key?(transformer_name)
    content = BUILTIN_TRANSFORMERS[transformer_name].call(content)
    puts "  #{entry[:filename]} → #{transformer_name}"
    transformed << entry[:id]
  else
    # Custom transformer script (LLM or hand-written)
    transform_script = REPO_ROOT.join(transformer_name)
    if transform_script.exist?
      require_relative transform_script.relative_path_from(REPO_ROOT).to_s.delete_suffix('.rb')
      transformer_class = Object.const_get('Transform')
      transformer = transformer_class.new(
        source_file: nil,
        entry: entry
      )
      content = transformer.transform
      puts "  #{entry[:filename]} → #{transformer_name}"
      transformed << entry[:id]
    else
      warn "  #{entry[:id]}: transform script not found — #{transformer_name}"
      errors << entry[:id]
      next
    end
  end

  # Determine target path in SSoT
  case entry[:type]
  when 'rule'
    target = SSOT_DIR.join('rules', entry[:filename])
  when 'doc'
    target = SSOT_DIR.join('docs', entry[:filename])
  when 'skill'
    target = SSOT_DIR.join('skills', entry[:filename])
  end
  target.dirname.mkpath
  target.write(content)
end

# ─── Log ─────────────────────────────────────────────────────────────────────
log_entry = {
  'timestamp' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
  'transformed' => transformed,
  'skipped' => skipped,
  'errors' => errors
}
TRANSFORM_LOG.open('a') { |f| f.puts log_entry.to_yaml + "---\n" }

puts ""
if errors.empty?
  puts "✅ Transform complete: #{transformed.size} transformed, #{skipped.size} skipped"
else
  puts "⚠️  Transform complete with #{errors.size} errors:"
  errors.each { |e| puts "   - #{e}" }
end
puts "   Log: #{TRANSFORM_LOG}"
