# frozen_string_literal: true

require_relative 'encoding_defaults'
require 'yaml'
require 'pathname'
require 'fileutils'
require_relative 'common'
require_relative 'installer'
require_relative 'installed_state'

module Rulepack
  module Verify
    module_function

    # Data-returning API. Returns a Rulepack::Result with structured verify
    # data; rendering is the CLI's job (Reporter via the unified render path).
    def check(options = {}, paths: nil, ui: nil)
      if ui
        Rulepack::Common.with_ui(ui) { check(options, paths: paths) }
      elsif paths
        Rulepack::Common.with_paths(paths) { check_unscoped(options) }
      else
        check_unscoped(options)
      end
    end

    def check_unscoped(options = {})
      package_arg = options[:package_name]
      target_arg = options[:target]
      project_arg = options[:project_path]

      unless Rulepack::Common.index_yaml_path.exist?
        msg = "Installed index not found at #{Rulepack::Common.index_yaml_path}. Nothing is installed."
        return Rulepack::Result.new(
          status: :failure,
          errors: [msg],
          messages: [msg]
        )
      end

      index = Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)
      packages = index[:packages] || {}
      registry = Rulepack::Common.load_platform_registry

      targets_to_verify, target_package = Rulepack::Common.validate_targets_and_packages(
        target_arg, package_arg, packages, registry,
        exit_on_failure: false,
        project_arg: project_arg,
        enforce_project_scope: true
      )

      if targets_to_verify.empty?
        return Rulepack::Result.new(
          status: :success,
          data: { ok: 0, drift: 0, orphans: 0, platforms: [] },
          messages: ['  No targets to verify.']
        )
      end

      platforms_data = []
      total_drifts = 0
      total_orphans = 0
      total_ok = 0

      targets_to_verify.each do |platform_id|
        platform_cfg = registry[platform_id.to_sym] || registry[platform_id.to_s]
        base_path = resolve_base_path(platform_cfg, project_arg)

        platform_pkgs = packages.select do |name, pkg|
          next false if target_package && name.to_s != target_package
          pkg[:installed].is_a?(Array) && pkg[:installed].any? { |i| i[:platform] == platform_id }
        end

        platform_result = check_platform(
          platform_id, platform_cfg, base_path, platform_pkgs,
          packages: packages,
          scan_orphans: target_package.nil?
        )

        platforms_data << platform_result
        total_ok += platform_result[:ok]
        total_drifts += platform_result[:drift]
        total_orphans += platform_result[:orphans].size
      end

      status = total_drifts.positive? || total_orphans.positive? ? :partial : :success

      Rulepack::Result.new(
        status: status,
        data: {
          ok: total_ok,
          drift: total_drifts,
          orphans: total_orphans,
          platforms: platforms_data
        },
        messages: build_summary_messages(platforms_data, total_ok, total_drifts, total_orphans)
      )
    end

    def check_platform(platform_id, platform_cfg, base_path, platform_pkgs, packages:, scan_orphans: true)
      items = []

      if platform_pkgs.empty?
        return {
          platform_id: platform_id,
          base_path: base_path,
          ok: 0,
          drift: 0,
          orphans: [],
          items: items,
          message: '  No packages matched or installed.'
        }
      end

      platform_ok = 0
      platform_drifts = 0

      platform_pkgs.each do |pkgname, pkgdata|
        inst = pkgdata[:installed].find { |i| i[:platform] == platform_id }
        target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }

        unless target
          items << {
            pkgname: pkgname.to_s,
            type: :rule,
            status: :missing,
            messages: ["  ⚠ No target for #{pkgname} on #{platform_id} (stale install record)"]
          }
          platform_drifts += 1
          next
        end

        verdict = InstalledState.check(
          installed: inst, target: target, platform_cfg: platform_cfg,
          pkgname: pkgname.to_s, base_path: base_path
        )
        # Only :rule and :skill items historically carried :output; skill-bundle
        # and agent items never did (byte-compatible item shape).
        item = if %i[rule skill].include?(verdict.type)
                 verdict.to_item_h(pkgname: pkgname.to_s, output: inst[:output])
               else
                 verdict.to_item_h(pkgname: pkgname.to_s)
               end

        items << item
        if item[:status] == :ok
          platform_ok += 1
        else
          platform_drifts += 1
        end
      end

      orphans = []
      if scan_orphans
        orphans = scan_orphans_on_disk(platform_id, platform_cfg, base_path, packages)
      end

      {
        platform_id: platform_id,
        base_path: base_path,
        ok: platform_ok,
        drift: platform_drifts,
        orphans: orphans,
        items: items,
        message: "  #{platform_ok} OK | #{platform_drifts} drift(s) | #{orphans.size} orphan(s)"
      }
    end

    def build_summary_messages(platforms_data, total_ok, total_drifts, total_orphans)
      messages = []
      messages << "\n── Summary (#{platforms_data.size} platform(s)) ──"
      messages << "  #{total_ok} package(s) OK"
      messages << "  #{total_drifts} drift(s)" if total_drifts.positive?
      messages << "  #{total_orphans} orphan(s)" if total_orphans.positive?
      messages
    end

    def resolve_base_path(platform_cfg, project_arg)
      project_root = Rulepack::Common.project_root_for(platform_cfg, project_arg)
      project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
    end

    # Legacy orphan scanner kept for backward compatibility.
    # Prefer Rulepack::PlatformScanner for new code.
    def scan_orphans(platform_id, platform_cfg, base_path, packages)
      scan_orphans_on_disk(platform_id, platform_cfg, base_path, packages).map { |o| o[:path].to_s }
    end

    def scan_orphans_on_disk(platform_id, platform_cfg, base_path, packages)
      return [] unless platform_cfg[:type] == 'directory'

      dirs_to_scan = []
      if platform_cfg[:rules_dir] && !platform_cfg[:rules_dir].to_s.empty?
        dirs_to_scan << base_path.join(platform_cfg[:rules_dir])
      end
      if platform_cfg[:skills_dir] && !platform_cfg[:skills_dir].to_s.empty?
        dirs_to_scan << base_path.join(platform_cfg[:skills_dir])
      end

      expected_top = Set.new
      packages.each_value do |pkgdata|
        (pkgdata[:installed] || []).each do |inst|
          next unless inst[:platform] == platform_id

          target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
          next unless target

          p = Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
          expected_top << p.to_s
        end
      end

      orphans = []
      dirs_to_scan.each do |dir|
        next unless dir.exist?

        Dir.entries(dir).each do |entry|
          full = File.join(dir, entry)
          next if ['.', '..'].include?(entry)
          next if expected_top.include?(full)
          next if entry.start_with?('.')
          next if entry == 'manifest.json'
          next if File.directory?(full) && expected_top.any? { |e| e.start_with?("#{full}/") || e == full }

          orphans << {
            path: Pathname.new(full),
            platform: platform_id,
            source: :manual,
            type: :orphan,
            status: :orphan
          }
        end
      end

      orphans
    end
  end
end

