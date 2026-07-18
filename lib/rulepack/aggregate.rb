# frozen_string_literal: true

# Aggregate skills for skill-based agents
# Reads built skill fragments from Rulepack::Common::BUILD_DIR and combines them with common/agent-specific skills
# Output: Rulepack::Common::BUILD_DIR/<agent>/skills/vendor/<agent>.md

require_relative 'encoding_defaults'
require 'yaml'
require 'pathname'
require 'fileutils'
require_relative 'common'
require_relative 'cli_parser'

module Rulepack
  module Aggregate
    module_function

    def run(options = {})
      target_filter = options[:target]

      unless Rulepack::Common::BUILD_INDEX_PATH.exist?
        msg = "Build index not found: #{Rulepack::Common::BUILD_INDEX_PATH}. Run build first."
        raise msg
      end

      # Load build index (package metadata) with symbol keys
      index = YAML.safe_load(Rulepack::Common::BUILD_INDEX_PATH.read, permitted_classes: [Symbol], symbolize_names: true)
      platforms = Rulepack::Common.load_platform_registry

      # Identify skill-based agents
      skill_agents = platforms.select { |_id, cfg| cfg[:type] == :skill || cfg[:type] == 'skill' }.keys

      if target_filter
        skill_agents = skill_agents.select { |agent_id| agent_id.to_s == target_filter.to_s }
      end

      if skill_agents.empty?
        puts 'ℹ️ No skill-based agents matched or configured in registry.'
        return true
      end

      puts "Base platform registry vendor skills..."
      puts "🔧 Aggregating vendor skills for: #{skill_agents.join(', ')}\n"

      # ─── Process each skill agent ──────────────────────────────────────────────────

      skill_agents.each do |agent_id|
        platform_cfg = platforms[agent_id]
        puts "Generating vendor skill for #{agent_id} (#{platform_cfg[:display_name]})..."

        content_parts = []

        # Header: optional inline header from platform config or agent-specific header file
        if platform_cfg[:vendor_header]
          content_parts << platform_cfg[:vendor_header]
          puts '  ✓ vendor header (from registry)'
        else
          header_file = Rulepack::Common::RULEPACK_ROOT.join('data', 'skills').join('agent-specific', agent_id.to_s, 'header.md')
          if header_file.exist?
            content_parts << header_file.read
            puts "  ✓ header from #{header_file.relative_path_from(Rulepack::Common::RULEPACK_ROOT)}"
          end
        end

        # ─── Collect skill fragments from built packages ────────────────────────────
        # These are the rule/skill packages that target this agent with format 'skill'
        rule_skills = []

        index[:packages].each do |pkgname, pkgdata|
          # Check if this package has a built artifact for this agent
          built_checksum = pkgdata[:checksums] && pkgdata[:checksums][:built] && pkgdata[:checksums][:built][agent_id]
          next unless built_checksum

          targets = pkgdata[:targets] || []
          targets.each do |tgt|
            next unless tgt[:platform].to_s == agent_id.to_s
            next unless tgt[:format] == 'skill'
            next unless tgt[:output] # must have output

            fragment_path = Rulepack::Common.build_dir.join(agent_id.to_s, pkgname.to_s, tgt[:output])
            if fragment_path.exist?
              # Determine order: from pkgdata order if available (from index) or from pkgbuild?
              order = pkgdata[:order] || 0
              rule_skills << { pkgname: pkgname, order: order, path: fragment_path }
            else
              warn "  ⚠ Built artifact missing: #{fragment_path}"
            end
          end
        end

        # Sort by order (lower first)
        rule_skills.sort_by! { |r| r[:order] }

        rule_skills.each do |skill|
          content = skill[:path].read
          content_parts << content
          puts "  ✓ rule fragment: #{skill[:pkgname]} (#{skill[:path].basename})"
        end

        # ─── Include common skills ───────────────────────────────────────────────────
        common_skills_dir = Rulepack::Common::RULEPACK_ROOT.join('data', 'skills').join('common')
        if common_skills_dir.exist?
          common_files = Dir.glob(common_skills_dir.join('*.md')).sort
          common_files.each do |skill_file|
            content_parts << File.read(skill_file)
            puts "  ✓ common skill: #{Pathname.new(skill_file).basename}"
          end
        end

        # ─── Include agent-specific skills ──────────────────────────────────────────
        agent_skills_dir = Rulepack::Common::RULEPACK_ROOT.join('data', 'skills').join('agent-specific', agent_id.to_s)
        if agent_skills_dir.exist?
          agent_files = Dir.glob(agent_skills_dir.join('*.md')).sort
          agent_files.each do |skill_file|
            content_parts << File.read(skill_file)
            puts "  ✓ agent-specific skill: #{Pathname.new(skill_file).basename}"
          end
        end

        # ─── Combine and write vendor skill ─────────────────────────────────────────
        section_sep = "\n\n---\n\n"
        if platform_cfg[:format_profile]
          rules_cfg = platform_cfg[:format_profile][:rules]
          skills_cfg = platform_cfg[:format_profile][:skills]
          if rules_cfg && rules_cfg[:section_separator]
            section_sep = rules_cfg[:section_separator]
          elsif skills_cfg && skills_cfg[:section_separator]
            section_sep = skills_cfg[:section_separator]
          end
        end

        final_content = content_parts.join(section_sep)

        # Determine output path: Rulepack::Common::BUILD_DIR/<agent>/skills/vendor/<agent>.md
        vendor_dir = Rulepack::Common.build_dir.join(agent_id.to_s, 'skills', 'vendor')
        vendor_dir.mkpath
        vendor_file = vendor_dir.join("#{agent_id}.md")

        vendor_file.write(final_content)
        puts "  🎯 Vendor skill written: #{vendor_file.relative_path_from(Rulepack::Common::RULEPACK_ROOT)}\n"
      end

      puts "Base platform registry vendor skills aggregation complete for #{skill_agents.size} agent(s)."
      true
    end
  end
end

# CLI runner block
if __FILE__ == $PROGRAM_NAME || caller.none? || caller.any? { |c| c.include?('capture_script_run') }
  begin
    opts = Rulepack::CliParser.parse(ARGV)
    Rulepack::Aggregate.run(opts)
  rescue StandardError => e
    $stderr.puts "❌ Error: #{e.message}"
    exit 1
  end
end
