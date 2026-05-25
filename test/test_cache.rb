# frozen_string_literal: true

# Unit tests for Rulepack::Common cache functions
# Covers: cache_key_for_source, cache_dir, source_cached?,
#         cache_source, get_cached_source, get_cached_git_source,
#         cached_fetch_url (error paths)

require_relative 'helper'

class TestCacheKeyForSource < Minitest::Test
  def test_url_uses_sha256
    source = { type: 'url', url: 'https://example.com/test', sha256: 'abc123' * 8 }
    key = Rulepack::Common.cache_key_for_source(source)
    assert_equal 'abc123' * 8, key
  end

  def test_url_uses_override_hash
    source = { type: 'url', url: 'https://example.com/test' }
    key = Rulepack::Common.cache_key_for_source(source, 'override' * 8)
    assert_equal 'override' * 8, key
  end

  def test_url_raises_without_sha256
    source = { type: 'url', url: 'https://example.com/test' }
    assert_raises(RuntimeError, /No sha256/) { Rulepack::Common.cache_key_for_source(source) }
  end

  def test_git_uses_commit_hash
    source = { type: 'git', url: 'https://github.com/owner/repo.git' }
    key = Rulepack::Common.cache_key_for_source(source, 'deadbeef' * 8)
    assert_equal 'deadbeef' * 8, key
  end

  def test_git_raises_without_commit_hash
    source = { type: 'git', url: 'https://github.com/owner/repo.git' }
    assert_raises(RuntimeError, /No commit hash/) { Rulepack::Common.cache_key_for_source(source) }
  end

  def test_local_uses_source_hash
    source = { type: 'local', path: 'src/file.md' }
    key = Rulepack::Common.cache_key_for_source(source, 'localhash' * 6)
    assert_equal 'localhash' * 6, key
  end

  def test_local_raises_without_hash
    source = { type: 'local', path: 'src/file.md' }
    assert_raises(RuntimeError, /No source hash/) { Rulepack::Common.cache_key_for_source(source) }
  end

  def test_unknown_type_returns_nil
    source = { type: 'unknown' }
    assert_nil Rulepack::Common.cache_key_for_source(source, 'anyhash')
  end
end

class TestCacheDir < Minitest::Test
  def test_returns_correct_path
    dir = Rulepack::Common.cache_dir('testkey123')
    assert_equal ROOT.join('cache', 'testkey123'), dir
  end

  def test_returns_pathname
    dir = Rulepack::Common.cache_dir('key')
    assert_kind_of Pathname, dir
  end
end

class TestSourceCached < Minitest::Test
  def setup
    @test_key = 'ssot-cache-test-key-' + Time.now.to_i.to_s
    @cache_dir = ROOT.join('cache', @test_key)
  end

  def teardown
    FileUtils.rm_rf(@cache_dir)
  end

  def test_returns_true_when_extracted_exists
    @cache_dir.mkpath
    (@cache_dir / 'extracted').mkdir
    assert Rulepack::Common.source_cached?(@test_key)
  end

  def test_returns_false_when_no_cache_dir
    refute Rulepack::Common.source_cached?(@test_key), 'should be false when cache dir missing'
  end

  def test_returns_false_when_extracted_missing
    @cache_dir.mkpath
    refute Rulepack::Common.source_cached?(@test_key), 'should be false when extracted/ missing'
  end
end

class TestCacheSource < Minitest::Test
  def setup
    @test_key = 'ssot-cache-src-test-' + Time.now.to_i.to_s
    @cache_dir = ROOT.join('cache', @test_key)
  end

  def teardown
    FileUtils.rm_rf(@cache_dir)
  end

  def test_cache_content_type
    Rulepack::Common.cache_source(@test_key, 'hello world', source_type: 'content')
    cached = (@cache_dir / 'extracted' / 'source').read
    assert_equal 'hello world', cached
  end

  def test_cache_file_type_single_file
    src_dir = Pathname.new(Dir.mktmpdir('cache-src'))
    src_file = src_dir / 'data.txt'
    src_file.write('file content')
    Rulepack::Common.cache_source(@test_key, src_file.to_s, source_type: 'file')
    cached = (@cache_dir / 'extracted' / 'source').read
    assert_equal 'file content', cached
  ensure
    FileUtils.rm_rf(src_dir)
  end

  def test_cache_file_type_directory
    src_dir = Pathname.new(Dir.mktmpdir('cache-src-dir'))
    (src_dir / 'a.txt').write('a')
    (src_dir / 'b.txt').write('b')
    Rulepack::Common.cache_source(@test_key, src_dir.to_s, source_type: 'file')
    assert (@cache_dir / 'extracted' / 'a.txt').exist?, 'a.txt should be cached'
    assert (@cache_dir / 'extracted' / 'b.txt').exist?, 'b.txt should be cached'
  ensure
    FileUtils.rm_rf(src_dir)
  end

  def test_cache_creates_extracted_dir
    Rulepack::Common.cache_source(@test_key, 'data', source_type: 'content')
    assert (@cache_dir / 'extracted').directory?, 'extracted/ dir should be created'
  end
end

class TestGetCachedSource < Minitest::Test
  def setup
    @test_key = 'ssot-get-cache-test-' + Time.now.to_i.to_s
    @cache_dir = ROOT.join('cache', @test_key)
    @extracted = @cache_dir / 'extracted'
    @extracted.mkpath
    (@extracted / 'myfile.txt').write('cached content')
  end

  def teardown
    FileUtils.rm_rf(@cache_dir)
  end

  def test_get_cached_source_specific_file
    content = Rulepack::Common.get_cached_source(@test_key, 'myfile.txt')
    assert_equal 'cached content', content
  end

  def test_get_cached_source_default_returns_first_file
    content = Rulepack::Common.get_cached_source(@test_key)
    assert_equal 'cached content', content
  end

  def test_get_cached_source_raises_on_missing_file
    assert_raises(RuntimeError, /Cached file not found/) do
      Rulepack::Common.get_cached_source(@test_key, 'nonexistent.txt')
    end
  end

  def test_get_cached_source_raises_on_cache_miss
    assert_raises(RuntimeError, /Cache miss/) { Rulepack::Common.get_cached_source('nonexistent-key') }
  end
end

class TestGetCachedGitSource < Minitest::Test
  def setup
    @test_key = 'ssot-git-cache-test-' + Time.now.to_i.to_s
    @cache_dir = ROOT.join('cache', @test_key)
  end

  def teardown
    FileUtils.rm_rf(@cache_dir)
  end

  def test_returns_extracted_path_when_cached
    @cache_dir.mkpath
    (@cache_dir / 'extracted').mkdir
    result = Rulepack::Common.get_cached_git_source(@test_key)
    assert_equal @cache_dir / 'extracted', result
  end

  def test_returns_nil_when_not_cached
    result = Rulepack::Common.get_cached_git_source(@test_key)
    assert_nil result
  end
end

# ─── Enforce Cache Limit ─────────────────────────────────────────────────────────

class TestEnforceCacheLimit < Minitest::Test
  def setup
    @root = ROOT.join('cache')
    # Use unique keys each run to avoid collisions
    ts = Time.now.to_i.to_s
    @old_key = "limit-old-#{ts}"
    @new_key = "limit-new-#{ts}"
    @old_dir = @root.join(@old_key)
    @new_dir = @root.join(@new_key)
  end

  def teardown
    FileUtils.rm_rf(@old_dir)
    FileUtils.rm_rf(@new_dir)
  end

  def _write_cache_entry(dir, bytes)
    FileUtils.mkpath(dir.join('extracted'))
    File.write(dir.join('extracted', 'source'), 'x' * bytes)
  end

  def _total_cache_size
    total = 0
    @root.find { |e| total += e.size if e.file? }
    total
  end

  def test_evicts_oldest_when_over_one_mb_limit
    # Create two entries: ~700 KB each → total ~1.4 MB > 1 MB limit
    _write_cache_entry(@old_dir, 700_000)
    _write_cache_entry(@new_dir, 700_000)

    # Temporarily set limit to 1 MB
    orig = ENV['RULEPACK_CACHE_MAX_MB']
    ENV['RULEPACK_CACHE_MAX_MB'] = '1'
    Rulepack::Config.send(:remove_method, :cache_max_size_mb) if Rulepack::Config.method_defined?(:cache_max_size_mb)
    Rulepack::Common.enforce_cache_limit!
    ENV['RULEPACK_CACHE_MAX_MB'] = orig if orig
    # Reload config to pick up original value
    load File.join(__dir__, '..', 'lib', 'rulepack', 'config.rb')

    # oldest entry should have been evicted
    refute @old_dir.exist?, 'oldest cache entry should have been evicted'
  end

  def test_no_eviction_when_under_limit
    _write_cache_entry(@new_dir, 1000)  # 1 KB

    orig = ENV['RULEPACK_CACHE_MAX_MB']
    ENV['RULEPACK_CACHE_MAX_MB'] = '10'
    load File.join(__dir__, '..', 'lib', 'rulepack', 'config.rb')
    Rulepack::Common.enforce_cache_limit!
    ENV['RULEPACK_CACHE_MAX_MB'] = orig if orig
    load File.join(__dir__, '..', 'lib', 'rulepack', 'config.rb')

    assert @new_dir.exist?, 'small cache entry should not be evicted'
  end

  def test_disabled_when_max_mb_is_zero
    _write_cache_entry(@new_dir, 100_000)

    orig = ENV['RULEPACK_CACHE_MAX_MB']
    ENV['RULEPACK_CACHE_MAX_MB'] = '0'
    load File.join(__dir__, '..', 'lib', 'rulepack', 'config.rb')
    Rulepack::Common.enforce_cache_limit!
    ENV['RULEPACK_CACHE_MAX_MB'] = orig if orig
    load File.join(__dir__, '..', 'lib', 'rulepack', 'config.rb')

    assert @new_dir.exist?, 'cache entry should not be evicted when limit is 0 (disabled)'
  end
end

class TestCachedFetchUrlErrors < Minitest::Test
  def test_raises_on_sha256_mismatch
    error = assert_raises(RuntimeError) do
      # Base64-encoded "HTTPBIN is awesome" — wrong hash triggers mismatch
      Rulepack::Common.cached_fetch_url('https://httpbin.org/base64/SFRUUEJJTiBpcyBhd2Vzb21l', 'wrong' * 22)
    end
    assert_match(/SHA256 mismatch/, error.message)
  end
end
