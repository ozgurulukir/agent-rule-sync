#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'fileutils'
require 'digest'
require 'json'
require 'set'
require_relative 'lib/common'

SSOT_ROOT = Pathname.new(__dir__).expand_path
BUILD_DIR = SSOT_ROOT.join('build')
BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')
INDEX_YAML_PATH = SSOT_ROOT.join('index.yaml')
INDEX_JSON_PATH = SSOT_ROOT.join('index.json')
LOG_PATH = BUILD_DIR.join('install.log')

# ─── Logging ────────────────────────────────────────────────────────────────────

$LOG_LEVEL = :info  # default, can be changed by --verbose

def log(msg, level: :info)
  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
  line = "[#{timestamp}] #{msg}"
  level_order = { error: 0, warn: 1, info: 2, debug: 3 }
  if level_order[level] <= level_order[$LOG_LEVEL]
    puts line
  end
  FileUtils.mkpath(BUILD_DIR)
  File.open(LOG_PATH, 'a') { |f| f.puts(line) }
end

def log_error(msg)
  warn "❌ #{msg}"
  log("ERROR: #{msg}", level: :error)
end

def log_warn(msg)
  warn "⚠️  #{msg}"
  log("WARN: #{msg}", level: :warn)
end

 def log_debug(msg)
   log("DEBUG: #{msg}", level: :debug)
 end

# ─── Helpers ────────────────────────────────────────────────────────────────────

def platform_cfg_for(platform_id)
  registry = Ssot::Lib::Common.load_platform_registry
  Ssot::Lib::Common.platform_config(platform_id, registry)
rescue => e
  log_error e.message
  exit 1
end

# Check if file content already present (for append-type installs)
def content_already_present?(path, new_content)
  return false unless path.exist?

  existing = path.read
  existing.include?(new_content)
end

# Uninstall a single package from a platform (used for upgrades).
# Modifies index in-place, does not write.
def uninstall_package_from_index!(index, pkgname, platform_id, dry_run: false, project_root: nil)
  uninstalled = Ssot::Lib::Common.uninstall_packages(index, platform_id, dry_run: dry_run, project_root: project_root, specific_packages: [pkgname])
  uninstalled.include?(pkgname)
end

# ─── Parse arguments ────────────────────────────────────────────────────────────

dry_run = false
check_mode = false
force_mode = false
verbose_mode = false
platform_arg = nil
project_arg = nil

i = 0
while i < ARGV.length
  arg = ARGV[i]
  case arg
  when '--dry-run'
    dry_run = true
    i += 1
  when '--check'
    check_mode = true
    i += 1
  when '--force'
    force_mode = true
    i += 1
  when '--project'
    if i + 1 >= ARGV.length
      raise "Missing path for --project"
    end
    project_arg = ARGV[i + 1]
    i += 2
  when '-v', '--verbose'
    verbose_mode = true
    i += 1
  else
    platform_arg = arg
    i += 1
  end
end

# Set log level based on verbose mode
$LOG_LEVEL = verbose_mode ? :debug : :info

unless platform_arg || check_mode
  puts "Usage: ruby ssot/install.rb <platform> [--dry-run] [--check] [--project PATH]"
  puts "       ruby ssot/install.rb --check <platform> [--project PATH]"
  puts ""
  puts "For project-level platforms (cursor, windsurf, github-copilot, claude-code, codex),"
  puts "use --project to specify the project root (default: current directory)."
  puts ""
  puts "Examples:"
  puts "  ruby ssot/install.rb opencode                  # user-level"
  puts "  ruby ssot/install.rb cursor --project .        # current project"
  puts "  ruby ssot/install.rb github-copilot --project ~/projects/myapp"
  exit 1
end

# Determine effective project root for project-level platforms
def project_root_for(platform_id, platform_cfg, project_arg)
  scope = platform_cfg[:scope] || 'user'
  if scope == 'project'
    if project_arg
      Pathname.new(project_arg).expand_path
    else
      # Default to current directory if not specified but platform is project-level
      Pathname.pwd
    end
  else
    nil
  end
end

if check_mode
  # --check mode: verify installed state matches index
  platform_id = platform_arg
  log "🔍 Checking installed state for platform: #{platform_id}"
  puts "🔍 Checking installed state for platform: #{platform_id}"

  unless SSOT_ROOT.join('index.yaml').exist?
    log_error "index.yaml not found. Run build first."
    raise  # re-raise so outer transaction rescue can rollback
  end

  index = Ssot::Lib::Common.load_yaml(INDEX_YAML_PATH)
  platform_cfg = platform_cfg_for(platform_id)
  # Check platform prerequisites (warn only, do not block)
  missing = Ssot::Lib::Common.check_prerequisites(platform_cfg)
  unless missing.empty?
    log_warn "Platform #{platform_id} may require: #{missing.join(", ")}"
    puts "  ⚠️  Platform #{platform_id} may require: #{missing.join(", ")}"
  end
  # Compute effective base path (handles project-level)
  project_root = project_root_for(platform_id, platform_cfg, project_arg)
  base_path = if project_root
                project_root
              else
                Pathname.new(Ssot::Lib::Common.expand_user_path(platform_cfg[:base_path]))
              end

  # Special handling for skill-based platforms: verify aggregated vendor skill
  if platform_cfg[:type] == 'skill'
    log "  🎯 Skill platform: verifying aggregated vendor skill"
    vendor_path = base_path.join(platform_cfg[:skill_file])
    unless vendor_path.exist?
      log_error "Vendor skill missing: #{vendor_path}"
      puts "  ❌ Vendor skill missing: #{vendor_path}"
      raise  # re-raise so outer transaction rescue can rollback
    end
    # Verify that the vendor file is up-to-date by comparing with build artifacts
    # Re-run aggregation to a temp location and compare? Simpler: check that vendor mtime >= build index mtime?
    log "  ✓ Vendor skill present: #{vendor_path}"
    puts "  ✅ Vendor skill present and readable"
    exit 0
  end

  errors = []
  index[:packages].each do |pkgname, pkgdata|
    # Find installed record for this platform
    inst = pkgdata[:installed].find { |i| i[:platform] == platform_id }
    next unless inst

    expected_output = inst[:output]
    expected_checksum = inst[:checksum]

     # Find target definition to get format (for directory platforms)
     target = pkgdata[:targets]&.find { |t| t[:platform] == platform_id }
     format_type = target ? target[:format] : 'directory' # default
     install_cfg = target[:install] || {}

     # Determine installed file path (using base_path which is effective)
     if platform_cfg[:type] == 'directory'
       # Use same path resolution as install mode
       if install_cfg[:target_dir]
         target_subdir = Ssot::Lib::Common.expand_user_path(install_cfg[:target_dir])
         base_subdir = if format_type == 'skill' || format_type == 'skill-bundle'
                         platform_cfg[:skills_dir]
                       else
                         platform_cfg[:rules_dir]
                       end
         if Pathname.new(target_subdir).absolute?
           installed_path = Pathname.new(target_subdir).join(expected_output)
         else
           installed_path = base_path.join(base_subdir, target_subdir, expected_output)
         end
       else
         # Default: use resolve_install_path (handles rules_dir/skills_dir based on format)
         installed_path = Ssot::Lib::Common.resolve_install_path(platform_cfg, target, project_root)
       end
     elsif platform_cfg[:type] == 'import'
       installed_path = base_path.join(platform_cfg[:config_file])
     elsif platform_cfg[:type] == 'skill'
       installed_path = base_path.join(platform_cfg[:skill_file])
     else
       raise "Unknown platform type: #{platform_cfg[:type]}"
     end

     # Handle skill-bundle: output '.' means target_dir, verify directory exists
     if format_type == 'skill-bundle'
       unless installed_path.directory?
         errors << "Skill-bundle directory missing: #{installed_path}"
       else
         log "  ✓ Skill-bundle directory: #{installed_path}"
         # L4.4: Verify skill-bundle manifest in check mode
         manifest_path = Pathname.new(installed_path).join("manifest.json")
         if manifest_path.exist?
           begin
             manifest = JSON.parse(manifest_path.read)
             mismatches = []
             manifest["files"].each do |rel_path, expected_sha|
               file_path = Pathname.new(installed_path).join(rel_path)
               unless file_path.exist?
                 mismatches << "missing: #{rel_path}"
               else
                 actual_sha = Digest::SHA256.hexdigest(file_path.read)
                 unless actual_sha == expected_sha
                   mismatches << "checksum mismatch: #{rel_path} (expected #{expected_sha[0..7]}, got #{actual_sha[0..7]})"
                 end
               end
             end
             if mismatches.empty?
               log "  ✓ Skill-bundle manifest: #{manifest["files"].size} file(s) verified"
             else
               log_warn "Skill-bundle manifest: #{mismatches.size} issue(s)"
               mismatches.each { |m| log_warn "    • #{m}" }
               errors.concat(mismatches.map { |m| "#{pkgname}: #{m}" })
             end
           rescue => e
             log_warn "Failed to read skill-bundle manifest: #{e.message}"
           end
         else
           log_warn "No manifest.json found for #{pkgname}"
         end
       end
       next  # skip checksum verification for bundles
     end

     # For file-based formats, verify file exists and checksum matches
     unless installed_path.exist?
       errors << "Missing: #{pkgname} (#{expected_output}) at #{installed_path}"
       next
     end

     actual_checksum = Digest::SHA256.hexdigest(installed_path.read)
     if actual_checksum != expected_checksum
       errors << "Checksum mismatch: #{pkgname} (expected #{expected_checksum[0..7]}, got #{actual_checksum[0..7]})"
     end
end

  if errors.empty?
    log "✅ All installed packages are valid"
    puts "✅ All installed packages are valid"
    exit 0
  else
    errors.each { |e| log_error e; puts "  ❌ #{e}" }
    raise  # re-raise so outer transaction rescue can rollback
  end
end

# ─── Normal install mode ────────────────────────────────────────────────────────

platform_id = platform_arg
log "🚀 Installing platform: #{platform_id} #{dry_run ? '(dry-run)' : ''}"
puts "🚀 Installing platform: #{platform_id} #{dry_run ? '(dry-run)' : ''}"

# Load build index
unless BUILD_INDEX_PATH.exist?
  log_error "Build index not found at #{BUILD_INDEX_PATH}. Run `ruby ssot/build.rb` first."
  exit 1
end

 build_index = Ssot::Lib::Common.load_yaml(BUILD_INDEX_PATH)
  index = if SSOT_ROOT.join('index.yaml').exist?
            Ssot::Lib::Common.load_yaml(SSOT_ROOT.join('index.yaml'))
          else
            { version: 3.0, packages: {} }
          end
  index[:packages] ||= {}

  (index[:packages] || {}).each_value { |pkg_idx| Ssot::Lib::Common.migrate_installed_records(pkg_idx) }

# ─── Transaction: backup index before any changes ──────────────────────────────
# L4.3: On failure, restore from backup so index is never left in a partial state.
backup_path = nil
unless dry_run
  backup_path = Ssot::Lib::Common.backup_index
  log "  🗂 Index backed up to #{backup_path.basename}" if backup_path
end

begin

platform_cfg = platform_cfg_for(platform_id)
# Check platform prerequisites (warn only, do not block)
  missing = Ssot::Lib::Common.check_prerequisites(platform_cfg)
  unless missing.empty?
    log_warn "Platform #{platform_id} may require: #{missing.join(", ")}"
    puts "  ⚠️  Platform #{platform_id} may require: #{missing.join(", ")}"
  end

# Resolve effective base path (handles user-level vs project-level)
project_root = project_root_for(platform_id, platform_cfg, project_arg)
if project_root
  base_path = project_root
  log "📁 Project root: #{project_root}"
else
  base_path = Pathname.new(Ssot::Lib::Common.expand_user_path(platform_cfg[:base_path]))
  log "🏠 Home base: #{base_path}"
end

log "  Platform base: #{base_path}"
log "  Platform type: #{platform_cfg[:type]}"

# Track which packages we actually installed this run (use Set to avoid duplicates)
require 'set'
installed_this_run = Set.new

build_index[:packages].each do |pkgname, pkgdata|
  # Find ALL targets for this platform (not just first)
  targets = pkgdata[:targets]&.select { |t| t[:platform] == platform_id }
  if targets.nil? || targets.empty?
    log "  ⊘ #{pkgname}: no target for #{platform_id}, skipping"
    next
  end

  # ─── Upgrade / Downgrade Check ────────────────────────────────────────────────
  # Check if this package is already installed on this platform
  current_pkg_index = index[:packages][pkgname] || { installed: [] }
  existing_records = (current_pkg_index[:installed] || []).select { |r| r[:platform] == platform_id }

  if existing_records.any?
    # Assume single installed record per platform (most recent)
    existing = existing_records.first
    cmp = Ssot::Lib::Common.compare_versions(
      pkgdata[:pkgver], existing[:version],
      pkgrel1: pkgdata[:pkgrel], pkgrel2: existing[:pkgrel],
      epoch1: pkgdata[:epoch], epoch2: existing[:epoch]
    )

    if cmp == 0
      log "  ↺ #{pkgname} already installed (#{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])})"
      next  # skip, nothing to do
       elsif cmp > 0
         log "  🔄 Upgrading #{pkgname} #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])} → #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}"
         unless dry_run
           unless uninstall_package_from_index!(index, pkgname, platform_id, dry_run: false, project_root: project_root)
             log_error "Failed to uninstall old version of #{pkgname}"
             next
           end
           # No index reload — uninstall modified index in-place
         else
           # Dry-run: simulate uninstall
           log "    [DRY-RUN] Would uninstall old version"
         end
       else # cmp < 0
         if force_mode
           log_warn "Downgrade forced for #{pkgname}: #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])} → #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}"
           unless dry_run
             unless uninstall_package_from_index!(index, pkgname, platform_id, dry_run: false, project_root: project_root)
               log_error "Failed to uninstall old version of #{pkgname}"
               next
             end
             # No index reload — uninstall modified index in-place
           else
             log "    [DRY-RUN] Would downgrade (force)"
           end
         else
           log_error "Downgrade detected for #{pkgname}: installed #{Ssot::Lib::Common.format_version(existing[:epoch], existing[:version], existing[:pkgrel])}, candidate #{Ssot::Lib::Common.format_version(pkgdata[:epoch], pkgdata[:pkgver], pkgdata[:pkgrel])}"
           log_error "Use --force to allow downgrade"
           next
         end
       end
   end

   # Ensure package entry exists in index and preserve installed records for other platforms
   pkg_index = index[:packages][pkgname] ||= {}
   pkg_index[:installed] ||= []
   # Update metadata from build data (excluding installed records)
   pkg_index.merge!(pkgdata.reject { |k, _| k == :installed })

   targets.each do |target|
     format = target[:format]
     output = target[:output]
     transformer = target[:transformer] || 'copy'
     install_cfg = target[:install] || {}
     install_type = install_cfg[:type] || platform_cfg[:"#{format}_install"]&.[](:type) || 'copy'

     # ─── skill-bundle: recursive directory copy ───────────────────────────────────
     if format == 'skill-bundle'
       log "  ⤷ #{pkgname} (skill-bundle) → #{install_cfg[:target_dir]} [copy]"

       # Build source directory: build/<platform>/<pkgname>/
       build_src_dir = BUILD_DIR.join(platform_id, pkgname.to_s)
       unless build_src_dir.exist? && build_src_dir.directory?
         log_error "Skill-bundle build directory missing: #{build_src_dir}"
         next
       end

       # Destination: skills_dir/target_dir/
       dest_dir = base_path.join(platform_cfg[:skills_dir]).join(install_cfg[:target_dir])

       if dry_run
         log "    [DRY-RUN] Would copy directory: #{build_src_dir} → #{dest_dir}"
       else
         begin
           # Remove existing if present (overwrite)
           if dest_dir.exist?
             FileUtils.rm_rf(dest_dir)
             log "    ✓ Removed existing: #{dest_dir}"
           end
           FileUtils.mkpath(dest_dir.parent)
           FileUtils.cp_r(build_src_dir, dest_dir)
           log "    ✓ Installed skill-bundle"
           # L4.4: Verify skill-bundle manifest checksums
           manifest_path = dest_dir.join("manifest.json")
           if manifest_path.exist?
             begin
               manifest = JSON.parse(manifest_path.read)
               mismatches = []
               manifest["files"].each do |rel_path, expected_sha|
                 file_path = dest_dir.join(rel_path)
                 unless file_path.exist?
                   mismatches << "missing: #{rel_path}"
                 else
                   actual_sha = Digest::SHA256.hexdigest(file_path.read)
                   unless actual_sha == expected_sha
                     mismatches << "checksum mismatch: #{rel_path} (expected #{expected_sha[0..7]}, got #{actual_sha[0..7]})"
                   end
                 end
               end
               if mismatches.empty?
                 log "    ✓ Skill-bundle manifest verified: #{manifest["files"].size} file(s)"
               else
                 log_warn "Skill-bundle manifest verification: #{mismatches.size} mismatch(es)"
                 mismatches.each { |m| log_warn "      • #{m}" }
               end
             rescue => e
               log_warn "Failed to verify skill-bundle manifest: #{e.message}"
             end
           else
             log_warn "No manifest.json found for #{pkgname} — skipping checksum verification"
           end
         rescue => e
           log_error "Failed to install skill-bundle: #{e.message}"
           next
         end
       end

        # Record installation (output = '.' as directory marker)
        unless dry_run
          installed_record = {
            platform: platform_id,
            version: pkgdata[:pkgver],
            pkgrel: pkgdata[:pkgrel],
            epoch: pkgdata[:epoch],
            output: '.',   # directory marker
            checksum: nil,  # no single checksum for bundle
            installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          }
          pkg_index[:installed] << installed_record
        end

       installed_this_run << pkgname
       log "  ✓ Installed: #{pkgname}"
       next
     end

     # ─── Single-file formats (directory, import, skill) ──────────────────────────
     # Determine built artifact path
     built_path = BUILD_DIR.join(platform_id, output)
     unless built_path.exist?
       log_error "Built artifact missing: #{built_path}"
       next
     end

     # Read built content
     content = built_path.read
     content_sha256 = Digest::SHA256.hexdigest(content)

     # For skill platforms, skip individual file installation; aggregation handles it.
     unless platform_cfg[:type] == 'skill'
        # Determine install destination
        begin
          if install_cfg[:target_dir]
            target_subdir = Ssot::Lib::Common.expand_user_path(install_cfg[:target_dir])
            if platform_cfg[:type] == 'directory'
              # Choose base subdirectory: skills_dir for skill/skill-bundle, else rules_dir
              base_subdir = if target[:format] == 'skill' || target[:format] == 'skill-bundle'
                              platform_cfg[:skills_dir]
                            else
                              platform_cfg[:rules_dir]
                            end
              # If target_subdir is absolute, use it directly; else join with base_subdir
              if Pathname.new(target_subdir).absolute?
                install_path = Pathname.new(target_subdir).join(output)
              else
                install_path = base_path.join(base_subdir, target_subdir, output)
              end
            else
              # For import platforms or others, treat target_subdir relative to base_path
              if Pathname.new(target_subdir).absolute?
                install_path = Pathname.new(target_subdir).join(output)
              else
                install_path = base_path.join(target_subdir, output)
              end
            end
          else
            install_path = Ssot::Lib::Common.resolve_install_path(platform_cfg, target, project_root)
          end
        rescue => e
          log_error "Failed to resolve install path for #{pkgname}: #{e.message}"
          next
        end

       # Ensure parent directory exists
       unless dry_run
         install_path.parent.mkpath
       end

       log "  ⤷ #{pkgname} (#{output}) → #{install_path} [#{install_type}]"

       # Perform install based on type
       case install_type
       when 'symlink'
         if dry_run
           log "    [DRY-RUN] Would symlink: #{built_path} → #{install_path}"
         else
           begin
             if install_path.symlink?
               if install_path.readlink == built_path.relative_path_from(install_path.parent)
                 log "    ↺ Already symlinked"
               else
                 FileUtils.rm(install_path)
                 FileUtils.ln_s(built_path.relative_path_from(install_path.parent), install_path)
                 log "    ✓ Replaced symlink"
               end
             elsif install_path.exist?
               log_warn "    ⚠ Target exists and is not a symlink, skipping: #{install_path}"
             else
               FileUtils.ln_s(built_path.relative_path_from(install_path.parent), install_path)
               log "    ✓ Symlinked"
             end
           rescue => e
             log_error "Symlink failed: #{e.message}"
             next
           end
         end

       when 'copy'
         if dry_run
           log "    [DRY-RUN] Would copy: #{built_path} → #{install_path}"
         else
           begin
             if install_path.exist?
               existing_sha = Digest::SHA256.hexdigest(install_path.read)
               if existing_sha == content_sha256
                 log "    ↺ Already up-to-date"
               else
                 FileUtils.cp(built_path, install_path)
                 log "    ✓ Updated"
               end
             else
               FileUtils.cp(built_path, install_path)
               log "    ✓ Copied"
             end
           rescue => e
             log_error "Copy failed: #{e.message}"
             next
           end
         end

       when 'inject', 'append'
         if dry_run
           log "    [DRY-RUN] Would #{install_type}: #{output} → #{install_path}"
         else
           begin
             if install_type == 'append'
               if content_already_present?(install_path, content)
                 log "    ↺ Already present (skipping duplicate append)"
               else
                 Ssot::Lib::Common.atomic_append(install_path, content)
                 log "    ✓ Appended"
               end
             elsif install_type == 'inject'
               directive = platform_cfg[:rule_install]&.[](:directive) || '@import'
               import_line = "#{directive} \"#{output}\"\n"
               unless install_path.exist?
                 Ssot::Lib::Common.atomic_write(install_path, import_line)
                 log "    ✓ Injected (created config)"
               else
                 existing = install_path.read
                 if existing.start_with?(import_line)
                   log "    ↺ Already injected"
                 else
                   Ssot::Lib::Common.atomic_write(install_path, import_line + existing)
                   log "    ✓ Injected"
                 end
               end
             end
           rescue => e
             log_error "Install failed (#{install_type}): #{e.message}"
             next
           end
         end

       else
         log_error "Unknown install type: #{install_type} for #{pkgname}"
         next
       end
     end  # unless skill platform

      # Record installation in index (only if not dry-run)
      unless dry_run
        installed_record = {
          platform: platform_id,
          version: pkgdata[:pkgver],
          pkgrel: pkgdata[:pkgrel],
          epoch: pkgdata[:epoch],
          output: output,
          checksum: content_sha256,
          installed_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        }
        pkg_index[:installed] << installed_record
      end

      installed_this_run << pkgname
      log "  ✓ Installed: #{pkgname}"
    end
end

# ─── Handle vendor skill aggregation (skill-type platforms) ─────────────────────

if platform_cfg[:type] == 'skill' && !dry_run
  log "  🧱 Aggregating vendor skills for #{platform_id}..."
  puts "\n  🧱 Aggregating vendor skills for #{platform_id}..."
  aggregate_script = SSOT_ROOT.join('aggregate-skills.rb')
  system("ruby", aggregate_script.to_s, platform_id.to_s)
  if $?.success?
    log "    ✓ Vendor skill aggregated"
    puts "    ✓ Vendor skill aggregated"
    # Copy aggregated vendor skill to agent's skill location
    vendor_file = BUILD_DIR.join(platform_id, 'skills', 'vendor', "#{platform_id}.md")
    if vendor_file.exist?
      install_path = base_path.join(platform_cfg[:skill_file])
      install_path.parent.mkpath
      FileUtils.cp(vendor_file, install_path)
      log "  ✓ Installed vendor skill to #{install_path}"
      puts "  ✓ Installed vendor skill to #{install_path}"
    else
      log_error "Vendor skill not generated: #{vendor_file}"
    end
  else
    log_error "Vendor skill aggregation failed"
  end
end

# ─── Write index ────────────────────────────────────────────────────────────────

unless dry_run
  begin
    index[:generated] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    Ssot::Lib::Common.write_yaml_atomic(INDEX_YAML_PATH, index)
    log "📝 Index written: #{INDEX_YAML_PATH}"
    puts "\n📝 Index written: #{INDEX_YAML_PATH}"
  rescue => e
    log_error "Failed to write index: #{e.message}"
    raise  # re-raise so outer transaction rescue can rollback
  end
else
  log "[DRY-RUN] Index write skipped"
  puts "\n[DRY-RUN] Index write skipped"
end

rescue => e
  # ─── Transaction rollback ─────────────────────────────────────────────────────
  if backup_path && Ssot::Lib::Common.restore_index(backup_path)
    log_error "Transaction failed (#{e.message}). Index restored from backup."
    puts "  ❌ Transaction failed. Index restored from backup: #{backup_path.basename}"
  else
    log_error "Transaction failed (#{e.message}). No backup available."
    puts "  ❌ Transaction failed: #{e.message}"
  end
  exit 1
ensure
  # ─── Cleanup backup ──────────────────────────────────────────────────────────
  Ssot::Lib::Common.cleanup_backups rescue nil
end
# ─── Summary ────────────────────────────────────────────────────────────────────

puts "\n✅ Install #{dry_run ? 'preview' : 'complete'}. #{installed_this_run.size} package(s) affected:"
installed_this_run.each { |p| puts "   • #{p}" }
puts ""
