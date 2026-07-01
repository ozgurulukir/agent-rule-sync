# frozen_string_literal: true

require_relative 'helper'
require 'yaml'
require 'fileutils'
require 'rulepack/outdated'

class TestOutdated < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-outdated-test-')
    @root = Pathname.new(@tmpdir)
    @build_dir = @root.join('build')
    @install_dir = @root.join('install')
    @build_dir.mkpath
    @install_dir.mkpath

    Rulepack::Common.build_index_path = @build_dir.join('index.yaml')
    Rulepack::Common.index_yaml_path = @install_dir.join('index.yaml')

    @build_index = {
      version: 3.0,
      packages: {
        'up-to-date': { pkgname: 'up-to-date', pkgver: '2.0.0' },
        'old-version': { pkgname: 'old-version', pkgver: '2.0.0' },
        'not-installed': { pkgname: 'not-installed', pkgver: '1.0.0' }
      }
    }
    (@build_dir / 'index.yaml').write(@build_index.to_yaml)

    @installed_index = {
      version: 3.0,
      packages: {
        'up-to-date': {
          pkgname: 'up-to-date',
          pkgver: '2.0.0',
          installed: [{ platform: 'opencode', version: '2.0.0' }]
        },
        'old-version': {
          pkgname: 'old-version',
          pkgver: '1.0.0',
          installed: [{ platform: 'opencode', version: '1.0.0' }]
        }
      }
    }
    (@install_dir / 'index.yaml').write(@installed_index.to_yaml)
  end

  def teardown
    Rulepack::Common.build_index_path = nil
    Rulepack::Common.index_yaml_path = nil
    FileUtils.rm_rf(@tmpdir)
  end

  def test_detects_outdated_package
    result = Rulepack::Outdated.run(target: 'opencode')
    assert result.partial?
    assert_equal 1, result.data[:outdated].size
    assert_equal 'old-version', result.data[:outdated].first[:pkgname]
    assert_equal '1.0.0', result.data[:outdated].first[:installed_version]
    assert_equal '2.0.0', result.data[:outdated].first[:build_version]
  end

  def test_lists_available_packages
    result = Rulepack::Outdated.run(target: 'opencode')
    assert result.partial?
    available = result.data[:available]
    assert available.any? { |a| a[:pkgname] == 'not-installed' }
    refute available.any? { |a| a[:pkgname] == 'up-to-date' }
  end

  def test_up_to_date_package_not_outdated
    result = Rulepack::Outdated.run(target: 'opencode')
    refute result.data[:outdated].any? { |o| o[:pkgname] == 'up-to-date' }
  end

  def test_returns_success_when_all_current
    # Make old-version match build
    index = Rulepack::Common.load_yaml(@install_dir / 'index.yaml')
    index[:packages][:'old-version'][:installed][0][:version] = '2.0.0'
    (@install_dir / 'index.yaml').write(index.to_yaml)

    result = Rulepack::Outdated.run(target: 'opencode')
    assert result.success?
    assert_empty result.data[:outdated]
  end

  def test_returns_failure_without_build_index
    (@build_dir / 'index.yaml').delete
    result = Rulepack::Outdated.run(target: 'opencode')
    assert result.failure?
    assert_match(/Build index not found/, result.errors.first)
  end

  def test_text_output
    out, _err = capture_io { Rulepack::Reporter.print(Rulepack::Outdated.run(target: 'opencode')) }
    assert_match(/Outdated check/, out)
    assert_match(/old-version/, out)
  end

  def test_json_output
    out, _err = capture_io { Rulepack::Reporter.print(Rulepack::Outdated.run(target: 'opencode'), format: :json) }
    data = JSON.parse(out)
    assert_equal 'partial', data['status']
    assert data['data']['outdated'].any? { |o| o['pkgname'] == 'old-version' }
  end
end
