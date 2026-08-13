# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')

require 'minitest/autorun'
require 'rulepack'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'thread'

class TestRemoteCatalog < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-remote-catalog-test-')
    @index_data = {
      'packages' => {
        'memory' => {
          'name' => 'memory',
          'version' => '1.0.0',
          'description' => 'Memory retention rules',
          'url' => 'http://localhost:0/memory.md',
          'sha256' => nil
        },
        'shell' => {
          'name' => 'shell',
          'version' => '2.0.0',
          'description' => 'Shell execution rules',
          'url' => 'http://localhost:0/shell.md',
          'sha256' => nil
        }
      }
    }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_search_by_name
    catalog = Rulepack::Catalog::RemoteCatalog.new('http://example.com/index.json')
    # Stub the index loading
    catalog.instance_variable_set(:@_index, @index_data['packages'])

    results = catalog.search('memory')
    assert_equal 1, results.length
    assert_equal 'memory', results.first[:name]
  end

  def test_search_by_description
    catalog = Rulepack::Catalog::RemoteCatalog.new('http://example.com/index.json')
    catalog.instance_variable_set(:@_index, @index_data['packages'])

    results = catalog.search('retention')
    assert_equal 1, results.length
    assert_equal 'memory', results.first[:name]
  end

  def test_search_no_match
    catalog = Rulepack::Catalog::RemoteCatalog.new('http://example.com/index.json')
    catalog.instance_variable_set(:@_index, @index_data['packages'])

    results = catalog.search('nonexistent')
    assert_empty results
  end

  def test_list_all
    catalog = Rulepack::Catalog::RemoteCatalog.new('http://example.com/index.json')
    catalog.instance_variable_set(:@_index, @index_data['packages'])

    results = catalog.list
    assert_equal 2, results.length
    names = results.map { |r| r[:name] }
    assert_includes names, 'memory'
    assert_includes names, 'shell'
  end

  def test_fetch_package_not_found
    catalog = Rulepack::Catalog::RemoteCatalog.new('http://example.com/index.json')
    catalog.instance_variable_set(:@_index, @index_data['packages'])

    assert_nil catalog.fetch_package('nonexistent')
  end
end

class TestLockfile < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-lockfile-test-')
    @lock_path = Pathname.new(@tmpdir).join('rulepack.lock')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_add_and_check_locked
    lock = Rulepack::Lockfile.new(@lock_path)
    lock.add('memory', version: '1.0.0', source_sha256: 'abc123')
    assert lock.locked?('memory', version: '1.0.0')
    refute lock.locked?('memory', version: '2.0.0')
    refute lock.locked?('shell')
  end

  def test_remove
    lock = Rulepack::Lockfile.new(@lock_path)
    lock.add('memory', version: '1.0.0')
    assert lock.locked?('memory')
    lock.remove('memory')
    refute lock.locked?('memory')
  end

  def test_enforce_passes
    lock = Rulepack::Lockfile.new(@lock_path)
    lock.add('memory', version: '1.0.0')
    assert lock.enforce!('memory', version: '1.0.0')
  end

  def test_enforce_fails_on_version_mismatch
    lock = Rulepack::Lockfile.new(@lock_path)
    lock.add('memory', version: '1.0.0')
    assert_raises(Rulepack::StateError) { lock.enforce!('memory', version: '2.0.0') }
  end

  def test_enforce_fails_on_not_locked
    lock = Rulepack::Lockfile.new(@lock_path)
    assert_raises(Rulepack::StateError) { lock.enforce!('memory', version: '1.0.0') }
  end

  def test_write_and_reload
    lock = Rulepack::Lockfile.new(@lock_path)
    lock.add('memory', version: '1.0.0', source_sha256: 'abc123')
    lock.add('shell', version: '2.0.0')
    lock.write!

    reloaded = Rulepack::Lockfile.new(@lock_path)
    assert reloaded.locked?('memory', version: '1.0.0')
    assert reloaded.locked?('shell', version: '2.0.0')
    assert_equal 2, reloaded.entries.size
  end

  def test_entries_returns_dup
    lock = Rulepack::Lockfile.new(@lock_path)
    lock.add('memory', version: '1.0.0')
    entries = lock.entries
    entries['new'] = { 'version' => '1' }
    refute lock.locked?('new'), 'entries must return a dup'
  end
end
