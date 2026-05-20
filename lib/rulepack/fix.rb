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
        if exit_on_failure
          abort "❌ Error: #{msg}"
        else
          raise msg
        end
      end

      unless Rulepack::Common::INDEX_YAML_PATH.exist?
        msg = "Installed index not found at #{Rulepack::Common::INDEX_YAML_PATH}. Nothing is installed."
        if exit_on_failure
          abort "❌ Error: #{msg}"
        else
          raise msg
        end
      end

      index = Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
      packages = index[:packages] || {}
      registry = Rulepack::Common.load_platform_registry

      # ─── Exact package validation ──────────────────────────────────────────────────

      target_package = nil
      if package_arg
        unless packages.key?(package_arg) || packages.key?(package_arg.to_sym)
          msg = "Package '#{package_arg}' is not registered as installed in index."
          if exit_on_failure
            abort "❌ Error: #{msg}"
          else
            raise msg
          end
        end
        target_package = packages.keys.find { |k| k.to_s == package_arg }.to_s
      end

      # ─── Target platform checks (MANDATORY) ────────────────────────────────────────

      unless target_arg
        msg = "Please specify target platform(s) with --target <platform> (or --target all)."
        if exit_on_failure
          abort "❌ Error: #{msg}"
        else
          raise msg
        end
      end

      targets_to_fix = []
      if target_arg.to_s.downcase == 'all'
        if target_package
          pkg_idx = packages[target_package.to_sym] || packages[target_package.to_s] || {}
          targets_to_fix = (pkg_idx[:installed] || []).map { |i| i[:platform] }.uniq
        else
          platforms = Set.new
          packages.each_value do |pkg|
            (pkg[:installed] || []).each { |i| platforms << i[:platform] }
          end
          targets_to_fix = platforms.to_a
        end
      else
        targets_to_fix = target_arg.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      if targets_to_fix.empty?
        puts "  No targets to fix."
        return false
      end

      # ─── Project-scoped platform validation ───────────────────────────────────────
      targets_to_fix.each do |platform_id|
        platform_cfg = registry[platform_id.to_sym] || registry[platform_id.to_s]
        unless platform_cfg
          msg = "Unknown target platform '#{platform_id}'."
          exit_on_failure ? abort("❌ Error: #{msg}") : raise(msg)
        end
        Rulepack::Common.project_root_for(platform_cfg, project_arg)
      end

      fixed_anything = false
      targets_to_fix.each do |platform_id|
        fixed_anything |= fix_platform(platform_id, target_package, project_arg, dry_run, auto_mode)
      end

      if fixed_anything
        puts "\n✅ Fix applied. Run verify to confirm."
      else
        puts "\nℹ No fixes needed."
      end

      if exit_on_failure
        exit 0
      end

      fixed_anything
    end

    # Execution Helpers

    def run_verify(platform_id, package_arg, project_arg)
      # Capture verify run output cleanly
      out = StringIO.new
      $stdout = out
      begin
        Rulepack::Verify.run(
          target: platform_id,
          package_name: package_arg,
          project_path: project_arg,
          exit_on_failure: false
        )
      rescue StandardError => e
        out.puts "Verify failed: #{e.message}"
      ensure
        $stdout = STDOUT
      end
      out.string
    end

    def fix_platform(platform_id, package_arg, project_arg, dry_run, auto_mode)
      puts "\n── #{platform_id} ──"

      cmd_out = run_verify(platform_id, package_arg, project_arg)
      # Re-print relevant lines
      cmd_out.each_line { |l| puts l if l =~ /[✓⚠?]/ }
      has_drift = cmd_out.include?('⚠')
      orphans = cmd_out.scan(/^\s*\?\s+ORPHAN:\s+(.+)$/).flatten

      unless has_drift || orphans.any?
        puts '  ✓ No drift detected.'
        return false
      end

      fixed_drift = false
      if has_drift
        fixed_drift = fix_drift(platform_id, package_arg, project_arg, dry_run)
      end

      fixed_orphans = false
      if orphans.any? && package_arg.nil? # Only clean orphans if verifying entire platform
        fixed_orphans = fix_orphans(orphans, dry_run, auto_mode)
      end

      fixed_drift || fixed_orphans
    end

    def fix_drift(platform_id, package_arg, project_arg, dry_run)
      if dry_run
        puts "  [DRY-RUN] Would reinstall packages on #{platform_id}"
        return false
      end

      index = Rulepack::Common.load_yaml(Rulepack::Common::INDEX_YAML_PATH)
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
      Rulepack::Common.write_yaml_atomic(Rulepack::Common::INDEX_YAML_PATH, index)
      
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
                      bundle_path = resolve_install_path(platform_cfg, target, base_path)
                      !bundle_path.exist?
                    elsif format_type == 'skill' && platform_cfg[:type] == 'skill'
                      !Rulepack::Common::BUILD_DIR.join(platform_id, pkgname.to_s, inst[:output]).exist?
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
