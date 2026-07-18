# frozen_string_literal: true

require_relative 'encoding_defaults'
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

      unless Rulepack::Common.build_index_path.exist?
        msg = 'Build index not found. Run build first.'
        return Rulepack::Result.new(status: :failure, errors: [msg])
      end

      unless Rulepack::Common.index_yaml_path.exist?
        msg = "Installed index not found at #{Rulepack::Common.index_yaml_path}. Nothing is installed."
        return Rulepack::Result.new(status: :failure, errors: [msg])
      end

      index = Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
      packages = index[:packages] || {}
      registry = Rulepack::Common.load_platform_registry

      targets_to_fix, target_package = begin
        Rulepack::Common.validate_targets_and_packages(
          target_arg, package_arg, packages, registry,
          exit_on_failure: false,
          project_arg: project_arg,
          enforce_project_scope: true
        )
      rescue StandardError => e
        return Rulepack::Result.new(status: :failure, errors: [e.message])
      end

      if targets_to_fix.empty?
        return Rulepack::Result.new(
          status: :success,
          data: { platforms: [], fixed: [], orphans_removed: [] },
          messages: ['ℹ No fixes needed.']
        )
      end

      fixed = []
      failed = []
      orphans_removed = []

      targets_to_fix.each do |platform_id|
        pf = fix_platform(platform_id, target_package, project_arg, dry_run, auto_mode, index)
        fixed.concat(pf[:fixed] || [])
        failed.concat(pf[:failed] || [])
        orphans_removed.concat(pf[:orphans_removed] || [])
      end

      status = failed.empty? ? (fixed.empty? && orphans_removed.empty? ? :success : :success) : :partial
      status = :success if fixed.empty? && orphans_removed.empty? && failed.empty?

      messages = []
      if fixed.any? || orphans_removed.any?
        messages << "\n✅ Fix applied. Run verify to confirm."
      else
        messages << "\nℹ No fixes needed."
      end

      Rulepack::Result.new(
        status: status,
        data: {
          platforms: targets_to_fix,
          fixed: fixed,
          failed: failed,
          orphans_removed: orphans_removed,
          dry_run: dry_run
        },
        messages: messages
      )
    end

    # Execution Helpers

    def run_verify(platform_id, package_arg, project_arg)
      Rulepack::Verify.check(
        target: platform_id,
        package_name: package_arg,
        project_path: project_arg
      )
    end

    def fix_platform(platform_id, package_arg, project_arg, dry_run, auto_mode, index)
      puts "\n── #{platform_id} ──"

      result = run_verify(platform_id, package_arg, project_arg)
      data = result.data || {}
      has_drift = data[:drift].to_i > 0
      orphans = data[:orphans] || []

      unless has_drift || orphans.any?
        puts '  ✓ No drift detected.'
        return { fixed: [], failed: [], orphans_removed: [] }
      end

      fixed = []
      failed = []
      orphans_removed = []

      if has_drift
        fd = fix_drift(platform_id, package_arg, project_arg, dry_run, index)
        fixed.concat(fd[:fixed] || [])
        failed.concat(fd[:failed] || [])
      end

      if orphans.any? && package_arg.nil?
        fo = fix_orphans(orphans, dry_run, auto_mode)
        orphans_removed.concat(fo[:orphans_removed] || [])
      end

      { fixed: fixed, failed: failed, orphans_removed: orphans_removed }
    end

    def fix_drift(platform_id, package_arg, project_arg, dry_run, index)
      if dry_run
        puts "  [DRY-RUN] Would reinstall packages on #{platform_id}"
        return { fixed: [], failed: [] }
      end

      broken = find_broken_packages(platform_id, package_arg, project_arg, index)

      if broken.empty?
        puts '  ✓ No broken packages matched.'
        return { fixed: [], failed: [] }
      end

      # Keep a copy of the original index so we can roll back if reinstall fails.
      original_index = Marshal.load(Marshal.dump(index))
      backup_path = Rulepack::Common.backup_index

      broken.each do |pkgname|
        clear_installed_record(index, pkgname, platform_id)
        puts "  Cleared index record for #{pkgname}"
      end

      puts "  Reinstalling #{broken.size} package(s) on #{platform_id}..."

      fixed = []
      failed = []
      broken.each do |pkgname|
        install_result = Rulepack::Install.run(
          platform_id,
          specific_package: pkgname,
          project_arg: project_arg,
          collision_strategy: 'overwrite',
          dry_run: false
        )
        if install_result.success?
          fixed << pkgname
        else
          failed << pkgname
          puts "  ⚠ Reinstall failed for #{pkgname}: #{install_result.errors.join(', ')}"
          break
        end
      end

      if failed.empty?
        index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        Rulepack::Common.write_yaml_atomic(Rulepack::Common.index_yaml_path, index)
        puts '  ✓ Reinstall complete'
      else
        Rulepack::Common.write_yaml_atomic(Rulepack::Common.index_yaml_path, original_index)
        puts "  ⚠ Reinstall failed; restored original index from backup."
      end

      { fixed: fixed, failed: failed }
    end

    def fix_orphans(orphans, dry_run, auto_mode)
      return { orphans_removed: [] } unless orphans.any?

      puts "\n  #{orphans.size} orphan(s) found:"
      orphans.each { |f| puts "    #{f}" }
      if dry_run
        puts '  [DRY-RUN] Would not remove orphans'
        return { orphans_removed: [] }
      end

      should_remove = if auto_mode
        true
      elsif ENV['RULEPACK_TEST'] || !$stdin.isatty || !$stdout.isatty
        false
      else
        print "\n  \e[33m?\e[0m Remove #{orphans.size} orphan(s)? [y/N] "
        response = $stdin.gets&.chomp&.downcase
        response == 'y' || response == 'yes'
      end

      if should_remove
        puts "  Removing #{orphans.size} orphan(s)..."
        orphans.each { |f| FileUtils.rm_rf(f) }
        puts '  ✓ Orphans removed'
        { orphans_removed: orphans }
      else
        puts '  Skipping orphan removal (use --auto to remove)'
        { orphans_removed: [] }
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
    result = Rulepack::Fix.run(opts)

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
    exit 0
  rescue StandardError => e
    $stderr.puts "❌ Error: #{e.message}"
    exit 1
  end
end
