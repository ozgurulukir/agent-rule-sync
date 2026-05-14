# frozen_string_literal: true

# Unit tests for SSoT::Lib::Common
# Covers: compare_versions, vercmp, format_version, validate_output_filename,
#         validate_target_dir, expand_user_path, strip_frontmatter

require_relative 'helper'

class TestCompareVersions < Minitest::Test
  def test_equal_versions
    assert_equal 0, Ssot::Lib::Common.compare_versions('1.0.0', '1.0.0')
  end

  def test_v1_greater_than_v2
    assert_equal 1, Ssot::Lib::Common.compare_versions('2.0.0', '1.0.0')
  end

  def test_v1_less_than_v2
    assert_equal -1, Ssot::Lib::Common.compare_versions('1.0.0', '2.0.0')
  end

  def test_alphanumeric_segments
    assert_equal 1, Ssot::Lib::Common.compare_versions('1.2.3b', '1.2.3a')
    assert_equal -1, Ssot::Lib::Common.compare_versions('1.2.3a', '1.2.3b')
    assert_equal 1, Ssot::Lib::Common.compare_versions('1.2.4', '1.2.3')
  end

  def test_numeric_vs_alphanumeric
    # Numeric segments compared as integers: 10 > 9
    assert_equal 1, Ssot::Lib::Common.compare_versions('1.10', '1.9')
  end

  def test_epoch_comparison
    assert_equal 1, Ssot::Lib::Common.compare_versions('1.0.0', '1.0.0', epoch1: 1, epoch2: 0)
    assert_equal -1, Ssot::Lib::Common.compare_versions('1.0.0', '1.0.0', epoch1: 0, epoch2: 1)
  end

  def test_pkgrel_comparison_same_pkgver
    assert_equal 1, Ssot::Lib::Common.compare_versions('1.0.0', '1.0.0', pkgrel1: 2, pkgrel2: 1)
    assert_equal -1, Ssot::Lib::Common.compare_versions('1.0.0', '1.0.0', pkgrel1: 1, pkgrel2: 2)
  end

  def test_pkgrel_ignored_when_pkgver_differs
    # pkgrel only matters when pkgver is equal
    assert_equal 1, Ssot::Lib::Common.compare_versions('2.0.0', '1.0.0', pkgrel1: 1, pkgrel2: 99)
  end

  def test_full_version_components
    assert_equal 1, Ssot::Lib::Common.compare_versions('1.0.0', '1.0.0', epoch1: 1, epoch2: 0, pkgrel1: 1, pkgrel2: 1)
  end
end

class TestFormatVersion < Minitest::Test
  def test_epoch_zero_omitted
    assert_equal '1.0.0-1', Ssot::Lib::Common.format_version(0, '1.0.0', 1)
  end

  def test_epoch_nonzero_included
    assert_equal '1:1.0.0-1', Ssot::Lib::Common.format_version(1, '1.0.0', 1)
    assert_equal '5:2.0.0-3', Ssot::Lib::Common.format_version(5, '2.0.0', 3)
  end

  def test_various_pkgrels
    assert_equal '1.0.0-1', Ssot::Lib::Common.format_version(0, '1.0.0', 1)
    assert_equal '1.0.0-10', Ssot::Lib::Common.format_version(0, '1.0.0', 10)
  end
end

class TestValidateOutputFilename < Minitest::Test
  def test_valid_filename
    assert_silent { Ssot::Lib::Common.validate_output_filename('memory.md', 'memory') }
  end

  def test_valid_with_hyphen
    assert_silent { Ssot::Lib::Common.validate_output_filename('00-memory.md', 'memory') }
  end

  def test_rejects_path_traversal
    assert_raises(RuntimeError) { Ssot::Lib::Common.validate_output_filename('../etc/passwd', 'pkg') }
  end

  def test_rejects_absolute_path
    assert_raises(RuntimeError) { Ssot::Lib::Common.validate_output_filename('/etc/passwd', 'pkg') }
  end

  def test_rejects_directory_separator
    assert_raises(RuntimeError) { Ssot::Lib::Common.validate_output_filename('subdir/file.md', 'pkg') }
  end
end

class TestValidateTargetDir < Minitest::Test
  def test_valid_target_dir
    assert_silent { Ssot::Lib::Common.validate_target_dir('golang-security-bundle/', 'pkg') }
  end

  def test_rejects_path_traversal
    assert_raises(RuntimeError) { Ssot::Lib::Common.validate_target_dir('../../../etc/', 'pkg') }
  end
end

class TestExpandUserPath < Minitest::Test
  def test_home_expansion
    result = Ssot::Lib::Common.expand_user_path('~/projects')
    assert_equal File.expand_path('~/projects'), result
    refute_match(/\A~/, result)
  end

  def test_absolute_path_passthrough
    path = '/absolute/path'
    assert_equal path, Ssot::Lib::Common.expand_user_path(path)
  end

  def test_relative_path_passthrough
    path = 'relative/path'
    assert_equal path, Ssot::Lib::Common.expand_user_path(path)
  end
end

class TestStripFrontmatter < Minitest::Test
  def test_strips_yaml_frontmatter
    content = "---\ntitle: Test\n---\nBody text"
    result = Ssot::Lib::Common.strip_frontmatter(content)
    assert_equal "Body text", result
  end

  def test_returns_content_without_frontmatter
    content = "No frontmatter here"
    assert_equal content, Ssot::Lib::Common.strip_frontmatter(content)
  end

  def test_strips_frontmatter_with_blank_lines
    content = "---\ntitle: Test\n---\n\nBody text"
    result = Ssot::Lib::Common.strip_frontmatter(content)
    assert_equal "Body text", result
  end
end
