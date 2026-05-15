# frozen_string_literal: true

# Unit tests for Rulepack::Common
# Covers: compare_versions, vercmp, format_version, validate_output_filename,
#         validate_target_dir, expand_user_path, strip_frontmatter, check_prerequisites,
#         load_pkgbuild, load_yaml, atomic_write, platform registry helpers

require_relative 'helper'

# ─── compare_versions ────────────────────────────────────────────────────────

class TestCompareVersions < Minitest::Test
  def test_equal_versions
    assert_equal 0, Rulepack::Common.compare_versions('1.0.0', '1.0.0')
  end

  def test_v1_greater_than_v2
    assert_equal 1, Rulepack::Common.compare_versions('2.0.0', '1.0.0')
  end

  def test_v1_less_than_v2
    assert_equal -1, Rulepack::Common.compare_versions('1.0.0', '2.0.0')
  end

  def test_alphanumeric_segments
    assert_equal 1, Rulepack::Common.compare_versions('1.2.3b', '1.2.3a')
    assert_equal -1, Rulepack::Common.compare_versions('1.2.3a', '1.2.3b')
    assert_equal 1, Rulepack::Common.compare_versions('1.2.4', '1.2.3')
  end

  def test_numeric_vs_alphanumeric
    # Numeric segments compared as integers: 10 > 9
    assert_equal 1, Rulepack::Common.compare_versions('1.10', '1.9')
  end

  def test_epoch_determines_winner_over_pkgver
    assert_equal 1, Rulepack::Common.compare_versions('1.0.0', '1.0.0', epoch1: 1, epoch2: 0)
    assert_equal -1, Rulepack::Common.compare_versions('1.0.0', '1.0.0', epoch1: 0, epoch2: 1)
  end

  def test_pkgrel_comparison_only_when_pkgver_equal
    assert_equal 1, Rulepack::Common.compare_versions('1.0.0', '1.0.0', pkgrel1: 2, pkgrel2: 1)
    assert_equal -1, Rulepack::Common.compare_versions('1.0.0', '1.0.0', pkgrel1: 1, pkgrel2: 2)
  end

  def test_pkgrel_ignored_when_pkgver_differs
    # pkgrel only matters when pkgver is equal
    assert_equal 1, Rulepack::Common.compare_versions('2.0.0', '1.0.0', pkgrel1: 1, pkgrel2: 99)
  end

  def test_full_version_components
    assert_equal 1, Rulepack::Common.compare_versions('1.0.0', '1.0.0', epoch1: 1, epoch2: 0, pkgrel1: 1, pkgrel2: 1)
  end

  def test_year_based_versioning
    assert_equal 1, Rulepack::Common.compare_versions('2026.05', '2026.04')
    assert_equal 0, Rulepack::Common.compare_versions('2026.05', '2026.05')
  end

  def test_single_segment_versions
    assert_equal 1, Rulepack::Common.compare_versions('2', '1')
    assert_equal 0, Rulepack::Common.compare_versions('1', '1')
    assert_equal -1, Rulepack::Common.compare_versions('1', '2')
  end

  def test_three_segment_numeric_comparison
    # Multi-digit segments: 10 > 9 in the same position
    assert_equal 1, Rulepack::Common.compare_versions('1.10.0', '1.9.0')
    # First differing segment determines result: 9 < 10
    assert_equal -1, Rulepack::Common.compare_versions('1.9.0', '1.10.0')
  end

  def test_epoch_zero_defaults
    # epoch=0 for both is default — should compare by pkgver only
    assert_equal 0, Rulepack::Common.compare_versions('1.0.0', '1.0.0', epoch1: 0, epoch2: 0)
  end

  def test_vercmp_alias
    # vercmp is the pacman-style comparator: a > b => 1, a == b => 0, a < b => -1
    assert_equal 1, Rulepack::Common.vercmp('2.0.0', '1.0.0')
    assert_equal 0, Rulepack::Common.vercmp('1.0.0', '1.0.0')
    assert_equal -1, Rulepack::Common.vercmp('1.0.0', '2.0.0')
  end
end

# ─── format_version ──────────────────────────────────────────────────────────

class TestFormatVersion < Minitest::Test
  def test_epoch_zero_omitted
    assert_equal '1.0.0-1', Rulepack::Common.format_version(0, '1.0.0', 1)
  end

  def test_epoch_nonzero_included
    assert_equal '1:1.0.0-1', Rulepack::Common.format_version(1, '1.0.0', 1)
    assert_equal '5:2.0.0-3', Rulepack::Common.format_version(5, '2.0.0', 3)
  end

  def test_various_pkgrels
    assert_equal '1.0.0-1',  Rulepack::Common.format_version(0, '1.0.0', 1)
    assert_equal '1.0.0-10', Rulepack::Common.format_version(0, '1.0.0', 10)
  end

  def test_double_digit_pkgrel
    assert_equal '1.0.0-99', Rulepack::Common.format_version(0, '1.0.0', 99)
  end

  def test_epoch_one_pkgrel_one
    assert_equal '1:1.0.0-1', Rulepack::Common.format_version(1, '1.0.0', 1)
  end

  def test_large_epoch
    assert_equal '10:3.0.0-2', Rulepack::Common.format_version(10, '3.0.0', 2)
  end
end

# ─── validate_output_filename ─────────────────────────────────────────────────

class TestValidateOutputFilename < Minitest::Test
  def test_valid_simple_filename
    assert_silent { Rulepack::Common.validate_output_filename('memory.md', 'memory') }
  end

  def test_valid_with_hyphen_and_numbers
    assert_silent { Rulepack::Common.validate_output_filename('00-memory.md', 'memory') }
  end

  def test_valid_underscore
    assert_silent { Rulepack::Common.validate_output_filename('my_rule.md', 'memory') }
  end

  def test_rejects_path_traversal_parent_dir
    assert_raises(RuntimeError) { Rulepack::Common.validate_output_filename('../etc/passwd', 'pkg') }
  end

  def test_rejects_absolute_path
    assert_raises(RuntimeError) { Rulepack::Common.validate_output_filename('/etc/passwd', 'pkg') }
  end

  def test_rejects_directory_separator
    assert_raises(RuntimeError) { Rulepack::Common.validate_output_filename('subdir/file.md', 'pkg') }
  end

  def test_rejects_empty_string
    assert_raises(RuntimeError) { Rulepack::Common.validate_output_filename('', 'pkg') }
  end

  def test_rejects_dotdot_only
    assert_raises(RuntimeError) { Rulepack::Common.validate_output_filename('..', 'pkg') }
  end

  def test_rejects_double_slash
    assert_raises(RuntimeError) { Rulepack::Common.validate_output_filename('a//b.md', 'pkg') }
  end
end

# ─── validate_target_dir ─────────────────────────────────────────────────────

class TestValidateTargetDir < Minitest::Test
  def test_valid_trailing_slash
    assert_silent { Rulepack::Common.validate_target_dir('golang-security-bundle/', 'pkg') }
  end

  def test_valid_no_trailing_slash
    assert_silent { Rulepack::Common.validate_target_dir('golang-security-bundle', 'pkg') }
  end

  def test_valid_nested_dir
    assert_silent { Rulepack::Common.validate_target_dir('skills/my-bundle/', 'pkg') }
  end

  def test_rejects_path_traversal_parent_dir
    assert_raises(RuntimeError) { Rulepack::Common.validate_target_dir('../../../etc/', 'pkg') }
  end

  def test_rejects_absolute_path
    assert_raises(RuntimeError) { Rulepack::Common.validate_target_dir('/absolute/path/', 'pkg') }
  end

  def test_rejects_dotdot_only
    assert_raises(RuntimeError) { Rulepack::Common.validate_target_dir('..', 'pkg') }
  end
end

# ─── expand_user_path ────────────────────────────────────────────────────────

class TestExpandUserPath < Minitest::Test
  def test_home_expansion
    result = Rulepack::Common.expand_user_path('~/projects')
    assert_equal File.expand_path('~/projects'), result
    refute_match(/\A~/, result)
  end

  def test_absolute_path_passthrough
    path = '/absolute/path'
    assert_equal path, Rulepack::Common.expand_user_path(path)
  end

  def test_relative_path_passthrough
    path = 'relative/path'
    assert_equal path, Rulepack::Common.expand_user_path(path)
  end

  def test_empty_string
    assert_equal '', Rulepack::Common.expand_user_path('')
  end

  def test_dot_path
    assert_equal '.', Rulepack::Common.expand_user_path('.')
  end
end

# ─── strip_frontmatter ───────────────────────────────────────────────────────

class TestStripFrontmatter < Minitest::Test
  def test_strips_yaml_frontmatter
    content = "---\ntitle: Test\n---\nBody text"
    result = Rulepack::Common.strip_frontmatter(content)
    assert_equal "Body text", result
  end

  def test_returns_content_without_frontmatter
    content = "No frontmatter here"
    assert_equal content, Rulepack::Common.strip_frontmatter(content)
  end

  def test_strips_frontmatter_with_blank_lines_after
    content = "---\ntitle: Test\n---\n\nBody text"
    result = Rulepack::Common.strip_frontmatter(content)
    assert_equal "Body text", result
  end

  def test_empty_content_returns_empty
    assert_equal '', Rulepack::Common.strip_frontmatter('')
  end

  def test_only_frontmatter_no_body
    content = "---\ntitle: Test\n---\n"
    result = Rulepack::Common.strip_frontmatter(content)
    assert_equal '', result
  end

  def test_frontmatter_with_leading_whitespace_not_matched
    content = "  ---\ntitle: Test\n---\nBody"
    result = Rulepack::Common.strip_frontmatter(content)
    assert_equal content, result
  end

  def test_multiline_frontmatter_body_stripped
    content = "---\ntitle: Hello\ndesc: World\nauthor: test\n---\nReal body"
    result = Rulepack::Common.strip_frontmatter(content)
    assert_equal "Real body", result
  end

  def test_opening_delimiter_only_not_stripped
    content = "---\ntitle: Test\nNo closing delimiter"
    result = Rulepack::Common.strip_frontmatter(content)
    assert_equal content, result
  end
end
