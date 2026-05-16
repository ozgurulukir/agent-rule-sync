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

      valid_formats = %w[directory import skill skill-bundle]
      data[:targets].each do |t|
        raise "Target missing required fields: #{t.inspect}" unless t[:platform] && t[:format] && t[:output]
        raise "Invalid format '#{t[:format]}' for platform '#{t[:platform]}'" unless valid_formats.include?(t[:format])

        # skill-bundle: output must be '.' (directory marker), target_dir required
        next unless t[:format] == 'skill-bundle'
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
