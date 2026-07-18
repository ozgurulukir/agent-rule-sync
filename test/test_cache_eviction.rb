require 'minitest/autorun'
require 'fileutils'
require 'pathname'

require_relative '../lib/rulepack/config'
require_relative '../lib/rulepack/cache'
require_relative '../lib/rulepack/common'

module Rulepack
  module Config
    class << self
      attr_accessor :cache_max_size_mb
      def cache_dir_name
        '.test_cache_eviction'
      end
    end
  end

  module Common
    class << self
      attr_reader :warnings

      def log_warn(msg, log_file: nil)
        @warnings ||= []
        @warnings << msg
      end

      def clear_warnings
        @warnings = []
      end
    end
  end
end

class TestCacheEviction < Minitest::Test
  def setup
    @root = Pathname.new(__dir__).join('..').join(Rulepack::Config.cache_dir_name)
    FileUtils.rm_rf(@root)
    @root.mkpath
    Rulepack::Config.cache_max_size_mb = 1 # 1MB limit
    Rulepack::Common.clear_warnings
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def create_entry(name, size, time_offset = 0)
    dir = @root.join(name)
    dir.mkpath
    File.write(dir.join('data.bin'), "x" * size)
    File.utime(Time.now - time_offset, Time.now - time_offset, dir.to_s)
    dir
  end

  def test_eviction_removes_oldest
    # Limit is 1MB = 1048576 bytes
    # Create 3 files of 500KB. Total 1.5MB. One should be evicted (the oldest).
    create_entry('entry1', 512000, 10) # oldest
    create_entry('entry2', 512000, 5)
    create_entry('entry3', 512000, 0) # newest

    assert_equal 1536000, Rulepack::Common.cache_total_bytes

    Rulepack::Common.enforce_cache_limit!

    refute @root.join('entry1').exist?
    assert @root.join('entry2').exist?
    assert @root.join('entry3').exist?

    # 1.5MB - 500KB = 1.0MB (just under limit, or equal depending on dirs)
    # Actually 1024000 < 1048576. So one deletion is enough.
    assert Rulepack::Common.cache_total_bytes < 1048576
  end

  def test_eviction_handles_race_condition
    # To simulate race condition, we need to mock directory_size to delete the directory midway or mock oldest_dir.find to raise ENOENT.
    # A simple way is to override directory_size for this test
    create_entry('entry1', 512000, 10) # oldest
    create_entry('entry2', 512000, 5)
    create_entry('entry3', 512000, 0) # newest

    # Mock directory_size to raise ENOENT on the first call
    original_method = Rulepack::Common.method(:directory_size)
    call_count = 0
    Rulepack::Common.define_singleton_method(:directory_size) do |path|
      if path.to_s.end_with?('entry1')
        FileUtils.rm_rf(path) # Simulate external deletion
        raise Errno::ENOENT, "No such file or directory @ dir_s_rmdir - #{path}"
      end
      original_method.call(path)
    end

    begin
      Rulepack::Common.enforce_cache_limit!

      # Should have continued to entry2 since entry1 raised
      refute @root.join('entry1').exist? # We deleted it in the mock
      refute @root.join('entry2').exist? # It was evicted properly because total was still too high after entry1 was skipped (its size wasn't subtracted from total_bytes, so total_bytes was still > limit)
      assert @root.join('entry3').exist?

      assert_includes Rulepack::Common.warnings.first, "Warning: File disappeared during eviction: "
    ensure
      Rulepack::Common.define_singleton_method(:directory_size, &original_method)
    end
  end
end
