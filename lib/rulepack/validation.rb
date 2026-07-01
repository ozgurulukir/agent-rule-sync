# frozen_string_literal: true

require 'pathname'

module Rulepack
  module Validation
    module_function

    # ─── PKGBUILD Output Validation ───────────────────────────────────────────────

    # Validate output filename - no path traversal
    # Returns true if valid, raises ArgumentError if invalid
    def validate_output_filename(output, pkgname)
      # Must not contain '..' or absolute path
      if output.include?('..') || Pathname.new(output).absolute?
        raise "Invalid output path '#{output}' in package '#{pkgname}': path traversal not allowed"
      end

      # Must not contain directory separators that escape current dir
      clean = Pathname.new(output).cleanpath
      return unless clean.to_s != output || clean.to_s.include?(File::SEPARATOR)

      raise "Invalid output path '#{output}' in package '#{pkgname}': only filename allowed"
    end

    # Validate target_dir - no path traversal
    def validate_target_dir(target_dir, pkgname)
      return unless target_dir.include?('..') || Pathname.new(target_dir).absolute?

      raise "Invalid target_dir '#{target_dir}' in package '#{pkgname}': path traversal not allowed"
    end

    # ─── PKGBUILD Structure Validation ───────────────────────────────────────────

    def validate_pkgbuild(pkg, _pkgdir)
      errors = []
      validate_pkgname(pkg, errors)
      validate_version_fields(pkg, errors)
      validate_descriptive_fields(pkg, errors)
      validate_pkg_type_field(pkg, errors)
      validate_source_entries(pkg, errors)
      validate_target_entries(pkg, errors)
      errors.empty? || errors.join('; ')
    end

    def validate_pkgname(pkg, errors)
      return if pkg[:pkgname] =~ /\A[a-z0-9][a-z0-9_-]*\z/

      errors << "Invalid pkgname '#{pkg[:pkgname]}': must be lowercase alphanumeric with - or _"
    end

    def validate_version_fields(pkg, errors)
      errors << 'Invalid pkgver: must be non-empty string' unless pkg[:pkgver].is_a?(String) && !pkg[:pkgver].empty?
      if pkg.key?(:pkgver_func) && !(pkg[:pkgver_func].is_a?(String) && !pkg[:pkgver_func].empty?)
        errors << 'pkgver_func must be a non-empty string'
      end
      errors << 'Invalid epoch: must be integer >= 0' unless pkg[:epoch].is_a?(Integer) && pkg[:epoch] >= 0
      errors << 'Invalid pkgrel: must be integer >= 1' unless pkg[:pkgrel].is_a?(Integer) && pkg[:pkgrel] >= 1
    end

    def validate_descriptive_fields(pkg, errors)
      errors << 'Invalid pkgdesc: must be non-empty string' unless pkg[:pkgdesc].is_a?(String) && !pkg[:pkgdesc].empty?
      errors << "Invalid arch: only 'any' supported" unless pkg[:arch] == 'any'
      order_val = pkg[:order] || 0
      errors << 'Invalid order: must be integer >= 0' unless order_val.is_a?(Integer) && order_val >= 0
    end

    VALID_PKG_TYPES = %w[rule skill skill-bundle agent hybrid].freeze

    def validate_pkg_type_field(pkg, errors)
      pkg_type = pkg[:pkg_type]
      if pkg_type.nil? || !pkg_type.is_a?(String) || !VALID_PKG_TYPES.include?(pkg_type)
        errors << "Invalid or missing pkg_type '#{pkg_type}': must be one of #{VALID_PKG_TYPES.join('/')}"
      end
    end

    def validate_source_entries(pkg, errors)
      errors << 'source must be a non-empty array' unless pkg[:source].is_a?(Array) && !pkg[:source].empty?
      pkg[:source]&.each_with_index do |src, i|
        errors << "source[#{i}] missing type or path/url" unless src[:type] && (src[:path] || src[:url])
        case src[:type]
        when 'local'
          unless src[:path].is_a?(String) && !src[:path].empty?
            errors << "source[#{i}] local type requires non-empty path"
          end
        when 'url'
          errors << "source[#{i}] url type requires url" unless src[:url].is_a?(String) && !src[:url].empty?
          errors << "source[#{i}] url type requires valid sha256" unless src[:sha256] =~ /\A[0-9a-f]{64}\z/i
        when 'git'
          errors << "source[#{i}] git type requires url" unless src[:url].is_a?(String) && !src[:url].empty?
          errors << "source[#{i}] git ref must be string" if src.key?(:ref) && !src[:ref].is_a?(String)
          errors << "source[#{i}] git path must be string" if src.key?(:path) && !src[:path].is_a?(String)
          errors << "source[#{i}] git depth must be integer" if src.key?(:depth) && !src[:depth].is_a?(Integer)
        else
          errors << "source[#{i}] unknown type: #{src[:type]}"
        end
      end
    end

    def validate_target_entries(pkg, errors)
      unless pkg[:targets].nil? || (pkg[:targets].is_a?(Array) && !pkg[:targets].empty?)
        errors << 'targets must be a non-empty array or omitted (auto-expanded)'
      end
      return unless pkg[:targets].is_a?(Array)

      valid_formats = %w[directory import skill skill-bundle agent]
      pkg[:targets].each_with_index do |t, i|
        errors << "targets[#{i}]: missing platform" unless t[:platform].is_a?(String)
        if t[:format] && !valid_formats.include?(t[:format])
          errors << "targets[#{i}]: invalid format '#{t[:format]}' (must be #{valid_formats.join('/')})"
        end
        begin
          validate_target_entry_output(t, i, pkg)
        rescue StandardError => e
          errors << "targets[#{i}]: #{e.message}"
        end
        tf = t[:transformer]
        if tf && tf != 'copy' && tf !~ /\Acustom:.+\z/
          errors << "targets[#{i}]: invalid transformer '#{tf}' (strip-frontmatter is deprecated; remove it — frontmatter is handled automatically by SchemaEngine)"
        end
        if t[:install]
          inst = t[:install]
          if inst[:type] && !%w[symlink copy inject append json_merge yaml_merge].include?(inst[:type])
            errors << "targets[#{i}]: invalid install.type '#{inst[:type]}'"
          end
          validate_target_dir(inst[:target_dir], pkg[:pkgname]) if inst[:target_dir]
        end
        next unless t[:format] == 'skill-bundle'

        inst = t[:install] || {}
        unless inst[:target_dir].is_a?(String) && !inst[:target_dir].empty?
          errors << "targets[#{i}]: skill-bundle requires install.target_dir"
        end
        errors << "targets[#{i}]: skill-bundle install.type must be 'copy'" unless (inst[:type] || 'copy') == 'copy'
      end
    end

    def validate_target_entry_output(t, _i, _pkg)
      return unless t[:output]

      validate_output_filename(t[:output], _pkg[:pkgname])
    end

    # ─── PKGBUILD Load & Validate ────────────────────────────────────────────────

    # Load and validate PKGBUILD YAML
    # Returns parsed hash with symbolized keys
    def load_pkgbuild(pkgdir)
      pkgbuild_path = Pathname.new(pkgdir).join('PKGBUILD')
      unless pkgbuild_path.exist?
        raise "PKGBUILD not found in #{pkgdir}. " \
              'Create data/packages/<name>/PKGBUILD, data/packages/local/<name>/PKGBUILD, ' \
              'or data/packages/upstream/<name>/PKGBUILD.'
      end

      raw = pkgbuild_path.read
      data = YAML.safe_load(raw, permitted_classes: [Symbol, Pathname], symbolize_names: true)

      # Validate required fields
      %i[pkgname pkgver source].each do |field|
        unless data.key?(field)
          raise "PKGBUILD missing required field: #{field}. Ensure every PKGBUILD has #{field} defined."
        end
      end

      # Validate source array
      raise 'PKGBUILD must have at least one source entry' unless data[:source].is_a?(Array) && !data[:source].empty?

      data[:source].each do |src|
        raise "Invalid source entry: #{src.inspect}" unless src[:type] && (src[:path] || src[:url])
      end

      # Validate targets array (optional — auto-expanded when omitted)
      return data unless data.key?(:targets)

      unless data[:targets].is_a?(Array) && !data[:targets].empty?
        raise 'PKGBUILD must have at least one target'
      end

      valid_formats = %w[directory import skill skill-bundle agent]
      data[:targets].each do |t|
        raise "Target missing platform: #{t.inspect}" unless t[:platform]

        next unless t[:format]

        raise "Invalid format '#{t[:format]}' for platform '#{t[:platform]}'" unless valid_formats.include?(t[:format])

        # skill-bundle/agent: output must be '.' (directory marker), target_dir required
        next unless %w[skill-bundle agent].include?(t[:format])
        if t[:output] && t[:output] != '.' && !t[:output].empty?
          raise "skill-bundle output must be '.' (directory marker), got '#{t[:output]}'"
        end
        raise 'skill-bundle requires install.target_dir in PKGBUILD' unless t[:install] && t[:install][:target_dir]

        # install type for skill-bundle should be 'copy' only
        install_type = t[:install][:type] || 'copy'
        raise "skill-bundle only supports install.type: 'copy', got '#{install_type}'" unless install_type == 'copy'
      end

      data
    end

    # ─── Drift CMS: Checksum & Target Validation ─────────────────────────────────

    # Verify checksum of file, supporting marker-based content
    def verify_checksum(path, expected_checksum, pkgname)
      path = Pathname.new(path)
      return false unless path.exist?

      content = path.read
      start_marker = "<!-- rulepack:#{pkgname} start -->"
      end_marker = "<!-- rulepack:#{pkgname} end -->"

      if content.include?(start_marker) && content.include?(end_marker)
        pattern = /#{Regexp.escape(start_marker)}\n(.*?)\n#{Regexp.escape(end_marker)}/m
        blocks = content.scan(pattern).map(&:first)
        unless blocks.empty?
          extracted = blocks.join("\n")
          return Digest::SHA256.hexdigest(extracted) == expected_checksum
        end
      end

      Digest::SHA256.hexdigest(content) == expected_checksum
    end

    # Validate and resolve target platforms against the installed index.
    #
    # @param target_arg [String, nil] "all" or comma-separated platform IDs
    # @param package_arg [String, nil] optional package name to filter
    # @param packages [Hash] index[:packages] — the installed-package index
    # @param registry [Hash] platform registry from load_platform_registry
    # @param exit_on_failure [Boolean] abort on error (CLI mode) vs raise
    # @param project_arg [String, nil] --project path for project-scoped platforms
    # @param enforce_project_scope [Boolean] call project_root_for during validation
    # @return [Array(Array<String>, String|nil)] [targets, target_package]
    def validate_targets_and_packages(target_arg, package_arg, packages, registry,
                                      exit_on_failure: false, project_arg: nil,
                                      enforce_project_scope: false)
      # ── Package existence check ──────────────────────────────────────────────────
      target_package = nil
      if package_arg
        unless packages.key?(package_arg) || packages.key?(package_arg.to_sym)
          msg = "Package '#{package_arg}' is not registered as installed in index."
          exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
        end
        target_package = packages.keys.find { |k| k.to_s == package_arg }.to_s
      end

      # ── Target arg required ──────────────────────────────────────────────────────
      unless target_arg
        msg = "Please specify target platform(s) with --target <platform> (or --target all)."
        exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
      end

      # ── Expand targets ───────────────────────────────────────────────────────────
      targets = []
      if target_arg.to_s.downcase == 'all'
        if target_package
          pkg_idx = packages[target_package.to_sym] || packages[target_package.to_s] || {}
          targets = (pkg_idx[:installed] || []).map { |i| i[:platform] }.uniq
        else
          platform_set = Set.new
          packages.each_value do |pkg|
            (pkg[:installed] || []).each { |i| platform_set << i[:platform] }
          end
          targets = platform_set.to_a
        end
      else
        targets = target_arg.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      return [targets, target_package] if targets.empty?

      # ── Validate targets against registry ────────────────────────────────────────
      targets.each do |p|
        cfg = registry[p.to_sym] || registry[p.to_s]
        unless cfg
          msg = "Unknown target platform '#{p}'."
          exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
        end
        Rulepack::Common.project_root_for(cfg, project_arg) if enforce_project_scope
      end

      [targets, target_package]
    end
  end
end
