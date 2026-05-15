#!/usr/bin/env ruby
# frozen_string_literal: true

# ssot/generate-catalog.rb — Generate portible package catalog from build index
# Output: ssot/build/catalog.json (repo envanteri — dış araçlar için)
# Çalışma zamanı: build.rb sonunda otomatik, veya standalone `ruby ssot/generate-catalog.rb`

require 'pathname'
require 'json'
require 'yaml'
require_relative 'lib/common'

SSOT_ROOT = Pathname.new(__dir__).expand_path

def main
  unless Ssot::Lib::Common::BUILD_INDEX_PATH.exist?
    abort "Build index not found. Run `ruby ssot/build.rb` first."
  end

  index = load_index
  packages = index[:packages] || {}
  return puts "No packages in build index." if packages.empty?

  catalog_pkgs = packages.map { |name, data| build_package_entry(name, data) }.compact

  platforms = catalog_pkgs.each_with_object(Hash.new(0)) do |pkg, counts|
    (pkg[:platforms] || []).each { |pl| counts[pl] += 1 }
  end

  catalog = {
    version: '1.0',
    generated_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
    packages: catalog_pkgs,
    platform_summary: platforms.sort_by { |_, count| -count }.to_h
  }

  output_path = Ssot::Lib::Common::BUILD_DIR.join('catalog.json')
  File.write(output_path, JSON.pretty_generate(catalog) + "\n")
  puts "Catalog written: #{output_path} (#{catalog_pkgs.size} packages, #{platforms.size} platforms)"
end

def load_index
  raw = YAML.safe_load(Ssot::Lib::Common::BUILD_INDEX_PATH.read, permitted_classes: [Symbol])
  deep_symbolize_keys(raw)
end

def deep_symbolize_keys(obj)
  case obj
  when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize_keys(v) }
  when Array then obj.map { |v| deep_symbolize_keys(v) }
  else obj
  end
end

def build_package_entry(name, data)
  source = read_source_info(name)

  {
    id: name.to_s,
    version: format_ver(data),
    description: data[:pkgdesc]&.strip,
    tags: data[:tags] || [],
    source: source,
    platforms: data[:available_targets]&.map(&:to_s) || []
  }
end

def format_ver(data)
  epoch = data[:epoch].to_i
  ver = data[:pkgver] || '0'
  rel = data[:pkgrel].to_i
  epoch > 0 ? "#{epoch}:#{ver}-#{rel}" : "#{ver}-#{rel}"
end

def read_source_info(name)
  pkgbuild_path = SSOT_ROOT.join('packages', name.to_s, 'PKGBUILD')
  return { type: 'unknown' } unless pkgbuild_path.exist?

  pkg = YAML.safe_load(pkgbuild_path.read, permitted_classes: [Symbol]) || {}
  sources = [pkg['source']].flatten.compact
  first = sources.first
  return { type: 'unknown' } unless first

  case first['type']
  when 'local'
    { type: 'local' }
  when 'url'
    { type: 'url', url: first['url'] }
  when 'git'
    entry = { type: 'git', url: first['url'] }
    entry[:ref] = first['ref'] if first['ref']
    entry[:path] = first['path'] if first['path']
    entry
  else
    { type: first['type'] || 'unknown' }
  end
end

main
