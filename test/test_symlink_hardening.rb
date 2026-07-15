# frozen_string_literal: true

# Regression tests for symlink traversal hardening (CVE companion to PR #5).
# Covers three layers that operate on untrusted git/url sources:
#   1. BuildPerPkg.strip_symlinks_in_tree — removes symlinks after source cp_r
#   2. Common.generate_skill_bundle_manifest — skips symlinks when hashing files
#   3. InstallExecute.strip_symlinks_in_tree — removes symlinks after install cp_r
#
# Without these guards, a symlinked .md planted in a fetched git source would be
# followed by File.write / path.read, allowing arbitrary file overwrite/read.

require_relative 'helper'
require 'rulepack/build_per_pkg'
require 'rulepack/install_execute'

class TestSymlinkHardeningBuild < Minitest::Test
  # strip_symlinks_in_tree must remove symlinks but leave regular files intact.
  def test_build_strip_removes_symlinks_keeps_files
    with_tmpdir do |src|
      (src / 'real.md').write('# real')
      subdir = src / 'sub'
      subdir.mkpath
      (subdir / 'note.md').write('# nested')
      # Plant a symlink pointing outside the tree.
      File.symlink('/etc/hostname', src / 'evil.md')

      Rulepack::BuildPerPkg.strip_symlinks_in_tree(src)

      assert (src / 'real.md').file?, 'regular file must remain'
      assert (subdir / 'note.md').file?, 'nested regular file must remain'
      refute (src / 'evil.md').symlink?, 'symlink must be removed'
      refute (src / 'evil.md').exist?, 'symlink target must not be created'
    end
  end

  def test_build_strip_handles_missing_dir
    # Should not raise on a non-existent path.
    assert_nil Rulepack::BuildPerPkg.strip_symlinks_in_tree('/nonexistent-rulepack-test-xyz')
  end

  def test_build_strip_handles_dotfiles
    with_tmpdir do |src|
      (src / '.hidden').write('keep me')
      File.symlink('/etc/hostname', src / '.evil_link')
      Rulepack::BuildPerPkg.strip_symlinks_in_tree(src)
      assert (src / '.hidden').file?, 'dotfile must remain'
      refute (src / '.evil_link').symlink?, 'dotfile symlink must be removed'
    end
  end
end

class TestSymlinkHardeningManifest < Minitest::Test
  # generate_skill_bundle_manifest must not follow symlinks when hashing files.
  def test_manifest_skips_symlinked_files
    with_tmpdir do |build_dir|
      skill = build_dir / 'my-skill'
      skill.mkpath
      (skill / 'SKILL.md').write('# legit')
      # Symlink whose target we control; if followed, its content would be hashed.
      outside = build_dir / 'outside-secret'
      outside.write('TOP-SECRET-PAYLOAD')
      File.symlink(outside.expand_path, skill / 'leak.md')

      manifest = Rulepack::Common.generate_skill_bundle_manifest(build_dir, 'my-skill', 'opencode')

      # The leaked symlink must not appear in any sub-skill file list, and the
      # secret payload must not be hashed into the manifest.
      all_files = manifest[:sub_skills].flat_map { |s| s[:files].keys }
      refute_includes all_files, 'my-skill/leak.md', 'symlinked file must be excluded from manifest'
      json = JSON.generate(manifest)
      refute_includes json, 'TOP-SECRET-PAYLOAD', 'symlink target content must not leak into manifest'
      assert_includes all_files, 'my-skill/SKILL.md', 'legitimate file must be present'
    end
  end
end

class TestSymlinkHardeningInstall < Minitest::Test
  # install_execute.strip_symlinks_in_tree mirrors the build-time strip on the
  # install path, defending against symlinks reaching the user's agents dir.
  def test_install_strip_removes_symlinks
    with_tmpdir do |dest|
      (dest / 'agent.md').write('# agent')
      File.symlink('/etc/hostname', dest / 'payload.md')

      Rulepack::InstallExecute.strip_symlinks_in_tree(dest)

      assert (dest / 'agent.md').file?, 'regular file must remain'
      refute (dest / 'payload.md').symlink?, 'symlink must be removed from install tree'
    end
  end

  def test_install_strip_handles_missing_dir
    assert_nil Rulepack::InstallExecute.strip_symlinks_in_tree('/nonexistent-rulepack-install-xyz')
  end
end
