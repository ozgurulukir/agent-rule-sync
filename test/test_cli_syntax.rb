# frozen_string_literal: true

require_relative 'helper'
require 'stringio'

class TestCliSyntax < Minitest::Test
  def setup
    @original_argv = ARGV.dup
    ENV['RULEPACK_TEST'] = '1'
    
    # Create a dummy index.yaml if it doesn't exist
    @index_path = Rulepack::Common::INDEX_YAML_PATH
    @created_dummy_index = false
    unless @index_path.exist?
      @index_path.dirname.mkpath
      File.write(@index_path, "---\nversion: 3.0\npackages: {}\n")
      @created_dummy_index = true
    end
  end

  def teardown
    ARGV.replace(@original_argv)
    if @created_dummy_index && @index_path.exist?
      File.delete(@index_path)
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
    assert_match(/Please specify target platform\(s\)/, res[:stderr])
  end

  def test_fix_invalid_package_fails
    res = capture_script_run('fix', ['nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Package 'nonexistentpkg' is not registered as installed/, res[:stderr])
  end

  def test_fix_project_platform_without_project_path_fails
    res = capture_script_run('fix', ['--target', 'cursor'])
    assert_equal 1, res[:exit_code]
    assert_match(/is project-scoped. You must explicitly specify the project path/, res[:stderr])
  end

  def test_fix_pacman_flag_shift
    res = capture_script_run('fix', ['-F', 'nonexistentpkg', '--target', 'opencode'])
    assert_equal 1, res[:exit_code]
    assert_match(/Package 'nonexistentpkg' is not registered as installed/, res[:stderr])
  end
end
