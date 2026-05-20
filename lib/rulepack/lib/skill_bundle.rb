# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative 'transaction'
require_relative 'tui_selector'

module Rulepack
  module SkillBundle
    module_function

    def install_skill_bundle(pkgname, pkgdata, target, ctx, installer_inst)
      dry_run = ctx.dry_run
      select_list = ctx.select_list
      quiet = ctx.quiet
      platform_id = ctx.platform_id
      platform_cfg = ctx.platform_cfg
      base_path = ctx.base_path
      index = ctx.index
      installed_this_run = ctx.installed_this_run
      install_cfg = target[:install] || {}
      Rulepack::Common.log "  ⤷ #{pkgname} (skill-bundle) → #{install_cfg[:target_dir]} [copy]" unless quiet

      build_src_dir = Rulepack::Common.build_dir.join(platform_id, pkgname.to_s)
      unless build_src_dir.exist? && build_src_dir.directory?
        Rulepack::Common.log_error "Skill-bundle build directory missing: #{build_src_dir}"
        return false
      end

      manifest = load_skill_bundle_manifest(build_src_dir)
      sub_skills = manifest&.dig('sub_skills') || []
      warn_large_bundle(build_src_dir, sub_skills) unless select_list

      selected = select_sub_skills(sub_skills, select_list, pkgname)
      return false unless selected

      skills_dir_name = platform_cfg[:skills_dir]
      unless skills_dir_name
        Rulepack::Common.log "  ⊘ platform '#{platform_id}' does not support skill-bundles, skipping" unless quiet
        return false
      end

      dest_dir = base_path.join(skills_dir_name).join(install_cfg[:target_dir] || '')

      if dry_run
        selected.each do |ss|
          unless quiet
            Rulepack::Common.log "    [DRY-RUN] Would copy sub-skill: #{ss['path']} → #{dest_dir.join(ss['path'])}"
          end
        end
      else
        return false unless copy_sub_skills(build_src_dir, dest_dir, selected, pkgname,
                                           ctx, quiet: quiet)

        write_selected_manifest(dest_dir, manifest, pkgname, platform_id, selected)
      end

      installer_inst.record_installation(index, pkgname, platform_id, pkgdata, '.', nil) unless dry_run
      Rulepack::Common.log "  ✓ Installed: #{pkgname}" unless quiet
      installed_this_run << pkgname
      true
    end

    def load_skill_bundle_manifest(build_src_dir)
      manifest_path = build_src_dir.join('manifest.json')
      manifest_path.exist? ? JSON.parse(manifest_path.read) : nil
    rescue JSON::ParserError => e
      Rulepack::Common.log_warn "  ⚠ Invalid manifest.json: #{e.message}"
      nil
    end

    def warn_large_bundle(build_src_dir, _sub_skills)
      manifest_path = build_src_dir.join('manifest.json')
      return unless manifest_path.exist?

      m = JSON.parse(manifest_path.read)
      sub_count = m['sub_skills']&.size.to_i
      if sub_count > 50
        Rulepack::Common.log_warn "  ⚠ #{sub_count} sub-skills. Use --select <names> to install specific ones."
      end
    rescue JSON::ParserError
      # ignore
    end

    def select_sub_skills(sub_skills, select_list, pkgname)
      if select_list == :interactive
        Rulepack::TuiSelector.prompt_sub_skill_selection(sub_skills, pkgname)
      elsif select_list && !select_list.empty? && select_list.is_a?(Array)
        selected = sub_skills.select { |ss| select_list.include?(ss['name']) }
        if selected.empty?
          selected_s = select_list.join(',')
          Rulepack::Common.log_warn "  ⚠ --select #{selected_s}: no match in #{pkgname}"
          return nil
        end
        selected
      elsif $stdin.isatty && sub_skills.size.between?(2, 150)
        Rulepack::TuiSelector.prompt_sub_skill_selection(sub_skills, pkgname)
      else
        sub_skills
      end
    end

    def copy_sub_skills(build_src_dir, dest_dir, selected, pkgname, ctx, quiet: false)
      strategy = ctx.collision_strategy || 'stop'
      if dest_dir.exist?
        case strategy
        when 'overwrite', 'append' # append for directory bundle is treated as overwrite/merge
          backup_path = Rulepack::Common.backup_file(dest_dir)
          Rulepack::Transaction.record_journal(ctx, { action: :replace_dir, path: dest_dir, backup: backup_path })
          FileUtils.rm_rf(dest_dir)
          Rulepack::Common.log "    ✓ Replaced existing directory: #{dest_dir} (with backup)" unless quiet
        when 'ignore'
          Rulepack::Common.log "    ⚠ Collision: #{dest_dir} exists, skipping" unless quiet
          return true
        else # stop
          Rulepack::Common.log_error "Collision detected: #{dest_dir} exists. Use --on-collision to proceed."
          raise "Collision at #{dest_dir}"
        end
      else
        Rulepack::Transaction.record_journal(ctx, { action: :create_dir, path: dest_dir })
      end
      FileUtils.mkpath(dest_dir)

      selected.each do |ss|
        if ss['path'] == '.'
          ss['files'].each_key do |rel_path|
            src_file = build_src_dir.join(rel_path)
            dst_file = dest_dir.join(rel_path)
            FileUtils.mkpath(dst_file.parent)
            FileUtils.cp(src_file, dst_file)
          end
          Rulepack::Common.log "    ✓ Copied sub-skill: . (#{ss['files'].size} file(s))" unless quiet
        else
          src_sub = build_src_dir.join(ss['path'])
          dst_sub = dest_dir.join(ss['path'])
          FileUtils.cp_r(src_sub, dst_sub)
          Rulepack::Common.log "    ✓ Copied sub-skill: #{ss['path']}" unless quiet
        end
      end
      true
    rescue StandardError => e
      Rulepack::Common.log_error "Failed to install skill-bundle: #{e.message}"
      false
    end

    def write_selected_manifest(dest_dir, manifest, pkgname, platform_id, selected)
      selected_manifest = {
        generated_at: manifest&.dig('generated_at') || Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        pkgname: pkgname.to_s,
        platform: platform_id.to_s,
        sub_skills: selected
      }
      dest_dir.join('manifest.json').write(JSON.pretty_generate(selected_manifest))
    end
  end
end
