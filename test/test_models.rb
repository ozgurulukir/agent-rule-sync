# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')

require 'minitest/autorun'
require 'rulepack'

class TestPackageModel < Minitest::Test
  def test_constructs_from_hash
    pkg = Rulepack::Package.from_hash(
      pkgname: 'memory', pkgver: '1.0.0', pkg_type: 'rule',
      source: [{ type: 'local', path: 'src/memory.md' }]
    )
    assert_equal 'memory', pkg.pkgname
    assert_equal '1.0.0', pkg.pkgver
    assert_equal 1, pkg.pkgrel
    assert_equal 0, pkg.epoch
    assert pkg.rule?
    refute pkg.skill?
    refute pkg.agent?
  end

  def test_predicates
    rule = Rulepack::Package.from_hash(pkgname: 'r', pkgver: '1', pkg_type: 'rule', source: [])
    skill = Rulepack::Package.from_hash(pkgname: 's', pkgver: '1', pkg_type: 'skill', source: [])
    bundle = Rulepack::Package.from_hash(pkgname: 'b', pkgver: '1', pkg_type: 'skill-bundle', source: [])
    agent = Rulepack::Package.from_hash(pkgname: 'a', pkgver: '1', pkg_type: 'agent', source: [])
    hybrid = Rulepack::Package.from_hash(pkgname: 'h', pkgver: '1', pkg_type: 'hybrid', source: [])

    assert rule.rule?
    assert skill.skill?
    assert bundle.skill_bundle?
    assert agent.agent?
    assert hybrid.hybrid?
  end

  def test_source_is_dir
    dir_pkg = Rulepack::Package.from_hash(
      pkgname: 'd', pkgver: '1', pkg_type: 'skill-bundle',
      source: [{ type: 'local', path: 'skills/' }]
    )
    file_pkg = Rulepack::Package.from_hash(
      pkgname: 'f', pkgver: '1', pkg_type: 'rule',
      source: [{ type: 'local', path: 'src/rule.md' }]
    )
    assert dir_pkg.source_is_dir?
    refute file_pkg.source_is_dir?
  end

  def test_source_basename
    pkg = Rulepack::Package.from_hash(
      pkgname: 'm', pkgver: '1', pkg_type: 'rule',
      source: [{ type: 'local', path: 'src/memory.md' }]
    )
    assert_equal 'memory.md', pkg.source_basename
  end

  def test_to_h_roundtrip
    original = {
      pkgname: 'test-pkg', pkgver: '2.0.0', pkgrel: 2, epoch: 1,
      pkgdesc: 'A test', pkg_type: 'rule', order: 10, arch: 'any',
      source: [{ type: 'local', path: 'src/test.md' }],
      targets: [{ platform: 'opencode', format: 'directory', output: 'test.md' }],
      dependencies: ['other'], tags: ['test']
    }
    pkg = Rulepack::Package.from_hash(original)
    round = pkg.to_h
    assert_equal 'test-pkg', round[:pkgname]
    assert_equal '2.0.0', round[:pkgver]
    assert_equal 2, round[:pkgrel]
    assert_equal ['other'], round[:dependencies]
    assert_equal ['test'], round[:tags]
  end

  def test_frozen
    pkg = Rulepack::Package.from_hash(pkgname: 'm', pkgver: '1', pkg_type: 'rule', source: [])
    assert_raises(FrozenError) { pkg.instance_variable_set(:@x, 1) }
  end
end

class TestPlatformModel < Minitest::Test
  def test_constructs_from_hash
    plat = Rulepack::Platform.from_hash('opencode', {
      type: 'opencode', base_path: '~/.config/opencode',
      rules_dir: 'rules/', scope: 'user'
    })
    assert_equal 'opencode', plat.id
    assert_equal 'opencode', plat.type
    assert plat.user_scoped?
    refute plat.project_scoped?
  end

  def test_to_h_compact
    plat = Rulepack::Platform.from_hash('cursor', {
      type: 'cursor', base_path: '.cursor', scope: 'project',
      rules_dir: 'rules/'
    })
    h = plat.to_h
    assert_equal 'cursor', h[:type]
    assert_equal 'project', h[:scope]
    assert_equal 'rules/', h[:rules_dir]
  end
end

class TestTargetModel < Minitest::Test
  def test_constructs_from_hash
    tgt = Rulepack::Target.from_hash(
      platform: 'opencode', format: 'directory', output: '00-memory.md',
      install: { type: 'symlink' }
    )
    assert_equal 'opencode', tgt.platform
    assert_equal 'directory', tgt.format
    assert tgt.directory?
    refute tgt.skill_bundle?
  end

  def test_predicates
    sb = Rulepack::Target.from_hash(platform: 'c', format: 'skill-bundle', output: '.')
    ag = Rulepack::Target.from_hash(platform: 'c', format: 'agent', output: '.')
    di = Rulepack::Target.from_hash(platform: 'c', format: 'directory', output: 'r.md')
    im = Rulepack::Target.from_hash(platform: 'c', format: 'import', output: 'r.md')
    sk = Rulepack::Target.from_hash(platform: 'c', format: 'skill', output: 's.md')

    assert sb.skill_bundle?
    assert ag.agent?
    assert di.directory?
    assert im.import?
    assert sk.skill_format?
  end

  def test_to_h_omits_nils
    tgt = Rulepack::Target.from_hash(platform: 'o', format: 'directory', output: 'r.md')
    h = tgt.to_h
    assert_equal 'o', h[:platform]
    refute h.key?(:install), 'should omit nil install'
    refute h.key?(:transformer), 'should omit nil transformer'
  end

  def test_frozen
    tgt = Rulepack::Target.from_hash(platform: 'o', format: 'directory', output: 'r.md')
    assert_raises(FrozenError) { tgt.instance_variable_set(:@x, 1) }
  end
end
