# frozen_string_literal: true

# Unit tests for skill-bundle manifest generation and sub-skill discovery.
# Follows the tmpdir-fixture pattern of TestSkillBundleManifestGeneration in
# test_integration.rb.

require_relative 'helper'

class TestSkillBundleDiscovery < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('ssot-manifest-test-')
  end

  # Helper: create a bundle dir with given sub-skill structure and return
  # the Pathname. Creates directories and files matching what
  # skill_bundle_sub_skills expects.
  # - String values: single file content written at dir_path
  #   - If dir_path has no "/" (e.g., "auth", "SKILL.md"): the behavior depends on context.
  #     For test fixtures, "auth" means a directory, "SKILL.md" means a root file.
  #   - If dir_path has "/" (e.g., "auth/SKILL.md"): write to that nested path.
  # - Hash values: {rel_path => content} for files within a directory
  def build_bundle_dir(base, structure)
    dir = Pathname.new(base.to_s).join('bundle')
    dir.mkpath

    structure.each do |dir_path, files|
      # dir_path can be:
      # - "auth"         → creates bundle/auth/ directory, files go inside
      # - "auth/SKILL.md" → creates bundle/auth/SKILL.md file
      # - "SKILL.md"     → creates bundle/SKILL.md at root
      # - "engineering/ask-matt/SKILL.md" → creates bundle/engineering/ask-matt/SKILL.md
      parts = dir_path.split('/')

      # Determine if dir_path represents a file or directory:
      # - If the last component looks like a filename (no extension ambiguity)
      #   and there are multiple components, it's a file path.
      # - If dir_path has only 1 component, we need to determine context:
      #   - Look at the files hash: if values are strings, dir_path is a directory
      #   - If dir_path is just a filename (e.g., "SKILL.md"), it's a root file
      has_slash = dir_path.include?('/')
      
      if has_slash
        # Multi-component: last part is filename, rest is directory
        dir_name = parts[0..-2].join('/')  # e.g., "auth" or "engineering/ask-matt"
        file_name = parts[-1]  # e.g., "SKILL.md"
        full_dir = if dir_name.empty?
          dir
        else
          dir.join(dir_name)
        end
        full_dir.mkpath unless full_dir.exist?

        if files.is_a?(String)
          # Single file content: write to the nested path
          file_path = full_dir.join(file_name)
          file_path.write(files)
        else
          # Hash of {rel_path => content} within the directory
          files.each do |rel_path, content|
            target_path = full_dir.join(rel_path)
            target_path.parent.mkpath if rel_path.include?('/')
            target_path.write(content)
          end
        end
      else
        # Single component: determine if it's a directory or root file
        # by checking the files type. If files is a Hash, it's a directory.
        # If files is a String or nil, it could be a root file.
        if files.is_a?(Hash)
          # dir_path is a directory (e.g., "auth", "sql")
          # Create the directory and write files inside it
          full_dir = dir.join(dir_path)
          full_dir.mkpath unless full_dir.exist?

          files.each do |rel_path, content|
            target_path = full_dir.join(rel_path)
            target_path.parent.mkpath if rel_path.include?('/')
            target_path.write(content)
          end
        elsif files.is_a?(String)
          # dir_path is a root-level file (e.g., "SKILL.md", "README.md")
          file_path = dir.join(dir_path)
          file_path.write(files)
        else
          # dir_path with nil value - treat as directory name only
          # (create empty directory)
          full_dir = dir.join(dir_path)
          full_dir.mkpath unless full_dir.exist?
        end
      end
    end

    dir
  end

  def test_nested_discovery
    # A skill 2 levels deep (<pkg>/engineering/ask-matt/SKILL.md + nested files)
    # becomes its own sub-skill with name = ask-matt and path = engineering/ask-matt.
    # files includes the nested files; NO category-level (engineering) sub-skill appears.
    pkg_dir = build_bundle_dir(@tmpdir, {
      'engineering/ask-matt/SKILL.md' => '# Ask Matt Skill',
      'engineering/ask-matt/rules.md' => '# Rules'
    })

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'test-pkg', 'opencode')

    # Should have 1 sub-skill: ask-matt
    assert_equal 1, manifest[:sub_skills].size, "should have 1 sub-skill, got #{manifest[:sub_skills].size}"
    ask_matt = manifest[:sub_skills].find { |s| s[:name] == 'ask-matt' }
    assert ask_matt, 'should have ask-matt sub-skill'
    assert_equal 'engineering/ask-matt/SKILL.md', ask_matt[:files].keys.first
  end

  def test_exclusion
    # Complete exclusion: skill_exclude: [in-progress] excludes ALL
    # sub-skills under in-progress/ (both pr and retro).
    pkg_dir = build_bundle_dir(@tmpdir, {
      'in-progress/pr' => {
        'SKILL.md' => '# PR Skill'
      },
      'in-progress/retro' => {
        'SKILL.md' => '# Retro Skill'
      }
    })

    # Full exclusion test
    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'test-pkg', 'opencode', skill_exclude: ['in-progress'])

    # in-progress should be completely excluded - no sub-skills should remain
    in_progress_skills = manifest[:sub_skills].select { |s| s[:path].start_with?('in-progress') }
    assert in_progress_skills.empty?, "in-progress skills should be excluded, got: #{in_progress_skills.map { |s| s[:path] }}"

    # Partial exclusion test with separate top-level dirs
    # Create a fixture with in-progress/pr and in-progress/retro as separate
    # top-level skills (not under a common in-progress parent)
    pkg_dir2 = build_bundle_dir(@tmpdir, {
      'in-progress/pr/SKILL.md' => '# PR Skill',
      'in-progress/retro/SKILL.md' => '# Retro Skill'
    })

    manifest2 = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir2, 'test-pkg', 'opencode', skill_exclude: ['in-progress/pr'])

    # in-progress/pr should be excluded, retro should remain
    retro = manifest2[:sub_skills].find { |s| s[:path] == 'in-progress/retro' }
    assert retro, 'in-progress/retro should still appear with partial exclusion (skill_exclude: [in-progress/pr])'
    assert_includes retro[:files].keys, 'in-progress/retro/SKILL.md', 'retro SKILL.md should be present in files'

    # Also verify pr is excluded
    pr_skills = manifest2[:sub_skills].select { |s| s[:path].start_with?('in-progress/pr') }
    assert pr_skills.empty?, "in-progress/pr skills should be excluded with partial exclusion"
  end

  def test_flat_package_regression
    # A flat fixture (SKILL.md at each top-level dir + a loose root file)
    # yields sub-skills IDENTICAL to the current grouping (exact path/name/files).
    pkg_dir = build_bundle_dir(@tmpdir, {
      'auth' => {
        'SKILL.md' => '# Auth Skill',
        'rules.md' => 'auth rules'
      },
      'sql' => {
        'SKILL.md' => '# SQL Skill'
      },
      'README.md' => '# Readme',
      'SKILL.md' => '# Root Skill'  # root-level SKILL.md belongs to . group
    })

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'test-pkg', 'opencode')

    # Should have exactly 3 sub-skills: auth, sql, and . (root/README)
    assert_equal 3, manifest[:sub_skills].size, "should have 3 sub-skills, got #{manifest[:sub_skills].size}"

    # auth sub-skill
    auth_sub = manifest[:sub_skills].find { |s| s[:path] == 'auth' }
    assert auth_sub, 'should have auth sub-skill'
    assert_equal 2, auth_sub[:files].size, 'auth should have 2 files'

    # sql sub-skill
    sql_sub = manifest[:sub_skills].find { |s| s[:path] == 'sql' }
    assert sql_sub, 'should have sql sub-skill'
    assert_equal 1, sql_sub[:files].size, 'sql should have 1 file'

    # root sub-skill (loose files including root SKILL.md)
    root_sub = manifest[:sub_skills].find { |s| s[:path] == '.' }
    assert root_sub, 'should have root sub-skill for loose files'
    assert root_sub[:files].key?('README.md'), 'root should have README.md'
    assert root_sub[:files].key?('SKILL.md'), 'root should have SKILL.md'
  end

  def test_root_skill_md_belongs_to_dot_group
    # Root SKILL.md + sub-skill dir → root file stays in the . group, not a sub-skill.
    pkg_dir = build_bundle_dir(@tmpdir, {
      'SKILL.md' => '# Root Skill',
      'auth' => {
        'SKILL.md' => '# Auth Skill'
      }
    })

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'test-pkg', 'opencode')

    # Root SKILL.md should be in the . group
    root_sub = manifest[:sub_skills].find { |s| s[:path] == '.' }
    assert root_sub, 'should have root sub-skill for root-level SKILL.md'
    assert root_sub[:files].key?('SKILL.md'), 'root should have root SKILL.md'

    # auth should be its own sub-skill
    auth_sub = manifest[:sub_skills].find { |s| s[:path] == 'auth' }
    assert auth_sub, 'should have auth sub-skill'
    assert_nil root_sub[:files]['auth/SKILL.md'], 'auth SKILL.md should not be in root group'
  end

  def test_no_skill_md_at_all
    # A directory with no SKILL.md at any level produces a . group with root files.
    pkg_dir = build_bundle_dir(@tmpdir, {
      'readme.md' => '# Readme',
      'config.yaml' => 'key: value'
    })

    manifest = Rulepack::Common.generate_skill_bundle_manifest(pkg_dir, 'test-pkg', 'opencode')

    # Should have 1 sub-skill: . (root group with loose files)
    assert_equal 1, manifest[:sub_skills].size, "should have 1 . sub-skill, got #{manifest[:sub_skills].size}"
    root_sub = manifest[:sub_skills].find { |s| s[:path] == '.' }
    assert root_sub, 'should have root . sub-skill'
    assert_includes root_sub[:files].keys, 'readme.md', 'root should have readme.md'
    assert_includes root_sub[:files].keys, 'config.yaml', 'root should have config.yaml'
  end
end
