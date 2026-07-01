# frozen_string_literal: true

# Build Loader — PKGBUILD discovery, loading, validation, and index initialization.
#
# Extracted from build.rb (P-B: split 430 LOC build.rb into 3 focused files).

require 'pathname'
require 'tsort'
require_relative 'common'

module Rulepack
  module BuildLoader
    module_function

    def discover_pkgbuilds
      Rulepack::PackageResolver.all_pkgbuilds(namespaces: :all)
    end

    def load_and_validate_pkgbuild(pkgbuild_path)
      pkg_dir = pkgbuild_path.dirname
      pkg = Rulepack::Common.load_pkgbuild(pkg_dir)

      pkgname = pkg[:pkgname].to_sym

      # Set default epoch/pkgrel before validation (PKGBUILD may omit them)
      pkg[:epoch] = 0 unless pkg.key?(:epoch)
      pkg[:pkgrel] = 1 unless pkg.key?(:pkgrel)

      # Validate PKGBUILD
      validation_error = Rulepack::Common.validate_pkgbuild(pkg, pkg_dir)
      if validation_error != true
        Rulepack::Common.log_error "PKGBUILD validation failed for #{pkgname}: #{validation_error}"
        return nil
      end

      [pkg, pkgname]
    rescue StandardError => e
      Rulepack::Common.log_error "Failed to load #{pkgbuild_path}: #{e.message}"
      nil
    end

    def init_pkg_index(pkg)
      pkgname = pkg[:pkgname].to_sym
      {
        pkgver: pkg[:pkgver],
        pkgrel: pkg[:pkgrel],
        epoch: pkg[:epoch],
        pkgdesc: pkg[:pkgdesc],
        order: pkg[:order] || 0,
        status: 'stable',
        installed: [],
        available_targets: [],
        dependencies: pkg[:dependencies] || [],
        conflicts: pkg[:conflicts] || [],
        provides: pkg[:provides] || [],
        tags: pkg[:tags] || [],
        checksums: { source: nil, built: {} }
      }
    end

    def update_pkg_index_from_pkg(pkg_index, pkg)
      pkg_index[:pkgver] = pkg[:pkgver]
      pkg_index[:pkgrel] = pkg[:pkgrel]
      pkg_index[:epoch] = pkg[:epoch]
      pkg_index[:targets] = pkg[:targets] || []
    end

    FORMAT_MAP = {
      %w[rule directory]         => 'directory',
      %w[rule skill]             => 'skill',
      %w[rule import]            => 'import',
      %w[skill directory]        => 'skill',
      %w[skill skill]            => 'skill',
      %w[skill import]           => 'import',
      %w[skill-bundle directory] => 'skill-bundle',
      %w[skill-bundle skill]     => 'skill-bundle',
      %w[skill-bundle import]    => 'skill-bundle',
      %w[agent directory]        => 'agent',
      %w[agent skill]            => 'agent',
      %w[agent import]           => 'agent',
      %w[hybrid directory]       => 'directory',
      %w[hybrid skill]           => 'skill',
      %w[hybrid import]          => 'import'
    }.freeze

    def resolve_format(pkg_type, platform_type)
      FORMAT_MAP[[pkg_type, platform_type]] || raise("Unknown format for pkg_type=#{pkg_type}, platform_type=#{platform_type}")
    end

    def resolve_default_install(platform_cfg, format_type, pkg_type, pkgname)
      return { 'type' => 'copy', 'target_dir' => "#{pkgname}/" } if %w[skill-bundle agent].include?(format_type)

      if format_type == 'import'
        result = { 'type' => 'copy' }
        return result
      end

      default_cfg = if %w[skill].include?(format_type)
                      platform_cfg[:skill_install]
                    else
                      platform_cfg[:rule_install]
                    end
      install_type = default_cfg&.dig(:type) || 'copy'
      { 'type' => install_type }
    end

    def resolve_default_output(pkg, format_type, platform_id, _platform_type, source_basename)
      return '.' if %w[skill-bundle agent].include?(format_type)

      return 'SKILL.md' if platform_id.to_s == 'codex'

      pkgname = pkg[:pkgname].to_s

      return pkg[:output] if pkg[:output]

      if format_type == 'import'
        return "#{pkgname}-instructions.md" if platform_id.to_s == 'github-copilot'
        return "#{pkgname}-rule.md"
      end

      source_basename
    end

    def expand_targets(pkg, platforms)
      pkg_type = pkg[:pkg_type].to_s
      pkgname = pkg[:pkgname].to_s

      if pkg_type == 'hybrid' && (pkg[:targets].nil? || pkg[:targets].empty?)
        raise ArgumentError, "hybrid pkg_type requires explicit targets in PKGBUILD (ambiguous format mix)"
      end

      src = (pkg[:source] || []).first || {}
      source_path = src[:path].to_s
      source_basename = File.basename(source_path)
      source_is_dir = source_path.end_with?('/')

      existing = {}
      (pkg[:targets] || []).each do |t|
        existing[t[:platform].to_s] = t
      end

      expanded = []
      platforms.each do |platform_id, platform_cfg|
        platform_type = platform_cfg[:type].to_s

        default_format = if pkg_type == 'agent'
                           'agent'
                         elsif source_is_dir
                           'skill-bundle'
                         else
                           resolve_format(pkg_type, platform_type)
                         end

        override = existing[platform_id.to_s]
        format_type = (override && override[:format]) || default_format

        default_output = resolve_default_output(pkg, format_type, platform_id, platform_type, source_basename)
        default_install = resolve_default_install(platform_cfg, format_type, pkg_type, pkgname)

        target = {
          platform: platform_id.to_s,
          format: format_type,
          output: default_output,
          install: default_install
        }

        if override
          target[:output] = override[:output] if override[:output]
          target[:install] = default_install.merge(override[:install] || {})
          target[:transformer] = override[:transformer] if override[:transformer]
          target[:translate] = override[:translate] if override[:translate]
          target[:agent_config] = override[:agent_config] if override[:agent_config]
        end

        expanded << target
      end

      pkg[:targets] = expanded
    end

    VALID_PKG_TYPES = %w[rule skill skill-bundle agent hybrid].freeze

    def validate_pkg_type(pkg, errors)
      pkg_type = pkg[:pkg_type]
      if pkg_type.nil? || !pkg_type.is_a?(String) || !VALID_PKG_TYPES.include?(pkg_type)
        errors << "Invalid or missing pkg_type '#{pkg_type}': must be one of #{VALID_PKG_TYPES.join('/')}"
      end
    end

    def validate_dependencies(pkg_index, errors)
      pkg_names = pkg_index.keys.map(&:to_s)
      virtual = {}
      pkg_index.each do |_name, idx|
        (idx[:provides] || []).each { |v| virtual[v.to_s] = _name.to_s }
      end

      pkg_index.each do |name, idx|
        (idx[:dependencies] || []).each do |dep|
          resolved = pkg_names.include?(dep.to_s) ? dep.to_s : virtual[dep.to_s]
          unless resolved
            errors << "Package '#{name}' has unresolvable dependency: '#{dep}'"
          end
        end
      end
    end

    def resolve_install_order(pkg_index)
      graph = {}
      virtual = {}
      pkg_index.each do |name, idx|
        name_s = name.to_s
        deps = (idx[:dependencies] || []).map do |dep|
          dep_s = dep.to_s
          virtual[dep_s] ? virtual[dep_s] : (pkg_index.key?(dep_s.to_sym) || pkg_index.key?(dep_s) ? dep_s : nil)
        end.compact
        graph[name_s] = deps
        (idx[:provides] || []).each { |v| virtual[v.to_s] = name_s }
      end

      resolver = DependencyGraph.new(graph)
      begin
        resolver.tsort
      rescue TSort::Cyclic => e
        raise "Circular dependency detected: #{e.message}"
      end
    end

    class DependencyGraph < Hash
      include TSort
      alias tsort_each_node each_key

      def tsort_each_child(node, &blk)
        fetch(node, []).each(&blk)
      end
    end
  end
end
