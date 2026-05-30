# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'set'
require 'stringio'
require_relative 'common'
require_relative 'installer'
require_relative 'verify'
require_relative 'cli_parser'

module Rulepack
  module Fix
    module_function

    def run(options = {})
      package_arg = options[:package_name]
      target_arg = options[:target]
      project_arg = options[:project_path]
      dry_run = options.fetch(:dry_run, false)
      auto_mode = options.fetch(:auto, false)
      exit_on_failure = options.fetch(:exit_on_failure, false)

      unless Rulepack::Common.build_index_path.exist?
        msg = 'Build index not found. Run build first.'
        exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
      end

      unless Rulepack::Common.index_yaml_path.exist?
        msg = "Installed index not found at #{Rulepack::Common.index_yaml_path}. Nothing is installed."
        exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
      end

      index = Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
      packages = index[:packages] || {}
      registry = Rulepack::Common.load_platform_registry

      targets_to_fix, target_package = Rulepack::Common.validate_targets_and_packages(
        target_arg, package_arg, packages, registry,
        exit_on_failure: exit_on_failure,
        project_arg: project_arg,
        enforce_project_scope: true
      )
      return false if targets_to_fix.empty?

      fixed_anything = false
      targets_to_fix.each do |platform_id|
        fixed_anything |= fix_platform(platform_id, target_package, project_arg, dry_run, auto_mode, index)
      end

      if fixed_anything
        puts "\n✅ Fix applied. Run verify to confirm."
      else
        puts "\nℹ No fixes needed."
      end

      exit 0 if exit_on_failure

      fixed_anything
    end

    # Execution Helpers

    def run_verify(platform_id, package_arg, project_arg)
      Rulepack::Verify.run(
        target: platform_id,
        package_name: package_arg,
        project_path: project_arg,
        exit_on_failure: false
      )
    end

    def fix_platform(platform_id, package_arg, project_arg, dry_run, auto_mode, index)
      puts "\n── #{platform_id} ──"

      result = run_verify(platform_id, package_arg, project_arg)
      has_drift = result[:drift].to_i > 0
      orphans = result[:orphans] || []

      unless has_drift || orphans.any?
        puts '  ✓ No drift detected.'
        return false
      end

      fixed_drift = false
      if has_drift
        fixed_drift = fix_drift(platform_id, package_arg, project_arg, dry_run, index)
      end

      fixed_orphans = false
      if orphans.any? && package_arg.nil?
        fixed_orphans = fix_orphans(orphans, dry_run, auto_mode)
      end

      fixed_drift || fixed_orphans
    end
    def fix_drift(platform_id, package_arg, project_arg, dry_run, index)
      if dry_run
        puts "  [DRY-RUN] Would reinstall packages on #{platform_id}"
        return false
      end

      broken = find_broken_packages(platform_id, package_arg, project_arg, index)

      if broken.empty?
        puts '  ✓ No broken packages matched.'
        return false
      end

      broken.each do |pkgname|
        clear_installed_record(index, pkgname, platform_id)
        puts "  Cleared index record for #{pkgname}"
      end

      index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      Rulepack::Common.write_yaml_atomic(Rulepack::Common.index_yaml_path, index)

      puts "  Reinstalling #{broken.size} package(s) on #{platform_id}..."

      broken.each do |pkgname|
        begin
          Rulepack::Install.run(
            platform_id,
            specific_package: pkgname,
            project_arg: project_arg,
            collision_strategy: 'overwrite',
            dry_run: false
          )
        rescue StandardError => e
          puts "  ⚠ Reinstall failed for #{pkgname}: #{e.message}"
        end
      end

      puts '  ✓ Reinstall complete'
      true
    end

    def fix_orphans(orphans, dry_run, auto_mode)
      return false unless orphans.any?

      puts "\n  #{orphans.size} orphan(s) found:"
      orphans.each { |f| puts "    #{f}" }
      if dry_run
        puts '  [DRY-RUN] Would not remove orphans'
        false
      elsif auto_mode
        puts "  Removing #{orphans.size} orphan(s)..."
        orphans.each { |f| FileUtils.rm_rf(f) }
        puts '  ✓ Orphans removed'
        true
      else
        puts '  Skipping orphan removal (use --auto to remove)'
        false
      end
    end

    def clear_installed_record(index, pkgname, platform_id)
      pkgdata = index[:packages][pkgname.to_sym] || index[:packages][pkgname.to_s]
      return unless pkgdata
      return unless pkgdata[:installed].is_a?(Array)

      pkgdata[:installed].reject! { |r| r[:platform] == platform_id }
    end

    def find_broken_packages(platform_id, package_arg, project_arg, index)
      platform_cfg = Rulepack::Common.platform_config(platform_id, Rulepack::Common.load_platform_registry)
      return [] unless platform_cfg

      project_root = project_arg ? Pathname.new(project_arg).expand_path : nil
      base_path = project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
      broken = []

      (index[:packages] || {}).each do |pkgname, pkgdata|
        next if package_arg && pkgname.to_s != package_arg
        inst = pkgdata[:installed].is_a?(Array) && pkgdata[:installed].find { |i| i[:platform] == platform_id }
        next unless inst

        target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
        format_type = target ? target[:format] : 'directory'

        is_broken = if format_type == 'skill-bundle'
                      if !platform_cfg[:skills_dir] && %w[skill import].include?(platform_cfg[:type].to_s)
                        false
                      else
                        bundle_path = resolve_install_path(platform_cfg, target, base_path)
                        !bundle_path.exist?
                      end
                    elsif format_type == 'skill' && platform_cfg[:type] == 'skill'
                      !Rulepack::Common.build_dir.join(platform_id, pkgname.to_s, inst[:output]).exist?
                    elsif format_type == 'agent'
                      # Agents are directories; checksum-based detection does not apply.
                      # Platforms without agents_dir silently report "not broken".
                      agents_dir = platform_cfg[:agents_dir]
                      unless agents_dir
                        is_broken = false
                      else
                        target_dir = (target[:install] && target[:install][:target_dir]) || inst[:output] || pkgname.to_s
                        is_broken = !base_path.join(agents_dir, target_dir).exist?
                      end
                    else
                      installed_path = resolve_install_path(platform_cfg, target, base_path)
                      !installed_path.exist? || !Rulepack::Common.verify_checksum(installed_path, inst[:checksum], pkgname.to_s)
                    end

        broken << pkgname.to_s if is_broken
      end

      broken
    end

    def resolve_install_path(platform_cfg, target, base_path)
      if target
        Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
      else
        base_path
      end
    end
  end
end

# CLI runner block
if __FILE__ == $PROGRAM_NAME || caller.any? { |c| c.include?('capture_script_run') || c.include?('invoke') }
  begin
    opts = Rulepack::CliParser.parse(ARGV)
    Rulepack::Fix.run(opts.merge(exit_on_failure: true))
  rescue StandardError => e
    $stderr.puts "❌ Error: #{e.message}"
    exit 1
  end
end
