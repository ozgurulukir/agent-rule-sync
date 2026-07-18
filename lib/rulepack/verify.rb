# frozen_string_literal: true

require_relative 'encoding_defaults'
require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require_relative 'common'
require_relative 'installer'
require_relative 'cli_parser'

module Rulepack
  module Verify
    module_function

    # CLI entry point — parses options, calls check, and renders output.
    def run(options = {})
      result = check(options)
      Rulepack::Reporter.print(result, format: options[:format] || :text, out: options.fetch(:output, $stdout))

      if options[:exit_on_failure]
        exit(result.failure? ? 1 : 0)
      end

      result.data || { ok: 0, drift: 0, orphans: 0 }
    end

    # Data-returning API. Returns a Rulepack::Result with structured verify data.
    def check(options = {})
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
        format_type = target ? target[:format] : 'directory'

        installed_path = if inst[:target_path]
                           Pathname.new(inst[:target_path])
                         else
                           Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
                         end

        item = if format_type == 'skill' && platform_cfg[:type] == 'skill'
                 verify_skill_build_artifact(platform_id, pkgname, inst[:output], inst[:checksum])
               elsif format_type == 'agent'
                 verify_agent_on_disk(platform_cfg, target, base_path, pkgname)
               elsif format_type == 'skill-bundle'
                 verify_skill_bundle_on_disk(installed_path, pkgname)
               else
                 verify_single_file_on_disk(installed_path, inst[:checksum], pkgname, inst[:output])
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

    # Helper verification functions — now return structured item hashes.

    def resolve_base_path(platform_cfg, project_arg)
      project_root = Rulepack::Common.project_root_for(platform_cfg, project_arg)
      project_root || Pathname.new(Rulepack::Common.expand_user_path(platform_cfg[:base_path]))
    end

    def verify_single_file_on_disk(path, expected_checksum, pkgname, expected_output)
      item = {
        pkgname: pkgname,
        output: expected_output,
        path: path,
        type: :rule,
        status: :ok,
        messages: []
      }

      unless path.exist?
        item[:status] = :missing
        item[:messages] << "  ⚠ MISSING: #{pkgname} (#{expected_output}) at #{path}"
        return item
      end

      if Rulepack::Common.verify_checksum(path, expected_checksum, pkgname)
        item[:messages] << "  ✓ #{pkgname} (#{expected_output})"
      else
        item[:status] = :drift
        item[:messages] << "  ⚠ CHECKSUM mismatch: #{pkgname} (#{expected_output})"
      end
      item
    end

    def verify_skill_build_artifact(platform_id, pkgname, expected_output, expected_checksum)
      build_artifact = Rulepack::Common.build_dir.join(platform_id, pkgname.to_s, expected_output)
      item = {
        pkgname: pkgname,
        output: expected_output,
        path: build_artifact,
        type: :skill,
        status: :ok,
        messages: []
      }

      unless build_artifact.exist?
        item[:status] = :missing
        item[:messages] << "  ⚠ MISSING build artifact: #{pkgname} (#{build_artifact})"
        return item
      end

      actual_sha = Digest::SHA256.hexdigest(build_artifact.read)
      if actual_sha == expected_checksum
        item[:messages] << "  ✓ #{pkgname} (#{expected_output}) — build artifact OK"
      else
        item[:status] = :drift
        item[:messages] << "  ⚠ CHECKSUM mismatch (build artifact): #{pkgname}"
      end
      item
    end

    def verify_skill_bundle_on_disk(bundle_path, pkgname)
      manifest_path = bundle_path.join('manifest.json')
      item = {
        pkgname: pkgname,
        path: bundle_path,
        type: :skill_bundle,
        status: :ok,
        messages: [],
        files: []
      }

      unless manifest_path.exist?
        item[:status] = :missing
        item[:messages] << "  ⚠ MISSING manifest: #{pkgname} at #{manifest_path}"
        return item
      end

      manifest = JSON.parse(manifest_path.read)
      all_ok = true
      total_files = 0
      Array(manifest['sub_skills']).each do |sub_skill|
        (sub_skill['files'] || {}).each do |rel_path, expected_sha|
          total_files += 1
          file_path = bundle_path.join(rel_path)
          file_item = { path: rel_path, expected: expected_sha }
          unless file_path.exist?
            file_item[:status] = :missing
            item[:messages] << "  ⚠ MISSING: #{pkgname}/#{rel_path}"
            all_ok = false
            next
          end
          actual_sha = Digest::SHA256.hexdigest(file_path.read)
          if actual_sha == expected_sha
            file_item[:status] = :ok
          else
            file_item[:status] = :drift
            item[:messages] << "  ⚠ CHECKSUM mismatch: #{pkgname}/#{rel_path}"
            all_ok = false
          end
          item[:files] << file_item
        end
      end

      if all_ok
        sub_count = Array(manifest['sub_skills']).size
        item[:messages] << "  ✓ #{pkgname} (skill-bundle, #{sub_count} sub-skill(s), #{total_files} file(s))"
      else
        item[:status] = :drift
      end
      item
    end

    def verify_agent_on_disk(platform_cfg, target_cfg, base_path, pkgname)
      agents_dir = platform_cfg[:agents_dir]
      item = {
        pkgname: pkgname,
        type: :agent,
        status: :ok,
        messages: []
      }

      unless agents_dir
        item[:messages] << "  ⊘ #{pkgname}: no agent support, skipping verify"
        return item
      end

      install_cfg = target_cfg[:install] || {}
      target_dir = install_cfg[:target_dir] || target_cfg[:output] || pkgname.to_s
      agent_path = base_path.join(agents_dir, target_dir)
      item[:path] = agent_path

      unless agent_path.exist?
        item[:status] = :missing
        item[:messages] << "  ⚠ MISSING: #{pkgname} (agent) at #{agent_path}"
        return item
      end

      item[:messages] << "  ✓ #{pkgname} (agent)"
      item
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

# CLI runner block
if __FILE__ == $PROGRAM_NAME || caller.any? { |c| c.include?('capture_script_run') }
  begin
    opts = Rulepack::CliParser.parse(ARGV)
    Rulepack::Verify.run(opts.merge(exit_on_failure: true))
  rescue StandardError => e
    $stderr.puts "❌ Error: #{e.message}"
    exit 1
  end
end
