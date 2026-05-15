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

class TestCachedFetchUrlErrors < Minitest::Test
  def test_raises_on_sha256_mismatch
    error = assert_raises(RuntimeError) do
      # Base64-encoded "HTTPBIN is awesome" — wrong hash triggers mismatch
      Rulepack::Common.cached_fetch_url('https://httpbin.org/base64/SFRUUEJJTiBpcyBhd2Vzb21l', 'wrong' * 22)
    end
    assert_match(/SHA256 mismatch/, error.message)
  end
end
