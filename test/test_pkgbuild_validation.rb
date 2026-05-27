# frozen_string_literal: true

# Unit tests for PKGBUILD loading and validation
# Covers: load_pkgbuild, validate_pkgbuild

require_relative 'helper'

# ─── load_pkgbuild ─────────────────────────────────────────────────────────────

class TestLoadPkgbuild < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('ssot-pkgbuild-test-')
    @pkgdir = Pathname.new(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def write_pkgbuild(content)
    (@pkgdir / 'PKGBUILD').write(content)
  end

  def test_loads_valid_pkgbuild
    write_pkgbuild(<<~YAML)
      ---
      pkgname: mypackage
      pkgver: '1.0.0'
      source:
        - type: local
          path: src/file.md
      targets:
        - platform: opencode
          format: directory
          output: file.md
          transformer: copy
    YAML

    data = Rulepack::Common.load_pkgbuild(@pkgdir)
    assert_equal 'mypackage', data[:pkgname]
    assert_equal '1.0.0', data[:pkgver]
    assert_kind_of Array, data[:source]
    assert_kind_of Array, data[:targets]
  end

  def test_raises_when_pkgbuild_missing
    assert_raises(RuntimeError, /PKGBUILD not found/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_raises_when_missing_pkgname
    write_pkgbuild(<<~YAML)
      ---
      pkgver: '1.0.0'
      source:
        - type: local
          path: src/file.md
      targets: []
    YAML

    assert_raises(RuntimeError, /missing required field.*pkgname/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_raises_when_missing_pkgver
    write_pkgbuild(<<~YAML)
      ---
      pkgname: mypackage
      source:
        - type: local
          path: src/file.md
      targets: []
    YAML

    assert_raises(RuntimeError, /missing required field.*pkgver/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_raises_when_missing_source
    write_pkgbuild(<<~YAML)
      ---
      pkgname: mypackage
      pkgver: '1.0.0'
      targets: []
    YAML

    assert_raises(RuntimeError, /missing required field.*source/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_raises_when_missing_targets
    write_pkgbuild(<<~YAML)
      ---
      pkgname: mypackage
      pkgver: '1.0.0'
      source:
        - type: local
          path: src/file.md
    YAML

    result = Rulepack::Common.load_pkgbuild(@pkgdir)
    assert_nil result[:targets]
  end

  def test_raises_when_empty_source_array
    write_pkgbuild(<<~YAML)
      ---
      pkgname: mypackage
      pkgver: '1.0.0'
      source: []
      targets: []
    YAML

    assert_raises(RuntimeError, /at least one source/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_raises_when_empty_targets_array
    write_pkgbuild(<<~YAML)
      ---
      pkgname: mypackage
      pkgver: '1.0.0'
      source:
        - type: local
          path: src/file.md
      targets: []
    YAML

    assert_raises(RuntimeError, /at least one target/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_raises_when_invalid_target_format
    write_pkgbuild(<<~YAML)
      ---
      pkgname: mypackage
      pkgver: '1.0.0'
      source:
        - type: local
          path: src/file.md
      targets:
        - platform: opencode
          format: invalid-format
          output: file.md
    YAML

    assert_raises(RuntimeError, /Invalid format/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_raises_when_skill_bundle_output_not_dot
    write_pkgbuild(<<~YAML)
      ---
      pkgname: my-bundle
      pkgver: '1.0.0'
      source:
        - type: local
          path: skills/
      targets:
        - platform: opencode
          format: skill-bundle
          output: wrong-name
          transformer: copy
          install:
            type: copy
            target_dir: bundle/
    YAML

    assert_raises(RuntimeError, /skill-bundle output must be '.'/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_raises_when_skill_bundle_missing_target_dir
    write_pkgbuild(<<~YAML)
      ---
      pkgname: my-bundle
      pkgver: '1.0.0'
      source:
        - type: local
          path: skills/
      targets:
        - platform: opencode
          format: skill-bundle
          output: .
          transformer: copy
    YAML

    assert_raises(RuntimeError, /skill-bundle requires install.target_dir/) do
      Rulepack::Common.load_pkgbuild(@pkgdir)
    end
  end

  def test_skill_bundle_with_dot_output_and_target_dir_is_valid
    write_pkgbuild(<<~YAML)
      ---
      pkgname: my-bundle
      pkgver: '1.0.0'
      source:
        - type: local
          path: skills/
      targets:
        - platform: opencode
          format: skill-bundle
          output: .
          transformer: copy
          install:
            type: copy
            target_dir: my-bundle/
    YAML

    data = Rulepack::Common.load_pkgbuild(@pkgdir)
    assert_equal 'my-bundle', data[:pkgname]
    assert_equal '.', data[:targets].first[:output]
  end
end

# ─── validate_pkgbuild ─────────────────────────────────────────────────────────

class TestValidatePkgbuild < Minitest::Test
  def test_valid_minimal_package_passes
    pkg = {
      pkgname: 'valid-pkg',
      pkgver: '1.0.0',
      pkgrel: 1,
      epoch: 0,
      pkgdesc: 'A valid package',
      arch: 'any',
      order: 0,
      source: [{ type: 'local', path: 'src/file.md' }],
      targets: [{ platform: 'opencode', format: 'directory', output: 'file.md', transformer: 'copy' }]
    }
    assert Rulepack::Common.validate_pkgbuild(pkg, '/fake/dir'), 'valid package should pass validation'
  end

  def test_invalid_pkgname_uppercase
    pkg = { pkgname: 'BadPkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/Invalid pkgname/, result.to_s)
  end

  def test_invalid_pkgname_too_short
    pkg = { pkgname: '', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/Invalid pkgname/, result.to_s)
  end

  def test_empty_pkgver_fails
    pkg = { pkgname: 'mypkg', pkgver: '', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/Invalid pkgver/, result.to_s)
  end

  def test_missing_pkgdesc_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, arch: 'any', order: 0, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/Invalid pkgdesc/, result.to_s)
  end

  def test_invalid_arch_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'x86_64', order: 0, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/Invalid arch/, result.to_s)
  end

  def test_negative_epoch_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: -1, pkgdesc: 'test', arch: 'any', order: 0, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/Invalid epoch/, result.to_s)
  end

  def test_pkgrel_zero_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 0, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/Invalid pkgrel/, result.to_s)
  end

  def test_missing_source_array_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/source must be/, result.to_s)
  end

  def test_empty_source_array_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/source must be/, result.to_s)
  end

  def test_source_missing_type_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [{ path: 'src/file.md' }], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/source\[0\] missing type/, result.to_s)
  end

  def test_url_source_missing_sha256_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [{ type: 'url', url: 'https://example.com/file' }], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/valid sha256/, result.to_s)
  end

  def test_url_source_with_valid_sha256_passes
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [{ type: 'url', url: 'https://example.com/file', sha256: 'a' * 64 }], targets: [{ platform: 'opencode', format: 'directory', output: 'f.md', transformer: 'copy' }] }
    assert Rulepack::Common.validate_pkgbuild(pkg, '/fake'), 'valid url source should pass'
  end

  def test_git_source_without_url_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [{ type: 'git', path: 'src/' }], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/git type requires url/, result.to_s)
  end

  def test_unknown_source_type_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [{ type: 'ftp', url: 'ftp://example.com/file' }], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/unknown type/, result.to_s)
  end

  def test_missing_target_platform_fails
    pkg = { pkgname: 'mypkg', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [{ type: 'local', path: 'f.md' }], targets: [{ format: 'directory', output: 'f.md', transformer: 'copy' }] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/missing platform/, result.to_s)
  end

  def test_skill_bundle_without_target_dir_fails
    pkg = { pkgname: 'my-bundle', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [{ type: 'local', path: 'skills/' }], targets: [{ platform: 'opencode', format: 'skill-bundle', output: '.', transformer: 'copy' }] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/skill-bundle requires install.target_dir/, result.to_s)
  end

  def test_skill_bundle_with_non_copy_install_type_fails
    pkg = { pkgname: 'my-bundle', pkgver: '1.0.0', pkgrel: 1, epoch: 0, pkgdesc: 'test', arch: 'any', order: 0, source: [{ type: 'local', path: 'skills/' }], targets: [{ platform: 'opencode', format: 'skill-bundle', output: '.', transformer: 'copy', install: { type: 'symlink', target_dir: 'bundle/' } }] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    assert_match(/install.type must be .copy/, result.to_s)
  end

  def test_multiple_errors_reported
    pkg = { pkgname: '', pkgver: '', pkgrel: 0, epoch: -1, pkgdesc: '', arch: 'x86_64', order: -1, source: [], targets: [] }
    result = Rulepack::Common.validate_pkgbuild(pkg, '/fake')
    refute_equal true, result
    # At least the first few errors should be present
    result_str = result.to_s
    assert_match(/Invalid pkgname/, result_str)
    assert_match(/Invalid pkgver/, result_str)
  end
end
