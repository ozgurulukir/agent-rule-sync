# frozen_string_literal: true

require 'set'
require 'pathname'

module Rulepack
  # Scans platform directories on disk and compares them with the rulepack index.
  # Used by both Verify and Query to detect manual/orphaned installations.
  module PlatformScanner
    module_function

    # Returns a hash of installed items for a platform, merging rulepack-managed
    # records from the index with manually installed files/dirs found on disk.
    #
    # Options:
    #   platform_id  - platform identifier (e.g. 'opencode')
    #   platform_cfg - platform registry config hash
    #   base_path    - resolved install base path (Pathname)
    #   packages     - index packages hash
    #   verify       - if true, include drift/missing status by checking checksums
    #
    # Returns a Result with data: { platform_id, base_path, items: [...] }
    def scan_platform(platform_id:, platform_cfg:, base_path:, packages:, verify: false)
      items = []

      # Rulepack-managed items from the index
      packages.each do |pkgname, pkgdata|
        Array(pkgdata[:installed]).each do |rec|
          next unless rec[:platform].to_s == platform_id.to_s

          item = index_item(pkgname, pkgdata, rec, platform_cfg, base_path)
          item[:status] = verify_status(item) if verify
          items << item
        end
      end

      # Manual items found on disk but not in the index (directory platforms only)
      if platform_cfg[:type].to_s == 'directory'
        items.concat(scan_orphans(platform_cfg, base_path, items))
      end

      Rulepack::Result.new(
        status: :success,
        data: {
          platform_id: platform_id,
          base_path: base_path,
          items: items
        }
      )
    end

    # Scan rules_dir and skills_dir for entries not tracked in the given items.
    def scan_orphans(platform_cfg, base_path, tracked_items)
      orphans = []
      tracked_paths = tracked_items.map { |i| Pathname.new(i[:path]).expand_path.to_s }.to_set

      dirs_to_scan = []
      if platform_cfg[:rules_dir] && !platform_cfg[:rules_dir].to_s.empty?
        dirs_to_scan << base_path.join(platform_cfg[:rules_dir])
      end
      if platform_cfg[:skills_dir] && !platform_cfg[:skills_dir].to_s.empty?
        dirs_to_scan << base_path.join(platform_cfg[:skills_dir])
      end

      dirs_to_scan.each do |dir|
        next unless dir.exist? && dir.directory?

        dir.children.each do |child|
          next if child.basename.to_s.start_with?('.')
          next if child.basename.to_s == 'manifest.json'
          next if tracked_paths.include?(child.expand_path.to_s)

          type = infer_type(child, platform_cfg)
          orphans << {
            name: child.basename.to_s,
            type: type,
            source: :manual,
            status: :orphan,
            path: child,
            pkgname: nil,
            platform: platform_cfg[:id]
          }
        end
      end

      orphans
    end

    def index_item(pkgname, pkgdata, rec, platform_cfg, base_path)
      target = Array(pkgdata[:targets]).find { |t| t[:platform].to_s == rec[:platform].to_s }
      path = if target
               Rulepack::Common.resolve_install_path(platform_cfg, target, base_path)
             else
               base_path.join(rec[:output].to_s)
             end

      format = target ? target[:format].to_s : 'rule'
      type = infer_type_from_format(format, path)

      {
        name: pkgname.to_s,
        type: type,
        source: :rulepack,
        status: :ok,
        path: path,
        pkgname: pkgname.to_s,
        platform: rec[:platform].to_s,
        output: rec[:output].to_s,
        checksum: rec[:checksum],
        installed_at: rec[:installed_at]
      }
    end

    def infer_type(child, platform_cfg)
      skills_dir = platform_cfg[:skills_dir] ? platform_cfg[:skills_dir].to_s.sub(%r{/\z}, '') : nil
      rules_dir = platform_cfg[:rules_dir] ? platform_cfg[:rules_dir].to_s.sub(%r{/\z}, '') : nil
      agents_dir = platform_cfg[:agents_dir] ? platform_cfg[:agents_dir].to_s.sub(%r{/\z}, '') : nil

      rel = child.relative_path_from(platform_cfg[:base_path] ? Pathname.new(platform_cfg[:base_path]).expand_path : child.parent).to_s
      case rel
      when %r{\A#{Regexp.escape(skills_dir)}/} then :skill
      when %r{\A#{Regexp.escape(rules_dir)}/} then :rule
      when %r{\A#{Regexp.escape(agents_dir)}/} then :agent
      else
        child.directory? ? :skill_bundle : :skill
      end
    end

    def infer_type_from_format(format, path)
      case format
      when 'skill-bundle' then :skill_bundle
      when 'agent' then :agent
      when 'skill' then :skill
      else
        path.directory? ? :skill_bundle : :rule
      end
    end

    def verify_status(item)
      return :missing unless item[:path].exist?

      # For files with a checksum, verify it; otherwise assume ok.
      if item[:checksum] && item[:path].file?
        actual = Digest::SHA256.hexdigest(item[:path].read)
        actual == item[:checksum] ? :ok : :drift
      else
        :ok
      end
    end
  end
end
