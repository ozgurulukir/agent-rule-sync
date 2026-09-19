# frozen_string_literal: true

# Backend-level audit tests, migrated verbatim from test_cli_syntax.rb —
# they exercise Audit.run + the Reporter render path, not the runner.

require_relative 'helper'
require 'json'
require 'fileutils'
require 'rulepack/audit'
require 'rulepack/cli_parser'
require 'rulepack/reporter'

class TestAudit < Minitest::Test
  def capture_audit_run(argv)
    out_io = StringIO.new
    err_io = StringIO.new
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = out_io
    $stderr = err_io

    exit_code = 0
    begin
      opts = Rulepack::CliParser.parse(argv)
      result = Rulepack::Audit.run(opts)
      fmt = opts[:format] || :text
      # Render like the CLI does (text = audit report via TextRenderer.render_audit).
      Rulepack::Reporter.print(result, format: fmt, out: out_io)
      exit_code = result.failure? ? 1 : 0
    rescue SystemExit => e
      exit_code = e.status
    rescue StandardError => e
      err_io.puts(e.message)
      exit_code = 1
    ensure
      $stdout = old_stdout
      $stderr = old_stderr
    end

    { exit_code: exit_code, stdout: out_io.string, stderr: err_io.string }
  end

  def test_audit_normal_run_passes
    res = capture_audit_run([])
    assert_equal 0, res[:exit_code], "Expected exit 0 but got: #{res[:stderr]}"
    assert_match(/Rulepack PKGBUILD Audit Report/, res[:stdout])
    assert_match(/Success! All PKGBUILD files conform perfectly/, res[:stdout])
  end

  def test_audit_json_format
    res = capture_audit_run(['--format', 'json'])
    assert_equal 0, res[:exit_code], "Expected exit 0 but got: #{res[:stderr]}"
    data = JSON.parse(res[:stdout])
    assert_kind_of Hash, data
    expected_count = Dir.glob([
      File.join(__dir__, '..', 'data', 'packages', '*', 'PKGBUILD'),
      File.join(__dir__, '..', 'data', 'packages', '*', '*', 'PKGBUILD')
    ]).size
    packages = data['data']['audit']['packages']
    assert_equal expected_count, packages.size,
      "Expected #{expected_count} packages but got #{packages.size}"
  end

  def test_audit_discovers_local_namespace_packages
    local_pkg_dir = Rulepack::Common::RULEPACK_ROOT.join('data', 'packages', 'local', 'test-local-audit-pkg')
    pkgbuild_path = local_pkg_dir.join('PKGBUILD')

    local_pkg_dir.mkpath
    pkgbuild_path.write(<<~YAML)
      ---
      pkgname: test-local-audit-pkg
      pkgver: '0.0.1'
      pkgrel: 1
      epoch: 0
      pkgdesc: Test local namespace package
      arch: any
      pkg_type: rule
      source:
      - type: local
        path: test-local-audit-pkg.md
    YAML
    local_pkg_dir.join('test-local-audit-pkg.md').write("# test\n")

    res = capture_audit_run(['--format', 'json'])
    FileUtils.rm_rf(local_pkg_dir)

    assert_equal 0, res[:exit_code], "Expected exit 0 but got: #{res[:stderr]}"
    data = JSON.parse(res[:stdout])
    packages = data['data']['audit']['packages']
    names = packages.map { |p| p['name'] }
    assert_includes names, 'test-local-audit-pkg'
    local_pkg = packages.find { |p| p['name'] == 'test-local-audit-pkg' }
    assert_equal 'local', local_pkg['namespace']
  ensure
    FileUtils.rm_rf(local_pkg_dir) if local_pkg_dir
  end

  def test_audit_unknown_target_exits
    res = capture_audit_run(['--target', 'nonexistent-platform'])
    assert_equal 1, res[:exit_code]
  end
end
