# frozen_string_literal: true

# Build Loader — PKGBUILD discovery, loading, validation, and index initialization.
#
# Extracted from build.rb (P-B: split 430 LOC build.rb into 3 focused files).

require 'pathname'
require_relative 'common'

module Rulepack
  module BuildLoader
    module_function

    def discover_pkgbuilds
      Rulepack::Common::RULEPACK_ROOT.join('data', 'packages').glob('*/PKGBUILD')
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
      %w[agent import]           => 'agent'
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
  end
end
