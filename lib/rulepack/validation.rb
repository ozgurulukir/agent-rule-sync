# frozen_string_literal: true

module Rulepack
  module Common
    module_function

    # Validate output filename - no path traversal
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

    def validate_pkgbuild(pkg, _pkgdir)
      errors = []
      validate_pkgname(pkg, errors)
      validate_version_fields(pkg, errors)
      validate_descriptive_fields(pkg, errors)
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
      errors << 'targets must be a non-empty array' unless pkg[:targets].is_a?(Array) && !pkg[:targets].empty?
      return unless pkg[:targets].is_a?(Array)

      valid_formats = %w[directory import skill skill-bundle agent]
      pkg[:targets].each_with_index do |t, i|
        errors << "targets[#{i}]: missing platform" unless t[:platform].is_a?(String)
        unless valid_formats.include?(t[:format])
          errors << "targets[#{i}]: invalid format '#{t[:format]}' (must be #{valid_formats.join('/')})"
        end
        begin
          validate_target_entry_output(t, i, pkg, errors)
        rescue StandardError => e
          errors << "targets[#{i}]: #{e.message}"
        end
        tf = t[:transformer]
        if tf && tf != 'copy' && tf != 'strip-frontmatter' && tf !~ /\Acustom:.+\z/
          errors << "targets[#{i}]: invalid transformer '#{tf}'"
        end
        if t[:install]
          inst = t[:install]
          unless %w[symlink copy inject append].include?(inst[:type])
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

    def validate_target_entry_output(t, i, pkg, errors)
      if t[:output].nil? || t[:output].empty?
        errors << "targets[#{i}]: output cannot be empty"
      else
        validate_output_filename(t[:output], pkg[:pkgname])
      end
    end

    # Load and validate PKGBUILD YAML
    # Returns parsed hash with symbolized keys
    def load_pkgbuild(pkgdir)
      pkgbuild_path = Pathname.new(pkgdir).join('PKGBUILD')
      unless pkgbuild_path.exist?
        raise "PKGBUILD not found in #{pkgdir}. " \
              'Create data/packages/<name>/PKGBUILD or run `rulepack build` from repo root.'
      end

      raw = pkgbuild_path.read
      data = YAML.safe_load(raw, permitted_classes: [Symbol, Pathname], symbolize_names: true)

      # Validate required fields
      %i[pkgname pkgver source targets].each do |field|
        unless data.key?(field)
          raise "PKGBUILD missing required field: #{field}. Ensure every PKGBUILD has #{field} defined."
        end
      end

      # Validate source array
      raise 'PKGBUILD must have at least one source entry' unless data[:source].is_a?(Array) && !data[:source].empty?

      data[:source].each do |src|
        raise "Invalid source entry: #{src.inspect}" unless src[:type] && (src[:path] || src[:url])
      end

      # Validate targets array
      raise 'PKGBUILD must have at least one target' unless data[:targets].is_a?(Array) && !data[:targets].empty?

      valid_formats = %w[directory import skill skill-bundle agent]
      data[:targets].each do |t|
        raise "Target missing required fields: #{t.inspect}" unless t[:platform] && t[:format] && t[:output]
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
  end
end
