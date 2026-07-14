# frozen_string_literal: true

# Unit tests for Rulepack::Common.extract_tar_gz
# Covers: legitimate extraction, path traversal prevention, symlink skipping,
#         false-positive guard for entries resolving to dest dir.

require_relative 'helper'

class TestExtractTarGz < Minitest::Test
  # Build an in-memory gzipped tarball from an array of entry descriptors.
  # Each entry: [full_name, content_or_nil, typeflag]
  #   typeflag: '0' = file, '5' = directory, '2' = symlink, '1' = hardlink
  #   For symlinks/hardlinks, content_or_nil is the link target.
  def build_tarball(entries)
    raw_tar = StringIO.new
    raw_tar.set_encoding('ASCII-8BIT')

    Gem::Package::TarWriter.new(raw_tar) do |tar|
      entries.each do |name, content, type|
        case type
        when '5'
          tar.mkdir(name, 0o755)
        when '2'
          tar.add_symlink(name, content, 0o644)
        when '1'
          # TarWriter doesn't support hardlinks natively.
          # Write a raw tar header with typeflag '1'.
          write_raw_hardlink_header(raw_tar, name, content.to_s)
        else
          tar.add_file_simple(name, 0o644, content.bytesize) { |f| f.write(content) }
        end
      end
    end

    # Gzip the raw tar data
    gz_io = StringIO.new
    gz_io.set_encoding('ASCII-8BIT')
    gz = Zlib::GzipWriter.new(gz_io)
    gz.write(raw_tar.string)
    gz.finish
    gz_io.string
  end

  # Write a raw tar header for a hardlink entry (typeflag '1').
  # Tar header is 512 bytes; typeflag at offset 156, linkname at offset 157.
  def write_raw_hardlink_header(io, name, linkname)
    header = "\0" * 512
    header[0, 100] = name.ljust(100, "\0")[0, 100]
    header[100, 8] = "0000644\0"
    header[108, 8] = "0001750\0"
    header[116, 8] = "0001750\0"
    header[124, 12] = "00000000000\0" # size = 0 for hardlinks
    header[136, 12] = "00000000000\0" # mtime
    header[156] = '1' # typeflag = hardlink
    header[157, 100] = linkname.ljust(100, "\0")[0, 100]
    # Calculate checksum: sum of all bytes, with chksum field treated as spaces
    header[148, 8] = "        " # 8 spaces for checksum calculation
    chksum = header.each_byte.sum
    header[148, 8] = sprintf("%06o", chksum) + "\0 "
    io.write(header)
  end

  def test_extracts_legitimate_tarball
    tar_gz = build_tarball([
      ['repo', nil, '5'],
      ['repo/file1.txt', 'hello', '0'],
      ['repo/subdir', nil, '5'],
      ['repo/subdir/file2.txt', 'world', '0']
    ])

    with_tmpdir do |dest|
      Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)

      f1 = dest.join('file1.txt')
      f2 = dest.join('subdir', 'file2.txt')

      assert f1.exist?, 'Expected file1.txt to be extracted'
      assert_equal 'hello', f1.read
      assert f2.exist?, 'Expected subdir/file2.txt to be extracted'
      assert_equal 'world', f2.read
    end
  end

  def test_blocks_path_traversal_with_dotdot
    tar_gz = build_tarball([
      ['repo', nil, '5'],
      ['repo/../../escape.txt', 'pwned', '0']
    ])

    with_tmpdir do |dest|
      parent = dest.parent
      files_before = parent.each_child.to_a

      assert_raises(Rulepack::Common::PathTraversalError) do
        Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)
      end

      files_after = parent.each_child.to_a
      new_files = files_after - files_before
      assert_empty new_files, 'No files should have been created outside dest_dir'
    end
  end

  def test_blocks_absolute_path_traversal
    # Entry with enough '..' segments to escape above the dest dir
    tar_gz = build_tarball([
      ['repo', nil, '5'],
      ['repo/../../../tmp/escape.txt', 'pwned', '0']
    ])

    with_tmpdir do |dest|
      assert_raises(Rulepack::Common::PathTraversalError) do
        Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)
      end
    end
  end

  def test_allows_entry_resolving_to_dest_dir
    # Entry like 'repo/.' resolves to dest_dir itself — should not raise PathTraversalError
    tar_gz = build_tarball([
      ['repo', nil, '5'],
      ['repo/.', nil, '5']
    ])

    with_tmpdir do |dest|
      # Should not raise — entry resolves to dest_dir itself
      Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)
    end
  end

  def test_skips_symlinks
    tar_gz = build_tarball([
      ['repo', nil, '5'],
      ['repo/link', '../../etc/passwd', '2']
    ])

    with_tmpdir do |dest|
      # Should not raise — symlinks are skipped, not validated
      Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)

      # Verify no symlink was created
      link_path = dest.join('link')
      refute link_path.exist?, 'Symlink should not have been created'
      refute link_path.symlink?, 'Symlink should not have been created'
    end
  end

  def test_blocks_traversal_in_subdirectory_entry
    # Entry with '..' segments that escape above the dest dir
    tar_gz = build_tarball([
      ['repo', nil, '5'],
      ['repo/sub/../../../escape.txt', 'pwned', '0']
    ])

    with_tmpdir do |dest|
      assert_raises(Rulepack::Common::PathTraversalError) do
        Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)
      end
    end
  end

  def test_warns_on_hardlink_entries
    tar_gz = build_tarball([
      ['repo', nil, '5'],
      ['repo/file.txt', 'content', '0'],
      ['repo/hardlink', 'repo/file.txt', '1']
    ])

    with_tmpdir do |dest|
      # Hardlinks are not supported — should warn but not raise
      Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)

      # The regular file should still be extracted
      assert dest.join('file.txt').exist?, 'Regular file should be extracted'
      # The hardlink entry should be skipped (not created)
      refute dest.join('hardlink').exist?, 'Hardlink entry should be skipped'
    end
  end

  def test_flat_tarball_entries_are_skipped
    # Tarballs without a top-level directory have entries with parts.size <= 1
    # after splitting by '/'. These are silently skipped by the current implementation.
    tar_gz = build_tarball([
      ['file.txt', 'hello', '0']
    ])

    with_tmpdir do |dest|
      # Should not raise — flat entries are silently skipped
      Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)

      # The file is NOT extracted because the top-level skip drops it
      refute dest.join('file.txt').exist?, 'Flat tarball entries are skipped by design'
    end
  end

  def test_allows_nested_dotdot_that_cancels_out
    # repo/foo/../bar/file.txt resolves to dest_dir/bar/file.txt — within bounds
    tar_gz = build_tarball([
      ['repo', nil, '5'],
      ['repo/foo/../bar/file.txt', 'content', '0']
    ])

    with_tmpdir do |dest|
      Rulepack::Common.extract_tar_gz(tar_gz, dest.to_s)

      assert dest.join('bar', 'file.txt').exist?, 'Nested .. that cancels out should be allowed'
      assert_equal 'content', dest.join('bar', 'file.txt').read
    end
  end
end
