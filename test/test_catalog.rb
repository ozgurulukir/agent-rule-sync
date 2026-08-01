# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')

require 'minitest/autorun'
require 'rulepack'
require 'tmpdir'
require 'fileutils'

class TestCatalog < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-catalog-test-')
    @pkg_dir = Pathname.new(@tmpdir).join('pkg')
    @pkg_dir.mkpath
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_source_repository_interface_raises
    repo = Rulepack::Catalog::SourceRepository.new
    assert_raises(NotImplementedError) { repo.fetch({}) }
    assert_raises(NotImplementedError) { repo.directory({}) }
  end

  def test_local_catalog_fetch_local_file
    src_file = @pkg_dir.join('src', 'test.md')
    src_file.parent.mkpath
    src_file.write('hello world')

    catalog = Rulepack::Catalog::LocalCatalog.new
    result = catalog.fetch({ type: 'local', path: 'src/test.md' }, pkg_dir: @pkg_dir)

    assert_equal 'hello world', result.content
    assert_match(/\A[0-9a-f]{64}\z/, result.sha256)
    assert_nil result.source_dir
  end

  def test_local_catalog_directory_local
    src_dir = @pkg_dir.join('skills')
    src_dir.mkpath
    src_dir.join('skill1.md').write('skill 1')

    catalog = Rulepack::Catalog::LocalCatalog.new
    dir = catalog.directory({ type: 'local', path: 'skills/' }, pkg_dir: @pkg_dir)

    assert dir.directory?
    assert_equal src_dir.cleanpath, dir
  end

  def test_source_result_is_frozen
    result = Rulepack::Catalog::SourceResult.new(content: 'test', sha256: 'abc', source_dir: nil)
    assert_raises(FrozenError) { result.instance_variable_set(:@x, 1) }
  end
end
