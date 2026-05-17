# frozen_string_literal: true

require 'minitest/autorun'
require 'pathname'
require 'fileutils'
require 'digest'
require 'tmpdir'
require_relative '../lib/rulepack/common'

class TestDriftCms < Minitest::Test
  def setup
    @temp_dir = Pathname.new(Dir.mktmpdir('rulepack-drift-cms'))
    @file_path = @temp_dir.join('shared_config.txt')
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_verify_checksum_without_markers
    content = "Hello World\n"
    checksum = Digest::SHA256.hexdigest(content)
    @file_path.write(content)

    assert Rulepack::Common.verify_checksum(@file_path, checksum, 'my-pkg')
    refute Rulepack::Common.verify_checksum(@file_path, 'wrong-checksum', 'my-pkg')
  end

  def test_verify_checksum_with_markers_clean
    pkg_content = "This is my rule content\n"
    checksum = Digest::SHA256.hexdigest(pkg_content)
    
    # Write fully marked content
    marked = "<!-- rulepack:my-pkg start -->\nThis is my rule content\n\n<!-- rulepack:my-pkg end -->"
    @file_path.write(marked)

    assert Rulepack::Common.verify_checksum(@file_path, checksum, 'my-pkg')
  end

  def test_verify_checksum_with_markers_shared_file
    pkg_content = "This is my rule content\n"
    checksum = Digest::SHA256.hexdigest(pkg_content)
    
    # Write a shared file (like .bashrc) containing user custom code and marked content
    shared = <<~TXT
      # User custom configuration
      alias ll='ls -lh'

      <!-- rulepack:my-pkg start -->
      This is my rule content

      <!-- rulepack:my-pkg end -->

      # More user configuration
      export PATH=$PATH:/usr/local/bin
    TXT
    @file_path.write(shared)

    # Verification MUST pass, even with user custom configuration around the markers!
    assert Rulepack::Common.verify_checksum(@file_path, checksum, 'my-pkg')
  end

  def test_verify_checksum_with_markers_and_drift_inside
    pkg_content = "This is my rule content\n"
    checksum = Digest::SHA256.hexdigest(pkg_content)
    
    # Modify marked content (drift inside the rule!)
    drifted = <<~TXT
      # User custom configuration
      alias ll='ls -lh'

      <!-- rulepack:my-pkg start -->
      This is my MODIFIED rule content
      <!-- rulepack:my-pkg end -->

      # More user configuration
    TXT
    @file_path.write(drifted)

    # Verification MUST detect the drift and fail!
    refute Rulepack::Common.verify_checksum(@file_path, checksum, 'my-pkg')
  end
end
