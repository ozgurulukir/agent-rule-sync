# frozen_string_literal: true

require 'helper'
require 'rulepack/bump'

class TestBump < Minitest::Test
  def test_discover_git_packages_finds_real_packages
    packages = Rulepack::Bump.discover_git_packages
    assert packages.key?(:'vibe-security'), 'Expected vibe-security in git packages'
    assert packages.key?(:'antigravity-skills'), 'Expected antigravity-skills in git packages'
    assert packages.key?(:'cc-skills-golang'), 'Expected cc-skills-golang in git packages'
    assert packages.key?(:'ruby-update-signatures'), 'Expected ruby-update-signatures in git packages'
  end

  def test_discover_git_packages_structure
    packages = Rulepack::Bump.discover_git_packages
    pkg = packages[:'vibe-security']
    assert_instance_of Hash, pkg
    assert_equal 'https://github.com/raroque/vibe-security-skill.git', pkg[:url]
    assert_equal 'main', pkg[:ref]
    assert_equal 'vibe-security/SKILL.md', pkg[:path]
    assert_equal '0.1.0', pkg[:pkgver]
  end

  def test_discover_ignores_local_packages
    packages = Rulepack::Bump.discover_git_packages
    refute packages.key?(:'memory'), 'memory is local, should not appear'
    refute packages.key?(:'shell'), 'shell is local, should not appear'
    refute packages.key?(:'ast-grep'), 'ast-grep is local, should not appear'
  end

  def test_cached_commit_for_missing_index
    commit = Rulepack::Bump.cached_commit_for(:nonexistent)
    assert_nil commit
  end

  def test_cached_commit_for_checksums_source_fallback
    with_tmpdir do |dir|
      index_path = dir.join('build', 'index.yaml')
      index_path.parent.mkpath
      index_data = {
        version: 3.0,
        packages: {
          'skill-pkg': {
            pkgver: '1.0.0',
            checksums: { source: 'abc123def456' },
            targets: []
          }
        }
      }
      index_path.write(index_data.to_yaml)

      old = Rulepack::Common.build_index_path
      Rulepack::Common.build_index_path = index_path
      commit = Rulepack::Bump.cached_commit_for(:'skill-pkg')
      Rulepack::Common.build_index_path = old

      assert_equal 'abc123def456', commit
    end
  end

  def test_cached_commit_for_source_sha256_preferred
    with_tmpdir do |dir|
      index_path = dir.join('build', 'index.yaml')
      index_path.parent.mkpath
      index_data = {
        version: 3.0,
        packages: {
          'bundle-pkg': {
            pkgver: '1.0.0',
            source_sha256: 'prefer_this',
            checksums: { source: 'fallback_value' },
            targets: []
          }
        }
      }
      index_path.write(index_data.to_yaml)

      old = Rulepack::Common.build_index_path
      Rulepack::Common.build_index_path = index_path
      commit = Rulepack::Bump.cached_commit_for(:'bundle-pkg')
      Rulepack::Common.build_index_path = old

      assert_equal 'prefer_this', commit
    end
  end

  def test_date_based_version
    ver = Rulepack::Bump.date_based_version
    assert_match(/\A\d{4}\.\d{2}\.\d{2}\z/, ver)
  end

  def test_deep_stringify_keys_simple
    input = { a: 1, b: 'hello' }
    result = Rulepack::Bump.deep_stringify_keys(input)
    assert_equal({ 'a' => 1, 'b' => 'hello' }, result)
  end

  def test_deep_stringify_keys_nested
    input = { a: { b: { c: 2 } } }
    result = Rulepack::Bump.deep_stringify_keys(input)
    assert_equal({ 'a' => { 'b' => { 'c' => 2 } } }, result)
  end

  def test_deep_stringify_keys_with_array
    input = { items: [{ name: 'x' }, { name: 'y' }] }
    result = Rulepack::Bump.deep_stringify_keys(input)
    assert_equal({ 'items' => [{ 'name' => 'x' }, { 'name' => 'y' }] }, result)
  end

  def test_deep_stringify_keys_preserves_scalars
    input = { num: 42, flag: true, text: 'ok', sym: :thing }
    result = Rulepack::Bump.deep_stringify_keys(input)
    assert_equal 42, result['num']
    assert_equal true, result['flag']
    assert_equal 'ok', result['text']
  end

  def test_parse_args_default
    opts = Rulepack::Bump.parse_args([])
    refute opts[:apply]
    assert_nil opts[:package_name]
  end

  def test_parse_args_apply
    opts = Rulepack::Bump.parse_args(['--apply'])
    assert opts[:apply]
  end

  def test_parse_args_with_package_name
    opts = Rulepack::Bump.parse_args(['vibe-security'])
    assert_equal 'vibe-security', opts[:package_name]
  end

  def test_parse_args_apply_and_package
    opts = Rulepack::Bump.parse_args(['--apply', 'vibe-security'])
    assert opts[:apply]
    assert_equal 'vibe-security', opts[:package_name]
  end

  def test_update_pkgbuild_string_keys
    with_tmpdir do |dir|
      pkgbuild = dir.join('test-pkg', 'PKGBUILD')
      pkgbuild.parent.mkpath
      pkgbuild.write({ 'pkgname' => 'test-pkg', 'pkgver' => '1.0.0', 'pkgrel' => 1 }.to_yaml)

      info = { pkgbuild_path: pkgbuild }
      Rulepack::Bump.update_pkgbuild(info, '2.0.0')

      raw = pkgbuild.read
      parsed = YAML.safe_load(raw)
      assert_equal '2.0.0', parsed['pkgver']
      assert_equal 1, parsed['pkgrel']
      refute_match(/^:pkgver:/, raw, 'PKGBUILD must use string keys, not symbol keys')
    end
  end

  def test_update_pkgbuild_preserves_fields
    with_tmpdir do |dir|
      original = {
        'pkgname' => 'my-pkg',
        'pkgver' => '0.5.0',
        'pkgrel' => 3,
        'epoch' => 1,
        'pkgdesc' => 'A test package',
        'tags' => %w[test demo]
      }
      pkgbuild = dir.join('my-pkg', 'PKGBUILD')
      pkgbuild.parent.mkpath
      pkgbuild.write(original.to_yaml)

      info = { pkgbuild_path: pkgbuild }
      Rulepack::Bump.update_pkgbuild(info, '1.0.0')

      parsed = YAML.safe_load(pkgbuild.read)
      assert_equal 'my-pkg', parsed['pkgname']
      assert_equal '1.0.0', parsed['pkgver']
      assert_equal 1, parsed['pkgrel']
      assert_equal 1, parsed['epoch']
      assert_equal 'A test package', parsed['pkgdesc']
      assert_equal %w[test demo], parsed['tags']
    end
  end

  def test_update_pkgbuild_no_change_if_same_version
    with_tmpdir do |dir|
      pkgbuild = dir.join('test-pkg', 'PKGBUILD')
      pkgbuild.parent.mkpath
      original_content = { 'pkgname' => 'test-pkg', 'pkgver' => '1.0.0', 'pkgrel' => 5 }.to_yaml
      pkgbuild.write(original_content)

      info = { pkgbuild_path: pkgbuild }
      Rulepack::Bump.update_pkgbuild(info, '1.0.0')

      assert_equal original_content, pkgbuild.read, 'File should not change if version is same'
    end
  end

  def test_fetch_remote_head_git_uses_end_of_options_separator
    url = 'https://github.com/example/repo.git'
    ref = 'main'

    captured = nil
    Open3.stub :capture3, lambda { |*args| captured = args; ['', '', Struct.new(:success?).new(false)] } do
      Rulepack::Bump.fetch_remote_head_git(url, ref)
    end

    assert captured, 'Open3.capture3 was not called'
    dash_index = captured.index('--')
    url_index = captured.index(url)
    ref_index = captured.index(ref)

    assert dash_index, 'Expected -- separator in git ls-remote call'
    assert dash_index < url_index, 'Expected -- before url'
    assert dash_index < ref_index, 'Expected -- before ref'
  end
end
