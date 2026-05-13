#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'yaml'
require 'open-uri'
require 'digest'
require 'net/http'
require 'uri'

REPO_ROOT = Pathname.new(__dir__).join('..').expand_path
SSOT_DIR = REPO_ROOT.join('ssot')
VENDOR_DIR = SSOT_DIR.join('vendor')
SCHEMA_PATH = SSOT_DIR.join('schema.yaml')

FileUtils.mkdir_p(VENDOR_DIR)

# Helper: fetch URL following redirects
def fetch_url_with_redirects(url_str, max_redirects = 5)
  uri = URI.parse(url_str)
  last_response = nil

  max_redirects.times do
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 15) do |http|
      http.request_get(uri.request_uri)
    end

    case response
    when Net::HTTPSuccess
      return response.body
    when Net::HTTPRedirection
      location = response['location']
      uri = URI.parse(location)
      next
    else
      raise "HTTP #{response.code}: #{response.message}"
    end
  end

  raise "Too many redirects"
end

schema = YAML.load_file(SCHEMA_PATH)
sources = schema['sources'] || {}

puts "Fetching upstream sources..."
puts ""

changed = []
skipped = []
errors = []

# Collect all entries with upstream_path
entries = []

%w[rules docs].each do |section|
  next unless schema[section]
  schema[section].each do |entry|
    next unless entry['source'] && entry['upstream_path']
    entries << {
      type: section.sub('s', ''),
      id: entry['id'],
      source_id: entry['source'],
      upstream_path: entry['upstream_path'],
      filename: entry['filename'],
      current_sha: entry['sha256']
    }
  end
end

if schema['skills'] && schema['skills']['upstream']
  schema['skills']['upstream'].each do |skill_id, entry|
    next unless entry['source'] && entry['upstream_path']
    entries << {
      type: 'skill',
      id: skill_id,
      source_id: entry['source'],
      upstream_path: entry['upstream_path'],
      filename: "#{skill_id}.md",
      current_sha: entry['sha256']
    }
  end
end

if entries.empty?
  puts "No upstream sources configured."
  exit 0
end

entries.each do |entry|
  source_cfg = sources[entry[:source_id]]
  unless source_cfg
    warn "  Unknown source: #{entry[:source_id]} for #{entry[:id]} (skipping)"
    errors << entry[:id]
    next
  end

  filename = entry[:filename]
  target = VENDOR_DIR.join(filename)

  # Resolve upstream content based on source type
  content = nil
  new_sha = nil

  case source_cfg['type']
  when 'local'
    # Local path: source.path + upstream_path
    source_root = Pathname.new(source_cfg['path']).expand_path
    upstream_file = source_root.join(entry[:upstream_path])
    unless upstream_file.exist?
      warn "  Source missing: #{entry[:upstream_path]} (in #{source_root}) (skipping)"
      errors << entry[:id]
      next
    end
    content = upstream_file.read
    new_sha = Digest::SHA256.hexdigest(content)

  when 'local-path'
    # Same as local but path is mandatory
    source_root = Pathname.new(source_cfg['path']).expand_path
    upstream_file = source_root.join(entry[:upstream_path])
    unless upstream_file.exist?
      warn "  Source missing: #{entry[:upstream_path]} (in #{source_root}) (skipping)"
      errors << entry[:id]
      next
    end
    content = upstream_file.read
    new_sha = Digest::SHA256.hexdigest(content)

  when 'url'
    # URL fetch: base_url + upstream_path
    base_url = source_cfg['base_url']
    full_url = base_url + entry[:upstream_path]
    begin
      puts "  Fetching #{full_url}..."
      content = fetch_url_with_redirects(full_url)
      new_sha = Digest::SHA256.hexdigest(content)
    rescue => e
      warn "  Fetch failed: #{full_url} — #{e.message} (skipping)"
      errors << entry[:id]
      next
    end

  else
    warn "  Unknown source type: #{source_cfg['type']} for #{entry[:id]} (skipping)"
    errors << entry[:id]
    next
  end

  # Check if changed
  if target.exist? && entry[:current_sha] == new_sha
    puts "  #{filename}: up-to-date (#{new_sha[0..7]})"
    skipped << entry[:id]
    next
  end

  # Write to vendor
  target.write(content)
  puts "  #{filename}: fetched (#{new_sha[0..7]})"

  # Update schema with new sha256
  case entry[:type]
  when 'rule'
    rule = schema['rules'].find { |r| r['id'] == entry[:id] }
    rule['sha256'] = new_sha if rule
  when 'doc'
    doc = schema['docs'].find { |d| d['id'] == entry[:id] }
    doc['sha256'] = new_sha if doc
  when 'skill'
    skill = schema.dig('skills', 'upstream', entry[:id])
    skill['sha256'] = new_sha if skill
  end

  changed << entry[:id]
end

# Save updated schema
if changed.any?
  File.write(SCHEMA_PATH, schema.to_yaml)
  puts ""
  puts "✅ Updated: #{changed.join(', ')}"
else
  puts ""
  puts "✅ All upstream sources up-to-date"
end

puts "   Skipped: #{skipped.join(', ')}" unless skipped.empty?
puts "   Errors: #{errors.join(', ')}" unless errors.empty?
