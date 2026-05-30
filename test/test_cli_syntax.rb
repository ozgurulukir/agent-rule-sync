# frozen_string_literal: true

require_relative 'helper'
require 'stringio'
require 'json'

class TestCliSyntax < Minitest::Test
   def setup
     @original_argv = ARGV.dup
     ENV['RULEPACK_TEST'] = '1'

     # ── data/index.yaml (package database) ─────────────────────────────────────────
     @index_path = Rulepack::Common.index_yaml_path
     @created_dummy_index = false
     unless @index_path.exist?
       @index_path.dirname.mkpath
       File.write(@index_path, "---\nversion: 3.0\npackages: {}\n")
       @created_dummy_index = true
     end

     # ── build/index.yaml (build index) ───────────────────────────────────────────
     # fix.rb / install.rb / verify.rb / uninstall.rb all check BUILD_INDEX_PATH
     # before processing any command.  Without this file the scripts exit early
     # with "Build index not found" — poisoning every CLI-syntax test that calls
     # those scripts via capture_script_run.
     @build_index_path = Rulepack::Common::BUILD_INDEX_PATH
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

  # Helper to capture exit code and standard out/err of a load command
  def capture_script_run(script_name, new_argv)
    ARGV.replace(new_argv)
    
    script_path = File.expand_path("../../lib/rulepack/#{script_name}.rb", __FILE__)
    
    out_io = StringIO.new
    err_io = StringIO.new
    
    # Temporarily redirect stdout and stderr
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = out_io
    $stderr = err_io
    
    exit_code = 0
    begin
      # Use load instead of require so it executes every time
      load script_path
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

  def test_install_pacman_flag_shift
    # Shift -S flag should work and parse exactly the same
    res = capture_script_run('install', ['-S', 'nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Package 'nonexistentpkg' not found in build index/, res[:stderr])
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

  def test_uninstall_pacman_flag_shift
    res = capture_script_run('uninstall', ['-R', 'nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Package 'nonexistentpkg' is not registered as installed/, res[:stderr])
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

  def test_verify_pacman_flag_shift
    res = capture_script_run('verify', ['-Qk', 'nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Package 'nonexistentpkg' is not registered as installed/, res[:stderr])
  end

  # ─── Fix CLI Tests ────────────────────────────────────────────────────────────

  def test_fix_without_target_fails
    res = capture_script_run('fix', [])
    assert_equal 1, res[:exit_code]
    assert_match(/Build index not found/, res[:stderr])
  end

  def test_fix_invalid_package_fails
    res = capture_script_run('fix', ['nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Build index not found/, res[:stderr])
  end

  def test_fix_project_platform_without_project_path_fails
    res = capture_script_run('fix', ['--target', 'cursor'])
    assert_equal 1, res[:exit_code]
    assert_match(/Build index not found/, res[:stderr])
  end

  def test_fix_pacman_flag_shift
    res = capture_script_run('fix', ['-F', 'nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Build index not found/, res[:stderr])
  end

  # ─── Audit CLI Tests ──────────────────────────────────────────────────────────
  # Audit is a proper Ruby module (not a standalone script), so we call it directly.

  def capture_audit_run(argv)
    require_relative '../lib/rulepack/audit'

    out_io = StringIO.new
    err_io = StringIO.new
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = out_io
    $stderr = err_io

    exit_code = 0
    begin
      exit_code = Rulepack::Audit.run(argv)
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
    expected_count = Dir.glob(File.join(__dir__, '..', 'data', 'packages', '*', 'PKGBUILD')).size
    assert_equal expected_count, data['packages'].size,
      "Expected #{expected_count} packages (matching data/packages/*/PKGBUILD) but got #{data['packages'].size}"
  end

  def test_audit_unknown_target_exits
    res = capture_audit_run(['--target', 'nonexistent-platform'])
    assert_equal 1, res[:exit_code]
  end
end

