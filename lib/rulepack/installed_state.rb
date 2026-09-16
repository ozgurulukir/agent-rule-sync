# frozen_string_literal: true

# InstalledState — the single owner of "is this installed record intact on
# disk?" One dispatch, one verdict, consumed by Verify (item hashes), Fix
# (brokenness) and InstallExecute's check command (error strings).
#
# Before this module the same (format × platform) case-split existed in three
# divergent copies (install_execute.rb#verify_package_on_disk, verify.rb's
# per-format helpers, fix.rb#find_broken_packages). The branch semantics here
# are the superset (InstallExecute's), with Verify's strictly-more-correct
# agent target_dir fallback order.
#
# Pure: no Emitter, no UI, no puts — narration belongs to the callers.

require 'digest'
require 'json'
require_relative 'common'
require_relative 'models/installed_record'
require_relative 'models/target'

module Rulepack
  module InstalledState
    Verdict = Data.define(:status, :type, :path, :messages, :files) do
      # rubocop:disable Lint/StructNewOverride
      # status: :ok | :missing | :drift | :skipped
      def ok?     = status == :ok
      def skipped? = status == :skipped
      # Fix's contract: only genuine breakage counts; skipped checks are not
      # breakage.
      def broken? = status == :missing || status == :drift

      # Verify's item-hash contract (byte-compatible with the historical
      # verify.rb output; pkgname/output vary per branch so they are passed in).
      # Historical quirk preserved here: missing bundle files are tracked on
      # the Verdict but excluded from Verify's item files array.
      def to_item_h(pkgname:, output: nil)
        item = { pkgname: pkgname, type: type, status: item_status, messages: messages.dup }
        item[:output] = output if output
        item[:path] = path if path
        item[:files] = files.reject { |f| f[:status] == :missing }.map(&:dup) if files
        item
      end

      # InstallExecute check-command contract: nil when fine, an error string
      # otherwise. Message style matches the deleted verify_package_on_disk
      # strings (no ⚠, no indentation).
      def to_error_s(pkgname, output: nil)
        return nil if ok? || skipped?

        case type
        when :skill
          status == :missing ? "Build artifact missing: #{pkgname} (#{path})" : "Build artifact checksum mismatch: #{pkgname}"
        when :skill_bundle
          if status == :missing && messages.first.to_s.start_with?('  ⚠ MISSING manifest')
            "#{pkgname}: no manifest"
          elsif status == :missing
            "Skill-bundle directory missing: #{path}"
          elsif status == :drift && files&.any?
            files.select { |f| f[:status] != :ok }
                 .map { |f| "#{f[:status] == :missing ? 'missing' : 'checksum mismatch'}: #{f[:path]}" }
                 .map { |m| "#{pkgname}: #{m}" }.join('; ')
          else
            "#{pkgname}: manifest unreadable"
          end
        when :agent
          "Missing agent: #{pkgname} at #{path}"
        else
          if status == :missing
            "Missing: #{pkgname} (#{output}) at #{path}"
          else
            "Checksum mismatch: #{pkgname} (#{output})"
          end
        end
      end

      private

      # Verify reports skipped checks as :ok items carrying the ⊘ message.
      def item_status = skipped? ? :ok : status
      # rubocop:enable Lint/StructNewOverride
    end

    module_function

    # The one dispatch. `installed` and `target` are the raw index/target
    # hashes callers already hold; InstalledRecord.from_h owns the record
    # boundary. paths: follows the Fix.run precedent (Common.with_paths wrap).
    def check(installed:, target:, platform_cfg:, pkgname:, base_path:, paths: nil)
      if paths
        Rulepack::Common.with_paths(paths) { check_unscoped(installed, target, platform_cfg, pkgname, base_path) }
      else
        check_unscoped(installed, target, platform_cfg, pkgname, base_path)
      end
    end

    def check_unscoped(installed, target, platform_cfg, pkgname, base_path)
      record = InstalledRecord.from_h(installed || {})
      format = record.canonical_format(target && target[:format])

      # Legacy records with no build target have no reliable install path to
      # re-derive; nothing sound to check on disk (Fix treated these as
      # not-broken).
      unless target
        return Verdict.new(status: :skipped, type: :rule, path: nil,
                           messages: ["  ⊘ #{pkgname}: no build target for this platform, skipping verify"], files: nil)
      end

      if format == 'skill' && platform_cfg[:type] == 'skill'
        check_skill_build_artifact(record, pkgname, platform_cfg)
      elsif format == 'agent'
        # Agent dispatch precedes the materializable/no-skills_dir branch:
        # agents install to agents_dir regardless of skills_dir, so the
        # agents_dir presence check is the well-defined semantics.
        check_agent(record, target, platform_cfg, pkgname, base_path)
      elsif Target.materializable_format?(format) && !platform_cfg[:skills_dir]
        check_materializable_no_skills_dir(record.platform, platform_cfg, pkgname)
      elsif Target.materializable_format?(format)
        check_skill_bundle(resolve_installed_path(record, target, platform_cfg, base_path), pkgname)
      else
        check_single_file(record, target, platform_cfg, pkgname, base_path)
      end
    end

    def check_skill_build_artifact(record, pkgname, platform_cfg)
      build_artifact = Rulepack::Common.build_dir.join(record.platform, pkgname.to_s, record.output)
      messages = []
      return Verdict.new(status: :missing, type: :skill, path: build_artifact,
                         messages: ["  ⚠ MISSING build artifact: #{pkgname} (#{build_artifact})"], files: nil) unless build_artifact.exist?

      if Digest::SHA256.hexdigest(build_artifact.read) == record.checksum
        messages << "  ✓ #{pkgname} (#{record.output}) — build artifact OK"
        Verdict.new(status: :ok, type: :skill, path: build_artifact, messages: messages, files: nil)
      else
        Verdict.new(status: :drift, type: :skill, path: build_artifact,
                    messages: ["  ⚠ CHECKSUM mismatch (build artifact): #{pkgname}"], files: nil)
      end
    end

    # Materializable format on a platform without skills_dir: nothing to
    # verify on disk for skill/import-type platforms (aggregation owns the
    # content); otherwise the lazy build/<plat>/<pkg>/ tree must exist.
    def check_materializable_no_skills_dir(platform_id, platform_cfg, pkgname)
      return Verdict.new(status: :ok, type: :skill_bundle, path: nil,
                         messages: ["  ⊘ #{pkgname}: no skills_dir on #{platform_cfg[:type]} platform, nothing to verify"], files: nil) if
        %w[skill import].include?(platform_cfg[:type].to_s)

      build_tree = Rulepack::Common.build_dir.join(platform_id, pkgname.to_s)
      if build_tree.exist?
        Verdict.new(status: :ok, type: :skill_bundle, path: build_tree, messages: [], files: nil)
      else
        Verdict.new(status: :missing, type: :skill_bundle, path: build_tree,
                    messages: ["  ⚠ MISSING build tree: #{pkgname} (#{build_tree})"], files: nil)
      end
    end

    def check_agent(record, target, platform_cfg, pkgname, base_path)
      agents_dir = platform_cfg[:agents_dir]
      unless agents_dir
        return Verdict.new(status: :skipped, type: :agent, path: nil,
                           messages: ["  ⊘ #{pkgname}: no agent support, skipping verify"], files: nil)
      end

      install_cfg = (target && target[:install]) || {}
      target_dir = install_cfg[:target_dir] || (target && target[:output]) || record.output || pkgname.to_s
      agent_path = base_path.join(agents_dir, target_dir)

      if agent_path.exist?
        Verdict.new(status: :ok, type: :agent, path: agent_path, messages: ["  ✓ #{pkgname} (agent)"], files: nil)
      else
        Verdict.new(status: :missing, type: :agent, path: agent_path,
                    messages: ["  ⚠ MISSING: #{pkgname} (agent) at #{agent_path}"], files: nil)
      end
    end

    def check_skill_bundle(bundle_path, pkgname)
      unless bundle_path.directory?
        return Verdict.new(status: :missing, type: :skill_bundle, path: bundle_path,
                           messages: ["  ⚠ MISSING: #{pkgname} (skill-bundle) at #{bundle_path}"], files: nil)
      end

      manifest_path = bundle_path.join('manifest.json')
      unless manifest_path.exist?
        return Verdict.new(status: :missing, type: :skill_bundle, path: bundle_path,
                           messages: ["  ⚠ MISSING manifest: #{pkgname} at #{manifest_path}"], files: nil)
      end

      begin
        manifest = JSON.parse(manifest_path.read)
      rescue StandardError
        return Verdict.new(status: :drift, type: :skill_bundle, path: bundle_path,
                           messages: ["  ⚠ Manifest unreadable: #{pkgname} at #{manifest_path}"], files: nil)
      end

      files = []
      messages = []
      all_ok = true
      Array(manifest['sub_skills']).each do |sub_skill|
        (sub_skill['files'] || {}).each do |rel_path, expected_sha|
          file_path = bundle_path.join(rel_path)
          file_item = { path: rel_path, expected: expected_sha }
          unless file_path.exist?
            file_item[:status] = :missing
            messages << "  ⚠ MISSING: #{pkgname}/#{rel_path}"
            all_ok = false
            files << file_item
            next
          end
          if Digest::SHA256.hexdigest(file_path.read) == expected_sha
            file_item[:status] = :ok
          else
            file_item[:status] = :drift
            messages << "  ⚠ CHECKSUM mismatch: #{pkgname}/#{rel_path}"
            all_ok = false
          end
          files << file_item
        end
      end

      if all_ok
        sub_count = Array(manifest['sub_skills']).size
        total_files = files.size
        messages << "  ✓ #{pkgname} (skill-bundle, #{sub_count} sub-skill(s), #{total_files} file(s))"
      end
      Verdict.new(status: all_ok ? :ok : :drift, type: :skill_bundle, path: bundle_path,
                  messages: messages, files: files)
    end

    def check_single_file(record, target, platform_cfg, pkgname, base_path)
      installed_path = resolve_installed_path(record, target, platform_cfg, base_path)
      unless installed_path.exist?
        return Verdict.new(status: :missing, type: :rule, path: installed_path,
                           messages: ["  ⚠ MISSING: #{pkgname} (#{record.output}) at #{installed_path}"], files: nil)
      end

      if Rulepack::Common.verify_checksum(installed_path, record.checksum, pkgname.to_s)
        Verdict.new(status: :ok, type: :rule, path: installed_path,
                    messages: ["  ✓ #{pkgname} (#{record.output})"], files: nil)
      else
        Verdict.new(status: :drift, type: :rule, path: installed_path,
                    messages: ["  ⚠ CHECKSUM mismatch: #{pkgname} (#{record.output})"], files: nil)
      end
    end

    def resolve_installed_path(record, target, platform_cfg, base_path)
      return Pathname.new(record.target_path) if record.target_path

      Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
    end
  end
end
