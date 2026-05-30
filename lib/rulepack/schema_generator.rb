# frozen_string_literal: true

# Schema Generator — derives data/build_schema.yaml from all PKGBUILD targets.
#
# Scans every data/packages/*/PKGBUILD and collects the (platform, format) pairs
# that actually occur. For each pair it checks whether at least one target has
# an explicit translate or transformer value; if none do, it marks the entry as
# null (no-op). A platform/format pair that never occurs in any PKGBUILD is
# left absent from the output.
#
# The generated YAML is the authoritative single source of truth. PKGBUILD
# authors should NOT hand-edit data/build_schema.yaml directly.

module Rulepack
  module SchemaGenerator
    module_function

    # Generate the full platform × format schema from existing PKGBUILD files.
    # Writes data/build_schema.yaml and returns the parsed schema hash.
    def generate!
      root = Rulepack::Common::RULEPACK_ROOT
      packages_dir = root.join('data', 'packages')
      schema_path = root.join('data', 'build_schema.yaml')

      # ─── 1. Collect every target ────────────────────────────────────────────────
      # collected[platform_id][format] = { translates: Set, transformers: Set }
      collected = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = { translates: Set.new, transformers: Set.new } } }

      packages_dir.glob('*/PKGBUILD').each do |pkgbuild_path|
        pkg = begin
                YAML.safe_load(pkgbuild_path.read, permitted_classes: [Symbol, Pathname], symbolize_names: true)
              rescue StandardError => e
                Rulepack::Common.log_warn "SchemaGenerator: failed to parse #{pkgbuild_path}: #{e.class}: #{e.message}, skipping"
                next
              end

        targets = pkg[:targets] || []
        targets = [targets] unless targets.is_a?(Array)
        pkgname = pkg[:pkgname] || pkgbuild_path.dirname.basename.to_s

        targets.each do |tgt|
          platform_id = tgt[:platform]&.to_s
          format       = tgt[:format]&.to_s
          next unless platform_id && format

          entry = collected[platform_id][format]
          explicit_translate   = tgt[:translate]
          explicit_transformer = tgt[:transformer]

          entry[:translates] << explicit_translate unless explicit_translate.nil?
          entry[:transformers] << explicit_transformer unless explicit_transformer.nil?
        end
      end

      # ─── 2. Build schema hash ──────────────────────────────────────────────────
      # For each (platform, format):
      #   translate   = first non-nil, non-'copy' value across all targets; else null
      #   transformer = first non-nil, non-'copy' value across all targets; else 'copy'
      new_schema = {}

      platforms_in_use = collected.keys.sort
      formats_in_use   = collected.values.flat_map(&:keys).uniq.sort

      platforms_in_use.each do |platform_id|
        new_schema[platform_id] ||= {}
        formats_in_use.each do |format|
          next unless collected[platform_id].key?(format)

          entry_data = collected[platform_id][format]

          # Resolve translate: prefer any explicitly set value; if only nil/copy observed → null
          translate = resolve_effective(entry_data[:translates], default: nil)

          # Resolve transformer: prefer any explicitly set value; if only nil/copy observed → 'copy'
          # strip-frontmatter is permanently removed — filter it out
          raw_transformers = entry_data[:transformers].reject { |v| v == 'strip-frontmatter' }
          transformer = resolve_effective(raw_transformers, default: 'copy')

          new_schema[platform_id][format] = {
            'translate'   => translate,
            'transformer' => transformer,
          }
        end
      end

      # ─── 3. Read existing schema (merge to preserve comments) ──────────────────
      existing_raw = schema_path.exist? ? schema_path.read : nil

      # ─── 4. Write ──────────────────────────────────────────────────────────────
      yaml_output = build_yaml_output(new_schema, existing_raw, root)

      schema_path.dirname.mkpath
      schema_path.write(yaml_output)
      Rulepack::Common.log "SchemaGenerator: wrote #{schema_path} (#{new_schema.size} platforms, #{new_schema.values.sum { |f| f.size }} formats)"
      puts "SchemaGenerator: wrote #{schema_path} (#{new_schema.size} platforms, #{new_schema.values.sum { |f| f.size }} formats)"

      new_schema
    end

    # Pick the most common non-nil value from a set.
    # Falls back to default only when the set is empty or contains exclusively nil.
    def resolve_effective(set, default:)
      non_trivial = set.reject { |v| v.nil? || v == 'copy' }
      return nil if non_trivial.empty? && default.nil?
      return default if non_trivial.empty?
      # If all values agree, return that value
      return non_trivial.first if non_trivial.size == 1

      # Multiple distinct values — return the most frequent one
      counts = non_trivial.each_with_object(Hash.new(0)) { |v, h| h[v] += 1 }
      counts.max_by { |_v, c| c }&.first || default
    end

    # Build YAML string from new_schema hash.
    # Tries to preserve existing section order and comments from the old file
    # by reusing the existing preamble and appending only platform blocks that are new.
    # For platforms already in the existing file, we only update inline values (not
    # re-structure), so structural comments are preserved.
    def build_yaml_output(new_schema, existing_raw, root)
      require 'yaml'

      if existing_raw.nil? || existing_raw.strip.empty?
        return render_schema_yaml(new_schema)
      end

      # Parse existing schema (preserve comments via Psych safe_load with aliases)
      existing = begin
                    YAML.safe_load(existing_raw, permitted_classes: [Symbol]) || {}
                  rescue StandardError
                    {}
                  end
      existing_schema = existing['schema'] || {}

      # We'll rebuild sections independently and merge with preamble
      existing_preamble = extract_preamble(existing_raw)

      rendered = render_schema_yaml(new_schema, existing_schema)
      existing_preamble + rendered
    end

    # Extract non-schema comment lines at the top of the file.
    # Skips the auto-generated header block (frozen_string_literal + Auto-generated)
    # to avoid accumulating duplicates on each build.
    def extract_preamble(raw)
      lines = raw.each_line.to_a
      preamble = []
      header_seen = 0
      lines.each do |line|
        stripped = line.strip
        break if stripped.start_with?('schema:')
        if stripped.empty? || stripped.start_with?('#')
          header_seen += 1 if stripped.start_with?('# frozen_string_literal') || stripped.start_with?('# Auto-generated')
          next if header_seen <= 2  # skip the canonical header block
        end
        preamble << line
      end
      preamble.join
    end

    # Render new_schema hash as YAML string.
    # existing_schema is used to preserve the order of platform keys that were
    # already present, and to avoid re-emitting platforms unchanged.
    def render_schema_yaml(new_schema, existing_schema = nil)
      lines = ["# frozen_string_literal: true\n", "\n", "# Auto-generated by SchemaGenerator. Do not edit manually.\n", "\n"]

      all_platforms = if existing_schema && !existing_schema.empty?
                        # Keep existing order, append new ones
                        (existing_schema.keys + (new_schema.keys - existing_schema.keys)).uniq
                      else
                        new_schema.keys
                      end

      lines << "schema:\n"
      all_platforms.each do |platform_id|
        next unless new_schema.key?(platform_id)
        platform_block = new_schema[platform_id]
        next if platform_block.nil? || platform_block.empty?

        lines << "  #{yaml_key(platform_id)}:\n"
        platform_block.each do |format, cfg|
          lines << "    #{yaml_key(format)}:\n"
          lines << "      translate: #{yaml_value(cfg['translate'])}\n"
          lines << "      transformer: #{yaml_value(cfg['transformer'])}\n"
        end
      end

      lines.join
    end

    # Quote string if it contains special chars or is empty; otherwise leave bare
    def yaml_key(s)
      s = s.to_s
      s =~ /[:\s\[\]{}#&*!|>'"%@`]/ || s.empty? ? "'#{s}'" : s
    end

    def yaml_value(v)
      return 'null' if v.nil?
      return v.to_s if v.is_a?(String) && !v.empty?
      'null'
    end
  end
end
