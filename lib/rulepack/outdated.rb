# frozen_string_literal: true

require_relative 'encoding_defaults'
require 'pathname'
require_relative 'common'

module Rulepack
  module Outdated
    module_function

    # Returns a Rulepack::Result listing installed packages that are older than
    # the current build, plus packages available in the build but not installed.
    def run(options = {})
      target_arg = options[:target] || 'all'
      project_arg = options[:project_path]

      unless Rulepack::Common.build_index_path.exist?
        msg = "Build index not found at #{Rulepack::Common.build_index_path}. Run `ruby lib/rulepack/build.rb` first."
        return Rulepack::Result.new(status: :failure, errors: [msg])
      end

      build_index = Rulepack::Common.load_yaml(Rulepack::Common.build_index_path)
      index = if Rulepack::Common.index_yaml_path.exist?
                Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
              else
                { version: 3.0, packages: {} }
              end
      registry = Rulepack::Common.load_platform_registry

      targets = resolve_targets(target_arg, registry, project_arg)
      if targets.empty?
        return Rulepack::Result.new(
          status: :success,
          data: { outdated: [], available: [], targets: [] },
          messages: ['No targets to check.']
        )
      end

      outdated = []
      available = []

      build_index[:packages].each do |pkgname, pkgdata|
        build_ver = pkgdata[:pkgver]
        installed_pkg = index.dig(:packages, pkgname.to_sym) || index.dig(:packages, pkgname.to_s)
        installed_records = installed_pkg ? Array(installed_pkg[:installed]) : []

        targets.each do |platform_id|
          record = installed_records.find { |r| r[:platform].to_s == platform_id.to_s }
          if record
            installed_ver = record[:version]
            if installed_ver != build_ver
              outdated << {
                pkgname: pkgname.to_s,
                platform: platform_id.to_s,
                installed_version: installed_ver,
                build_version: build_ver
              }
            end
          else
            available << {
              pkgname: pkgname.to_s,
              platform: platform_id.to_s,
              build_version: build_ver
            }
          end
        end
      end

      status = outdated.empty? ? :success : :partial
      messages = build_messages(targets, outdated, available)

      Rulepack::Result.new(
        status: status,
        data: {
          targets: targets,
          outdated: outdated,
          available: available
        },
        messages: messages
      )
    end

    def resolve_targets(target_arg, registry, project_arg)
      if target_arg.to_s.downcase == 'all'
        registry.keys.select do |p|
          cfg = registry[p]
          scope = cfg[:scope] || 'user'
          if scope == 'project'
            !project_arg.nil?
          else
            true
          end
        end.map(&:to_s)
      else
        target_arg.to_s.split(',').map(&:strip).reject(&:empty?)
      end
    end

    def build_messages(targets, outdated, available)
      messages = []
      messages << "📦 Outdated check for #{targets.size} platform(s): #{targets.join(', ')}"

      if outdated.empty?
        messages << '  ✓ All installed packages are up to date with the build index.'
      else
        messages << "  ⚠ #{outdated.size} installed package(s) are older than the build:"
        outdated.each do |o|
          messages << "    • #{o[:pkgname]} on #{o[:platform]}: #{o[:installed_version]} → #{o[:build_version]}"
        end
      end

      if available.any?
        messages << "  ⬇ #{available.size} package(s) available in build but not installed:"
        available.each { |a| messages << "    • #{a[:pkgname]} on #{a[:platform]} (#{a[:build_version]})" }
      end

      messages
    end
  end
end

# CLI runner block
if __FILE__ == $PROGRAM_NAME || caller.any? { |c| c.include?('capture_script_run') || c.include?('invoke') }
  begin
    opts = Rulepack::CliParser.parse(ARGV)
    result = Rulepack::Outdated.run(opts)

    if result.failure?
      if (opts[:format] || :text).to_sym == :text
        result.messages.each { |m| warn m }
        result.errors.each { |e| warn "Error: #{e}" }
      else
        Rulepack::Reporter.print(result, format: opts[:format])
      end
      exit 1
    end

    Rulepack::Reporter.print(result, format: opts[:format] || :text)
    exit(result.partial? ? 1 : 0)
  rescue StandardError => e
    $stderr.puts "❌ Error: #{e.message}"
    exit 1
  end
end
