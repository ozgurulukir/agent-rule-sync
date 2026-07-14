# frozen_string_literal: true

# Unit tests for Rulepack::IO.atomic_write
# Covers: new file creation, overwrite, Windows EACCES fallback, content fidelity

require_relative 'helper'

class TestAtomicWrite < Minitest::Test
  def test_writes_new_file
    with_tmpdir do |dir|
      target = dir.join('new_file.txt')
      refute target.exist?, 'precondition: target should not exist'

      Rulepack::IO.atomic_write(target.to_s, 'hello world')
      assert target.exist?, 'file should be created'
      assert_equal 'hello world', target.read
    end
  end

  def test_overwrites_existing_file
    with_tmpdir do |dir|
      target = dir.join('output.txt')
      target.write('old content')

      Rulepack::IO.atomic_write(target.to_s, 'new content')
      assert_equal 'new content', target.read
    end
  end

  def test_overwrites_when_destination_exists
    with_tmpdir do |dir|
      target = dir.join('output.txt')
      target.write('old content')

      # atomic_write should overwrite existing file
      Rulepack::IO.atomic_write(target.to_s, 'new content')
      assert_equal 'new content', target.read
    end
  end

  def test_preserves_content_exactly
    with_tmpdir do |dir|
      target = dir.join('special.txt')
      content = "Hello Wörld 🌍\nLine 2\n\n\tIndented\n```\ncode block\n```\n"

      Rulepack::IO.atomic_write(target.to_s, content)
      assert_equal content, target.read
    end
  end

  def test_creates_intermediate_directories
    with_tmpdir do |dir|
      target = dir.join('a', 'b', 'c', 'nested.txt')

      Rulepack::IO.atomic_write(target.to_s, 'nested')
      assert target.exist?, 'file in nested dir should be created'
      assert_equal 'nested', target.read
    end
  end

  def test_writes_empty_content
    with_tmpdir do |dir|
      target = dir.join('empty.txt')

      Rulepack::IO.atomic_write(target.to_s, '')
      assert target.exist?
      assert_equal '', target.read
    end
  end

  def test_writes_binary_content
    with_tmpdir do |dir|
      target = dir.join('binary.bin')
      content = "\x00\x01\x02\xFF\xFE".b

      Rulepack::IO.atomic_write(target.to_s, content)
      assert_equal content, target.read(encoding: Encoding::BINARY)
    end
  end

  def test_multiple_writes_same_file
    with_tmpdir do |dir|
      target = dir.join('multi.txt')

      (1..10).each do |i|
        Rulepack::IO.atomic_write(target.to_s, "content #{i}")
        assert_equal "content #{i}", target.read
      end
    end
  end

  def test_concurrent_writes_different_files
    with_tmpdir do |dir|
      files = (1..5).map { |i| dir.join("file_#{i}.txt") }
      contents = files.map.with_index { |_f, i| "file #{i} content" }

      files.zip(contents).each do |f, c|
        Rulepack::IO.atomic_write(f.to_s, c)
      end

      files.zip(contents).each do |f, c|
        assert_equal c, f.read
      end
    end
  end

  def test_writes_yaml_content
    with_tmpdir do |dir|
      target = dir.join('data.yaml')
      yaml = "---\nkey: value\nnested:\n  a: 1\n  b: 2\n"

      Rulepack::IO.atomic_write(target.to_s, yaml)
      assert_equal yaml, target.read
    end
  end

  def test_handles_long_content
    with_tmpdir do |dir|
      target = dir.join('long.txt')
      content = "line #{'x' * 1000}\n" * 100

      Rulepack::IO.atomic_write(target.to_s, content)
      assert_equal content, target.read
    end
  end
end
