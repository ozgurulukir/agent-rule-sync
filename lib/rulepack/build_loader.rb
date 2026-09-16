# frozen_string_literal: true

# Build Loader — PKGBUILD discovery, loading, validation, and target expansion.
#
# Returns immutable Rulepack::Package models (with Target models) to the
# build orchestrator; the build-index entry schema is owned by
# Rulepack::BuildRecord.

require 'pathname'
require_relative 'common'
require_relative 'models/package'
require_relative 'models/target'

module Rulepack
  module BuildLoader
    module_function

    def discover_pkgbuilds
      Rulepack::PackageResolver.all_pkgbuilds(namespaces: :all)
    end

    # Returns [Rulepack::Package, pkgname_sym] or nil on failure.
    # Package.from_hash applies the epoch/pkgrel/order defaults that
    # PKGBUILDs may omit, then the descriptor is validated.
    def load_and_validate_pkgbuild(pkgbuild_path)
      pkg_dir = pkgbuild_path.dirname
      pkg = Package.from_hash(Rulepack::Validation.load_pkgbuild(pkg_dir))
      pkgname = pkg.pkgname.to_sym

      validation_error = Rulepack::Validation.validate_pkgbuild(pkg, pkg_dir)
      if validation_error != true
        Rulepack::Common.log_error "PKGBUILD validation failed for #{pkgname}: #{validation_error}"
        return nil
      end

      [pkg, pkgname]
    rescue StandardError => e
      Rulepack::Common.log_error "Failed to load #{pkgbuild_path}: #{e.message}"
      nil
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
      FORMAT_MAP[[pkg_type, platform_type]] || raise(Rulepack::ConfigError, "Unknown format for pkg_type=#{pkg_type}, platform_type=#{platform_type}")
    end

    def resolve_default_install(platform_cfg, target_format, pkgname)
      return { 'type' => 'copy', 'target_dir' => "#{pkgname}/" } if target_format.materializable?

      if target_format.import?
        return { 'type' => 'copy' }
      end

      default_cfg = target_format.skill_format? ? platform_cfg[:skill_install] : platform_cfg[:rule_install]
      install_type = default_cfg&.dig(:type) || 'copy'
      { 'type' => install_type }
    end

    def resolve_default_output(pkg, target_format, platform_id, _platform_type, source_basename)
      return '.' if target_format.materializable?

      return 'SKILL.md' if platform_id.to_s == 'codex'

      pkgname = pkg.pkgname.to_s

      return pkg.output if pkg.output

      if target_format.import?
        return "#{pkgname}-instructions.md" if platform_id.to_s == 'github-copilot'
        return "#{pkgname}-rule.md"
      end

      source_basename
    end

    # Returns a new Package with targets expanded to every platform and
    # normalized as Target models. The input Package is never mutated.
    def expand_targets(pkg, platforms)
      pkg_type = pkg.pkg_type.to_s
      pkgname = pkg.pkgname.to_s

      if pkg_type == 'hybrid' && (pkg.targets.nil? || pkg.targets.empty?)
        raise ArgumentError, "hybrid pkg_type requires explicit targets in PKGBUILD (ambiguous format mix)"
      end

      source_path = pkg.source.first ? pkg.source.first[:path].to_s : ''
      source_basename = File.basename(source_path)
      source_is_dir = source_path.end_with?('/')

      existing = {}
      (pkg.targets || []).each do |t|
        existing[t[:platform].to_s] = t
      end

      expanded = platforms.map do |platform_id, platform_cfg|
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
        format = Target.from_hash(format: format_type, platform: platform_id)

        default_output = resolve_default_output(pkg, format, platform_id, platform_type, source_basename)
        default_install = resolve_default_install(platform_cfg, format, pkgname)

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

        Target.from_hash(target)
      end

      pkg.with(targets: expanded)
    end
  end
end
