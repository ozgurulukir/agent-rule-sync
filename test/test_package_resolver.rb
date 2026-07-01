# frozen_string_literal: true

require_relative 'helper'
require 'rulepack/package_resolver'
require 'fileutils'

class TestPackageResolver < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rulepack-resolver-test')
    @packages_root = File.join(@root, 'data', 'packages')
    FileUtils.mkdir_p(@packages_root)

    # Stub RULEPACK_ROOT for the resolver.
    @original_root = Rulepack::Common::RULEPACK_ROOT
    Rulepack::Common.send(:remove_const, :RULEPACK_ROOT)
    Rulepack::Common.const_set(:RULEPACK_ROOT, Pathname.new(@root).expand_path)
  end

  def teardown
    Rulepack::Common.send(:remove_const, :RULEPACK_ROOT)
    Rulepack::Common.const_set(:RULEPACK_ROOT, @original_root)
    FileUtils.rm_rf(@root)
  end

  def write_pkgbuild(path, pkgname)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, <<~YAML)
      ---
      pkgname: #{pkgname}
      pkgver: '1.0.0'
      pkgrel: 1
      pkg_type: rule
      source:
      - type: local
        path: #{pkgname}.md
    YAML
  end

  def test_pkgbuild_path_falls_back_to_legacy
    write_pkgbuild(File.join(@packages_root, 'legacy-pkg', 'PKGBUILD'), 'legacy-pkg')
    path = Rulepack::PackageResolver.pkgbuild_path('legacy-pkg')
    assert path.exist?
    assert_equal 'legacy-pkg', path.dirname.basename.to_s
  end

  def test_pkgbuild_path_prefers_local_over_legacy
    write_pkgbuild(File.join(@packages_root, 'local', 'shared', 'PKGBUILD'), 'shared')
    write_pkgbuild(File.join(@packages_root, 'shared', 'PKGBUILD'), 'shared')

    path = Rulepack::PackageResolver.pkgbuild_path('shared')
    assert path.exist?
    assert_equal Pathname.new('local'), path.dirname.dirname.basename
  end

  def test_pkgbuild_path_prefers_upstream_over_legacy
    write_pkgbuild(File.join(@packages_root, 'upstream', 'shared', 'PKGBUILD'), 'shared')
    write_pkgbuild(File.join(@packages_root, 'shared', 'PKGBUILD'), 'shared')

    path = Rulepack::PackageResolver.pkgbuild_path('shared')
    assert path.exist?
    assert_equal Pathname.new('upstream'), path.dirname.dirname.basename
  end

  def test_all_pkgbuilds_includes_all_namespaces
    write_pkgbuild(File.join(@packages_root, 'local', 'local-pkg', 'PKGBUILD'), 'local-pkg')
    write_pkgbuild(File.join(@packages_root, 'upstream', 'upstream-pkg', 'PKGBUILD'), 'upstream-pkg')
    write_pkgbuild(File.join(@packages_root, 'legacy-pkg', 'PKGBUILD'), 'legacy-pkg')

    paths = Rulepack::PackageResolver.all_pkgbuilds(namespaces: :all)
    names = paths.map { |p| p.dirname.basename.to_s }

    assert_includes names, 'local-pkg'
    assert_includes names, 'upstream-pkg'
    assert_includes names, 'legacy-pkg'
    assert_equal 3, names.size
  end

  def test_all_pkgbuilds_tracked_excludes_local
    write_pkgbuild(File.join(@packages_root, 'local', 'local-pkg', 'PKGBUILD'), 'local-pkg')
    write_pkgbuild(File.join(@packages_root, 'upstream', 'upstream-pkg', 'PKGBUILD'), 'upstream-pkg')
    write_pkgbuild(File.join(@packages_root, 'legacy-pkg', 'PKGBUILD'), 'legacy-pkg')

    paths = Rulepack::PackageResolver.all_pkgbuilds(namespaces: :tracked)
    names = paths.map { |p| p.dirname.basename.to_s }

    refute_includes names, 'local-pkg'
    assert_includes names, 'upstream-pkg'
    assert_includes names, 'legacy-pkg'
  end

  def test_all_pkgbuilds_resolves_duplicates_by_precedence
    write_pkgbuild(File.join(@packages_root, 'local', 'shared', 'PKGBUILD'), 'shared')
    write_pkgbuild(File.join(@packages_root, 'upstream', 'shared', 'PKGBUILD'), 'shared')
    write_pkgbuild(File.join(@packages_root, 'shared', 'PKGBUILD'), 'shared')

    paths = Rulepack::PackageResolver.all_pkgbuilds(namespaces: :all)
    assert_equal 1, paths.size
    assert_equal Pathname.new('local'), paths.first.dirname.dirname.basename
  end

  def test_namespace_for
    local_path = Pathname.new(@packages_root).join('local', 'pkg', 'PKGBUILD')
    upstream_path = Pathname.new(@packages_root).join('upstream', 'pkg', 'PKGBUILD')
    legacy_path = Pathname.new(@packages_root).join('pkg', 'PKGBUILD')

    assert_equal 'local', Rulepack::PackageResolver.namespace_for(local_path)
    assert_equal 'upstream', Rulepack::PackageResolver.namespace_for(upstream_path)
    assert_equal 'core', Rulepack::PackageResolver.namespace_for(legacy_path)
  end

  def test_each_pkgbuild_yields_namespace
    write_pkgbuild(File.join(@packages_root, 'local', 'local-pkg', 'PKGBUILD'), 'local-pkg')
    write_pkgbuild(File.join(@packages_root, 'legacy-pkg', 'PKGBUILD'), 'legacy-pkg')

    pairs = Rulepack::PackageResolver.each_pkgbuild(namespaces: :all).to_a
    namespaces = pairs.map(&:last)

    assert_includes namespaces, 'local'
    assert_includes namespaces, 'core'
  end
end
