# frozen_string_literal: true

# Unit tests for Rulepack::IO marker-based content helpers.

require_relative 'helper'

class TestIO < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-io-test-')
    @path = Pathname.new(@tmpdir).join('AGENTS.md')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # ─── update_marked_content ───────────────────────────────────────────────────

  def test_update_creates_file_when_missing
    result = Rulepack::IO.update_marked_content(@path, 'memory', "# Memory\n")
    assert_equal :created, result
    assert @path.exist?
    assert_includes @path.read, '<!-- rulepack:memory start -->'
    assert_includes @path.read, '<!-- rulepack:memory end -->'
  end

  def test_update_appends_to_existing_file
    @path.write("# Existing header\n")
    result = Rulepack::IO.update_marked_content(@path, 'memory', "# Memory\n")
    assert_equal :appended, result
    content = @path.read
    assert_includes content, '# Existing header'
    assert_includes content, '<!-- rulepack:memory start -->'
  end

  def test_update_replaces_existing_block_idempotently
    Rulepack::IO.update_marked_content(@path, 'memory', "# Memory v1\n")
    Rulepack::IO.update_marked_content(@path, 'memory', "# Memory v2\n")
    content = @path.read
    refute_includes content, '# Memory v1'
    assert_includes content, '# Memory v2'
    assert_equal 1, content.scan('<!-- rulepack:memory start -->').size
  end

  def test_update_preserves_other_blocks
    Rulepack::IO.update_marked_content(@path, 'memory', "# Memory\n")
    Rulepack::IO.update_marked_content(@path, 'shell', "# Shell\n")
    content = @path.read
    assert_includes content, '# Memory'
    assert_includes content, '# Shell'
  end

  # ─── remove_marked_content ───────────────────────────────────────────────────

  def test_remove_returns_not_found_for_missing_file
    result = Rulepack::IO.remove_marked_content(@path, 'memory')
    assert_equal :not_found, result
  end

  def test_remove_returns_not_found_when_no_markers
    @path.write("# Existing content\n")
    result = Rulepack::IO.remove_marked_content(@path, 'memory')
    assert_equal :not_found, result
  end

  def test_remove_excises_block_and_preserves_surrounding_content
    @path.write("# Header\n\n<!-- rulepack:memory start -->\n# Memory\n<!-- rulepack:memory end -->\n\n# Footer\n")
    result = Rulepack::IO.remove_marked_content(@path, 'memory')
    assert_equal :removed, result
    content = @path.read
    assert_includes content, '# Header'
    assert_includes content, '# Footer'
    refute_includes content, '# Memory'
    refute_includes content, '<!-- rulepack:memory start -->'
  end

  def test_remove_deletes_file_when_only_block_remains
    Rulepack::IO.update_marked_content(@path, 'memory', "# Memory\n")
    result = Rulepack::IO.remove_marked_content(@path, 'memory')
    assert_equal :file_removed, result
    refute @path.exist?
  end

  def test_remove_only_removes_its_own_block
    Rulepack::IO.update_marked_content(@path, 'memory', "# Memory\n")
    Rulepack::IO.update_marked_content(@path, 'shell', "# Shell\n")
    result = Rulepack::IO.remove_marked_content(@path, 'memory')
    assert_equal :removed, result
    content = @path.read
    refute_includes content, '# Memory'
    assert_includes content, '# Shell'
  end
end
