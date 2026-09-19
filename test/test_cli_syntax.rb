# frozen_string_literal: true

require_relative 'helper'
require 'stringio'
require 'json'
require 'fileutils'
require 'rulepack/models/package'
require 'rulepack/models/platform'
require 'rulepack/models/target'
require 'rulepack/installer'
require 'rulepack/uninstaller'
require 'rulepack/verify'
require 'rulepack/fix'

class TestCliSyntax < Minitest::Test
   def setup
     @original_argv = ARGV.dup

     # ── data/index.yaml (package database) ─────────────────────────────────────────
     @index_path = Rulepack::Common.index_yaml_path
     @created_dummy_index = false
     unless @index_path.exist?
       @index_path.dirname.mkpath
       File.write(@index_path, "---\nversion: 3.0\npackages: {}\n")
       @created_dummy_index = true
     end

     # ── build/index.yaml (build index) ───────────────────────────────────────────
     # The install/uninstall/verify/fix backends all check the build index
     # before processing any command. Without this file they fail early with
     # "Build index not found" — poisoning every CLI-syntax test.
     @build_index_path = Rulepack::Common.build_index_path
     @created_dummy_build_index = false
     unless @build_index_path.exist?
       @build_index_path.dirname.mkpath
       File.write(@build_index_path, "---\nversion: 3.0\npackages: {}\n")
       @created_dummy_build_index = true
     end
   end

   def teardown
     ARGV.replace(@original_argv)
     if @created_dummy_index && @index_path.exist?
       File.delete(@index_path)
     end
     if @created_dummy_build_index && @build_index_path.exist?
       File.delete(@build_index_path)
     end
   end

  # Helper to capture exit code and standard out/err of a backend command.
  # Calls the backend module directly.
  def capture_script_run(script_name, new_argv)
    ARGV.replace(new_argv)

    out_io = StringIO.new
    err_io = StringIO.new

    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = out_io
    $stderr = err_io

    exit_code = 0
    begin
      opts = Rulepack::CliParser.parse(new_argv)

      result = case script_name
               when 'install'
                 Rulepack::Install.dispatch(opts)
               when 'uninstall'
                 Rulepack::Uninstaller.dispatch(opts)
               when 'verify'
                 Rulepack::Verify.check(opts)
               when 'fix'
                 Rulepack::Fix.run(opts)
               else
                 raise "Unknown script: #{script_name}"
               end

      exit_code = result.failure? ? 1 : 0

      # Render errors to stderr for text format (matching old runner block behavior)
      if result.failure? && (opts[:format] || :text).to_sym == :text
        result.messages.each { |m| err_io.puts(m) }
        result.errors.each { |e| err_io.puts("Error: #{e}") }
      end
    rescue SystemExit => e
      exit_code = e.status
    rescue StandardError => e
      err_io.puts(e.message)
      exit_code = 1
    ensure
      $stdout = old_stdout
      $stderr = old_stderr
    end

    {
      exit_code: exit_code,
      stdout: out_io.string,
      stderr: err_io.string
    }
  end

  # ─── Install CLI Tests ────────────────────────────────────────────────────────

  def test_install_without_target_fails
    res = capture_script_run('install', [])
    assert_equal 1, res[:exit_code]
    assert_match(/Please specify target platform\(s\)/, res[:stderr])
  end

  def test_install_invalid_package_fails
    res = capture_script_run('install', ['nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Package 'nonexistentpkg' not found in build index/, res[:stderr])
  end

  def test_install_project_platform_without_project_path_fails
    res = capture_script_run('install', ['--target', 'cursor'])
    assert_equal 1, res[:exit_code]
    assert_match(/is project-scoped. You must explicitly specify the project path/, res[:stderr])
  end

  # ─── Uninstall CLI Tests ──────────────────────────────────────────────────────

  def test_uninstall_without_target_fails
    res = capture_script_run('uninstall', [])
    assert_equal 1, res[:exit_code]
    assert_match(/Please specify target platform\(s\)/, res[:stderr])
  end

  def test_uninstall_invalid_package_fails
    res = capture_script_run('uninstall', ['nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Package 'nonexistentpkg' is not registered as installed/, res[:stderr])
  end

  def test_uninstall_project_platform_without_project_path_fails
    res = capture_script_run('uninstall', ['--target', 'cursor'])
    assert_equal 1, res[:exit_code]
    assert_match(/is project-scoped. You must explicitly specify the project path/, res[:stderr])
  end

  # ─── Verify CLI Tests ─────────────────────────────────────────────────────────

  def test_verify_without_target_fails
    res = capture_script_run('verify', [])
    assert_equal 1, res[:exit_code]
    assert_match(/Please specify target platform\(s\)/, res[:stderr])
  end

  def test_verify_invalid_package_fails
    res = capture_script_run('verify', ['nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Package 'nonexistentpkg' is not registered as installed/, res[:stderr])
  end

  def test_verify_project_platform_without_project_path_fails
    res = capture_script_run('verify', ['--target', 'cursor'])
    assert_equal 1, res[:exit_code]
    assert_match(/is project-scoped. You must explicitly specify the project path/, res[:stderr])
  end

  # ─── Fix CLI Tests ────────────────────────────────────────────────────────────

  def test_fix_without_target_fails
    res = capture_script_run('fix', [])
    assert_equal 1, res[:exit_code]
    assert_match(/build index not found|specify target platform/i, res[:stderr])
  end

  def test_fix_invalid_package_fails
    res = capture_script_run('fix', ['nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/build index not found|not registered as installed/i, res[:stderr])
  end

  def test_fix_project_platform_without_project_path_fails
    res = capture_script_run('fix', ['--target', 'cursor'])
    assert_equal 1, res[:exit_code]
    assert_match(/build index not found|project-scoped/i, res[:stderr])
  end

  # ─── Audit CLI Tests ──────────────────────────────────────────────────────────
  # Audit is a proper Ruby module (not a standalone script), so we call it directly.

  def capture_audit_run(argv)
    require_relative '../lib/rulepack/audit'
    require_relative '../lib/rulepack/cli_parser'

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

  # ─── Pacman alias remap ───────────────────────────────────────────────────────

  def test_pacman_aliases_are_remapped_in_bin_entry_point
    # Alias handling lives solely in the CLI dispatch table (cli/commands.rb);
    # CliParser and backends never see the raw flags.
    table_src = File.read(ROOT.join('lib', 'rulepack', 'cli', 'commands.rb'))
    %w[-S install -R uninstall -Qk verify -F fix -Q query].each_slice(2) do |flag, command|
      assert_includes table_src, "'#{flag}' => '#{command}'",
                      "cli/commands.rb must remap #{flag} to #{command}"
    end
  end
end

