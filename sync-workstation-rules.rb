#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'yaml'

class SSoTSync
  REPO_ROOT = Pathname.new(__dir__).join('..').expand_path
  SSOT_DIR = REPO_ROOT.join('ssot')

  def initialize
    data = YAML.load_file(SSOT_DIR.join('schema.yaml'))
    @sections = data['rules'] || data['sections'] || []
    @agents = data['agents'] || {}
    @skills_dir = SSOT_DIR.join('skills')
    @docs = data['docs'] || []
    @docs_dir = SSOT_DIR.join('docs')
  end

  def run(dry_run: false)
    puts "Syncing SSoT to agents..." unless dry_run
    puts ""

    @agents.each do |agent_name, config|
      case config['format']
      when 'directory'
        generate_directory_agent(agent_name, config, dry_run: dry_run)
      when 'import'
        generate_import_agent(agent_name, config, dry_run: dry_run)
      when 'skill'
        generate_skill_agent(agent_name, config, dry_run: dry_run)
      else
        puts "  #{display_name(agent_name, config)}: Unknown format — #{config['format']}"
      end
    end

    sync_shared_skills(dry_run: dry_run)
    puts "\nDone." unless dry_run
  end

  def check(vendored: false)
    puts "Check mode: Validating all targets match SSoT..."
    puts ""
    issues = []

    @agents.each do |agent_name, config|
      case config['format']
      when 'directory'
        check_directory_agent(agent_name, config, issues)
      when 'import'
        check_import_agent(agent_name, config, issues)
      when 'skill'
        if vendored
          check_skill_agent_vendored(agent_name, config, issues)
        else
          check_skill_agent(agent_name, config, issues)
        end
      else
        issues << "#{display_name(agent_name, config)}: Unknown format — #{config['format']}"
      end
    end

    if issues.empty?
      puts "All agents in sync"
    else
      puts "Issues found:"
      issues.each { |issue| puts "  - #{issue}" }
    end
  end

  private

  def display_name(agent_name, config)
    config['display_name'] || agent_name
  end

  def expand_path(path_str)
    Pathname.new(path_str).expand_path
  end

  def resolve_section_ids(config)
    ids = config['rules'] || config['sections']
    if ids.nil? || ids.empty? || ids == 'all'
      @sections.map { |s| s['id'] }
    else
      ids
    end
  end

  def section_filename(section)
    section['filename'] or raise "Section missing filename"
  end

  def sync_shared_skills(dry_run: false)
    skills_dir = REPO_ROOT.join('skills')
    skills_dir.mkpath
    @sections.each do |section|
      filename = section_filename(section)
      source = SSOT_DIR.join('rules', filename)
      target = skills_dir.join(filename)
      next unless source.exist?

      in_sync = symlink_in_sync?(target, source)

      unless in_sync
        unless dry_run
          target.unlink if target.exist? || target.symlink?
          FileUtils.ln_s(source, target)
        end
      end
    end
    puts "  Synced shared skills" unless dry_run
  end

  def symlink_in_sync?(target, source)
    if target.symlink?
      begin
        target.realpath == source
      rescue Errno::ENOENT
        false
      end
    else
      false
    end
  end

  # ─── GENERATE (sync mode) ────────────────────────────────────────────────

  def generate_directory_agent(agent_name, config, dry_run: false)
    target_dir = expand_path(config['path'])
    section_ids = resolve_section_ids(config)

    unless target_dir.exist?
      puts "  #{display_name(agent_name, config)}: Target directory missing (skipping)"
      return
    end

    count = 0
    section_ids.each do |id|
      section = @sections.find { |s| s['id'] == id } or next
      filename = section_filename(section)
      source = SSOT_DIR.join('rules', filename)
      target = target_dir.join(filename)

      unless source.exist?
        puts "  #{display_name(agent_name, config)}: Source missing — #{filename} (skipping)"
        next
      end

      unless symlink_in_sync?(target, source)
        unless dry_run
          target.unlink if target.exist? || target.symlink?
          FileUtils.ln_s(source, target)
        end
        count += 1
      end
    end
    puts "  #{display_name(agent_name, config)}: Synced (#{count} sections)" unless dry_run

    sync_directory_skills(agent_name, config, dry_run: dry_run)
    sync_directory_docs(agent_name, config, dry_run: dry_run)
  end

  def sync_directory_skills(agent_name, config, dry_run: false)
    skill_ids = config['skills'] || []
    return if skill_ids.empty?

    skills_path = config['skills_path']
    unless skills_path
      return
    end

    target_skills_dir = expand_path(skills_path)
    unless target_skills_dir.exist?
      puts "  #{display_name(agent_name, config)}: Skills directory missing — #{skills_path} (skipping skills)"
      return
    end

    skill_count = 0
    skill_ids.each do |skill_id|
      source = @skills_dir.join("#{skill_id}.md")
      unless source.exist?
        puts "  #{display_name(agent_name, config)}: Skill source missing — #{skill_id}.md (skipping)" unless dry_run
        next
      end

      skill_dir = target_skills_dir.join(skill_id)
      skill_dir.mkpath unless dry_run
      target = skill_dir.join('SKILL.md')

      unless symlink_in_sync?(target, source)
        unless dry_run
          target.unlink if target.exist? || target.symlink?
          FileUtils.ln_s(source, target)
        end
        skill_count += 1
      end
    end
    puts "  #{display_name(agent_name, config)}: Synced #{skill_count} skills" if skill_count > 0 && !dry_run
  end

  def sync_directory_docs(agent_name, config, dry_run: false)
    doc_ids = config['docs'] || []
    return if doc_ids.empty?

    target_dir = expand_path(config['path'])
    unless target_dir.exist?
      return
    end

    doc_count = 0
    doc_ids.each do |doc_id|
      doc_entry = @docs.find { |d| d['id'] == doc_id }
      next unless doc_entry

      filename = doc_entry['filename']
      source = @docs_dir.join(filename)
      unless source.exist?
        puts "  #{display_name(agent_name, config)}: Doc source missing — #{filename} (skipping)" unless dry_run
        next
      end

      target = target_dir.join(filename)

      unless symlink_in_sync?(target, source)
        unless dry_run
          target.unlink if target.exist? || target.symlink?
          FileUtils.ln_s(source, target)
        end
        doc_count += 1
      end
    end
    puts "  #{display_name(agent_name, config)}: Synced #{doc_count} docs" if doc_count > 0 && !dry_run
  end

  def generate_import_agent(agent_name, config, dry_run: false)
    target_path = expand_path(config['path'])
    section_ids = resolve_section_ids(config)

    unless target_path.exist?
      puts "  #{display_name(agent_name, config)}: Target file missing (skipping)"
      return
    end

    new_content = build_import_content(config, section_ids)

    if dry_run
      status = (target_path.read == new_content) ? 'Already in sync' : 'Would update'
      puts "  #{display_name(agent_name, config)}: #{status}"
    else
      if target_path.read == new_content
        puts "  #{display_name(agent_name, config)}: Already in sync"
      else
        target_path.write(new_content)
        puts "  #{display_name(agent_name, config)}: Updated"
      end
    end
  end

  def build_import_content(config, section_ids)
    import_lines = section_ids.map do |id|
      section = @sections.find { |s| s['id'] == id } or next
      filename = section_filename(section)
      "@#{SSOT_DIR.join('rules', filename)}"
    end.compact.join("\n")

    new_content = +""
    new_content << (config['header'] || '').strip << "\n\n" unless (config['header'] || '').strip.empty?
    new_content << import_lines << "\n"
    new_content << (config['footer'] || '').strip << "\n" unless (config['footer'] || '').strip.empty?
    new_content
  end

  def generate_skill_agent(agent_name, config, dry_run: false)
    vendor_path = SSOT_DIR.join('skills', 'vendor', "#{agent_name}.md")
    target_path = expand_path(config['path'])

    unless vendor_path.exist?
      puts "  #{display_name(agent_name, config)}: Vendored skill not found at #{vendor_path} (skipping)"
      return
    end

    unless target_path.exist?
      puts "  #{display_name(agent_name, config)}: Target file missing (skipping)"
      return
    end

    if dry_run
      status = (target_path.read == vendor_path.read) ? 'Already in sync' : 'Would update'
      puts "  #{display_name(agent_name, config)}: #{status}"
    else
      if target_path.read == vendor_path.read
        puts "  #{display_name(agent_name, config)}: Already in sync"
      else
        FileUtils.cp(vendor_path, target_path)
        puts "  #{display_name(agent_name, config)}: Vendored skill file installed"
      end
    end
  end

  # ─── CHECK mode ──────────────────────────────────────────────────────────

  def check_directory_agent(agent_name, config, issues)
    target_dir = expand_path(config['path'])
    section_ids = resolve_section_ids(config)

    unless target_dir.exist?
      issues << "#{display_name(agent_name, config)}: Target directory missing"
      return
    end

    section_ids.each do |id|
      section = @sections.find { |s| s['id'] == id } or next
      filename = section_filename(section)
      source = SSOT_DIR.join('rules', filename)
      target = target_dir.join(filename)

      unless source.exist?
        issues << "#{display_name(agent_name, config)}: Section source missing — #{filename}"
        next
      end

      unless symlink_in_sync?(target, source)
        issues << "#{display_name(agent_name, config)}: Symlink out of sync — #{filename}"
      end
    end

    check_directory_skills(agent_name, config, issues)
    check_directory_docs(agent_name, config, issues)
  end

  def check_directory_skills(agent_name, config, issues)
    skill_ids = config['skills'] || []
    return if skill_ids.empty?

    skills_path = config['skills_path']
    return unless skills_path

    target_skills_dir = expand_path(skills_path)
    unless target_skills_dir.exist?
      issues << "#{display_name(agent_name, config)}: Skills directory missing — #{skills_path}"
      return
    end

    skill_ids.each do |skill_id|
      source = @skills_dir.join("#{skill_id}.md")
      unless source.exist?
        issues << "#{display_name(agent_name, config)}: Skill source missing — #{skill_id}.md"
        next
      end

      target = target_skills_dir.join(skill_id, 'SKILL.md')
      unless symlink_in_sync?(target, source)
        issues << "#{display_name(agent_name, config)}: Skill symlink out of sync — #{skill_id}"
      end
    end
  end

  def check_directory_docs(agent_name, config, issues)
    doc_ids = config['docs'] || []
    return if doc_ids.empty?

    target_dir = expand_path(config['path'])
    unless target_dir.exist?
      return
    end

    doc_ids.each do |doc_id|
      doc_entry = @docs.find { |d| d['id'] == doc_id }
      next unless doc_entry

      filename = doc_entry['filename']
      source = @docs_dir.join(filename)
      unless source.exist?
        issues << "#{display_name(agent_name, config)}: Doc source missing — #{filename}"
        next
      end

      target = target_dir.join(filename)
      unless symlink_in_sync?(target, source)
        issues << "#{display_name(agent_name, config)}: Doc symlink out of sync — #{filename}"
      end
    end
  end

  def check_import_agent(agent_name, config, issues)
    target_path = expand_path(config['path'])

    unless target_path.exist?
      issues << "#{display_name(agent_name, config)}: Target file missing"
      return
    end

    content = target_path.read
    section_ids = resolve_section_ids(config)

    section_ids.each do |id|
      section = @sections.find { |s| s['id'] == id } or next
      filename = section_filename(section)
      import_tag = "@#{SSOT_DIR.join('rules', filename)}"
      unless content.include?(import_tag)
        issues << "#{display_name(agent_name, config)}: Missing import — #{import_tag}"
      end
    end
  end

  def check_skill_agent(agent_name, config, issues)
    section_ids = resolve_section_ids(config)
    target_path = expand_path(config['path'])

    unless target_path.exist?
      issues << "#{display_name(agent_name, config)}: Target file missing"
      return
    end

    content = target_path.read
    section_ids.each do |id|
      section = @sections.find { |s| s['id'] == id } or next
      filename = section_filename(section)
      source = SSOT_DIR.join('rules', filename)
      unless source.exist?
        issues << "#{display_name(agent_name, config)}: Section source missing — #{filename}"
        next
      end
      unless content.include?(source.read)
        issues << "#{display_name(agent_name, config)}: Content missing — #{filename}"
      end
    end
  end

  def check_skill_agent_vendored(agent_name, config, issues)
    vendor_path = SSOT_DIR.join('skills', 'vendor', "#{agent_name}.md")
    target_path = expand_path(config['path'])

    unless vendor_path.exist?
      issues << "#{display_name(agent_name, config)}: Vendored skill not found at #{vendor_path}"
      return
    end

    unless target_path.exist?
      issues << "#{display_name(agent_name, config)}: Target file missing"
      return
    end

    unless vendor_path.read == target_path.read
      issues << "#{display_name(agent_name, config)}: Vendored skill out of sync — run 'make vendor-skills && make sync'"
    end
  end
end

# ─── Main ───────────────────────────────────────────────────────────────────

sync = SSoTSync.new
dry_run = ARGV.include?('--dry-run')
check_mode = ARGV.include?('--check')
vendored = ARGV.include?('--vendored')

if check_mode
  sync.check(vendored: vendored)
else
  sync.run(dry_run: dry_run)
end
