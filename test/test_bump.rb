# frozen_string_literal: true

require 'helper'
require 'rulepack/bump'
require 'rulepack/build_all'
require 'rulepack/cli_parser'

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

      commit = Rulepack::Common.with_paths(build_index_path: index_path) do
        Rulepack::Bump.cached_commit_for(:'skill-pkg')
      end

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

      commit = Rulepack::Common.with_paths(build_index_path: index_path) do
        Rulepack::Bump.cached_commit_for(:'bundle-pkg')
      end

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

  def test_invoke_build_restores_index_when_rebuild_fails
    with_tmpdir do |dir|
      index_path = dir.join('build', 'index.yaml')
      index_path.parent.mkpath
      index_path.write({ version: 3.0, packages: { 'pkg' => { source_sha256: 'keep' } } }.to_yaml)

      failure = Rulepack::Result.new(status: :failure, errors: ['build exploded'])
      result = Rulepack::Common.with_paths(Rulepack::Paths.new(root: dir, build_dir: dir.join('build'))) do
        Rulepack::BuildAll.stub(:run, failure) { Rulepack::Bump.invoke_build }
      end

      assert result.failure?, 'a failed rebuild must surface as a failure Result'
      assert_includes result.errors.join(' '), 'restored from backup'
      assert_includes result.errors.join(' '), 'rulepack build'
      assert index_path.exist?, 'the old build index must survive a failed rebuild'
      assert_includes index_path.read, 'keep'
    end
  end

  def test_invoke_build_backup_survives_the_build_dir_wipe
    with_tmpdir do |dir|
      index_path = dir.join('build', 'index.yaml')
      index_path.parent.mkpath
      index_path.write({ version: 3.0, packages: { 'pkg' => { source_sha256: 'keep' } } }.to_yaml)

      # Simulate what the real Build.run does on failure: wipe build/ (where
      # the index lived) before reporting failure. A backup stored inside
      # build/ could not survive this — regression guard for P-AR(c).
      wipe_and_fail = lambda do
        FileUtils.rm_rf(dir.join('build'))
        Rulepack::Result.new(status: :failure, errors: ['build exploded'])
      end
      result = Rulepack::Common.with_paths(Rulepack::Paths.new(root: dir, build_dir: dir.join('build'))) do
        Rulepack::BuildAll.stub(:run, wipe_and_fail) { Rulepack::Bump.invoke_build }
      end

      assert result.failure?
      assert_includes result.errors.join(' '), 'restored from backup'
      assert index_path.exist?, 'the index must be restored from a backup that survived the wipe'
      assert_includes index_path.read, 'keep'
    end
  end

  def test_invoke_build_re_raises_and_restores_when_rebuild_raises
    with_tmpdir do |dir|
      index_path = dir.join('build', 'index.yaml')
      index_path.parent.mkpath
      index_path.write({ version: 3.0, packages: { 'pkg' => { source_sha256: 'keep' } } }.to_yaml)

      Rulepack::Common.with_paths(Rulepack::Paths.new(root: dir, build_dir: dir.join('build'))) do
        Rulepack::BuildAll.stub(:run, lambda { raise RuntimeError, 'kaboom' }) do
          assert_raises(RuntimeError) { Rulepack::Bump.invoke_build }
        end
      end

      assert index_path.exist?, 'an exception mid-rebuild must still restore the old index'
      assert_includes index_path.read, 'keep'
    end
  end

  def test_invoke_build_without_prior_index_reports_build_guidance
    with_tmpdir do |dir|
      failure = Rulepack::Result.new(status: :failure, errors: ['build exploded'])
      result = Rulepack::Common.with_paths(Rulepack::Paths.new(root: dir, build_dir: dir.join('build'))) do
        Rulepack::BuildAll.stub(:run, failure) { Rulepack::Bump.invoke_build }
      end

      assert result.failure?
      assert_includes result.errors.join(' '), 'no build index backup existed'
    end
  end

  def test_invoke_build_returns_build_result_and_cleans_backups
    with_tmpdir do |dir|
      index_path = dir.join('build', 'index.yaml')
      index_path.parent.mkpath
      index_path.write({ version: 3.0, packages: {} }.to_yaml)

      success = Rulepack::Result.new(status: :success, data: { packages_built: 3 }, view: :build)
      result = Rulepack::Common.with_paths(Rulepack::Paths.new(root: dir, build_dir: dir.join('build'))) do
        Rulepack::BuildAll.stub(:run, success) { Rulepack::Bump.invoke_build }
      end

      assert result.success?
      assert_equal 3, result.data[:packages_built]
      assert index_path.exist?
      assert_empty Pathname.glob((dir / 'index.yaml.bak.*').to_s),
                   'backups must be cleaned up after a successful rebuild'
    end
  end

  def test_apply_with_failed_rebuild_downgrades_status_to_failure
    info = { url: 'https://example.git', ref: 'main', path: '.', depth: 1,
             pkgver: '0.1.0', pkgver_func: nil,
             pkgbuild_path: Pathname.new('dummy'), pkg_data: {} }
    upstream = { testpkg: { status: :changed, remote: 'a' * 40, cached: 'b' * 40, message: 'changed' } }
    rebuild = Rulepack::Result.new(status: :failure, errors: ['boom'])

    result = Rulepack::Bump.stub(:discover_git_packages, { testpkg: info }) do
      Rulepack::Bump.stub(:check_upstream, ->(_packages) { upstream }) do
        Rulepack::Bump.stub(:compute_new_version, '9.9.9') do
          Rulepack::Bump.stub(:update_pkgbuild, nil) do
            Rulepack::Bump.stub(:invalidate_cache, nil) do
              Rulepack::Bump.stub(:invoke_build, rebuild) do
                Rulepack::Bump.run_unscoped(apply: true)
              end
            end
          end
        end
      end
    end

    assert_equal :failure, result.status, 'a failed rebuild must fail the bump, not exit 0'
    assert_includes result.errors, 'boom'
    assert result.data[:bump][:applied]
  end

  def test_cli_parses_apply_flag
    opts = Rulepack::CliParser.parse(['--apply'])
    assert opts[:apply]
    assert_nil opts[:package_name]
  end

  def test_cli_parses_apply_with_package_positional
    opts = Rulepack::CliParser.parse(['--apply', 'vibe-security'])
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
