# frozen_string_literal: true

require "tempfile"
require "yaml"
require "pathname"
require "fileutils"

module Rulepack
  module IO
    module_function

    # Read a text file as UTF-8. Defensive fallback for environments where the
    # default external encoding has not been set to UTF-8.
    def read_text(path)
      Pathname.new(path).read(encoding: Encoding::UTF_8)
    end

    # Read a binary file without transcoding.
    def read_binary(path)
      Pathname.new(path).binread
    end

    def load_yaml(path)
      content = read_text(path)
      YAML.safe_load(content, permitted_classes: [Symbol, Pathname], symbolize_names: true)
    end

    # Write YAML atomically
    def write_yaml_atomic(path, data)
      yaml_content = data.to_yaml
      atomic_write(path, yaml_content)
    end

    # Atomic write: write content to temp file then rename
    def atomic_write(path, content)
      path = Pathname.new(path)
      path.dirname.mkpath

      Tempfile.create(['rulepack', path.extname], path.dirname) do |tmp|
        tmp.write(content)
        tmp.flush
        FileUtils.mv(tmp.path, path.to_s)
      end
    end

    # Append to file atomically (create if doesn't exist)
    def safe_append(path, content)
      path = Pathname.new(path)
      path.dirname.mkpath

      File.open(path.to_s, 'a') { |f| f.write(content) }
    end

    # Update content wrapped in markers (idempotent)
    def update_marked_content(path, pkgname, content)
      path = Pathname.new(path)
      start_marker = "<!-- rulepack:#{pkgname} start -->"
      end_marker = "<!-- rulepack:#{pkgname} end -->"

      new_block = "#{start_marker}\n#{content}\n#{end_marker}"

      if path.exist?
        existing = path.read
        if existing.include?(start_marker) && existing.include?(end_marker)
          # Replace existing block
          pattern = /#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}/m
          updated = existing.sub(pattern, new_block)
          atomic_write(path, updated)
          :updated
        else
          # Append new block (with separation if file not empty)
          sep = existing.empty? || existing.end_with?("\n\n") ? '' : (existing.end_with?("\n") ? "\n" : "\n\n")
          safe_append(path, sep + new_block)
          :appended
        end
      else
        # Create new file
        atomic_write(path, new_block)
        :created
      end
    end

    # Remove content wrapped in markers (surgical excision)
    # Returns :removed if content was excised, :file_removed if file was empty and deleted, :not_found if markers missing
    def remove_marked_content(path, pkgname)
      path = Pathname.new(path)
      return :not_found unless path.exist?

      start_marker = "<!-- rulepack:#{pkgname} start -->"
      end_marker = "<!-- rulepack:#{pkgname} end -->"

      content = path.read
      unless content.include?(start_marker) && content.include?(end_marker)
        return :not_found
      end

      pattern = /#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}/m
      updated = content.gsub(pattern, '').gsub(/\n{3,}/, "\n\n").strip

      if updated.empty?
        path.unlink
        :file_removed
      else
        atomic_write(path, updated + "\n")
        :removed
      end
    end

    def deep_merge(base, override)
      merger = proc { |_key, v1, v2|
        if v1.is_a?(Hash) && v2.is_a?(Hash)
          v1.merge(v2, &merger)
        elsif v1.is_a?(Array) && v2.is_a?(Array)
          v1 | v2
        else
          v2
        end
      }
      base.merge(override, &merger)
    end
  end
end
