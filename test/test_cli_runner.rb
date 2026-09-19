# frozen_string_literal: true

# First direct test suite for CLI::Runner — the real spine, driven in-process
# against with_paths sandboxes. Migrates the CLI error-path pins that
# test_cli_syntax.rb used to assert through an inline re-implementation of
# the runner (the duplication this suite replaces).

require_relative 'helper'
require 'stringio'
require 'json'
require 'fileutils'
require 'rulepack/cli/runner'
require 'rulepack/cli/help'
require 'rulepack/cli_parser'
require 'rulepack/query'
require 'rulepack/build'
require 'rulepack/aggregate'
require 'rulepack/build_all'
require 'rulepack/installer'
require 'rulepack/uninstaller'
require 'rulepack/verify'
require 'rulepack/fix'
require 'rulepack/outdated'
require 'rulepack/bump'
require 'rulepack/status'
require 'rulepack/build_catalog'
require 'rulepack/remote'
require 'rulepack/lock'
require 'rulepack/init_hooks'

class TestCliRunner < Minitest::Test
  def setup
    # helper.rb wires a process-global ConsoleRenderer that never unsubscribes;
    # the runner wires its own per invocation. Clear both sides so narration
    # is captured exactly once per run, and restore the global in teardown.
    Rulepack::Emitter.clear!
    @tmpdir = Dir.mktmpdir('rulepack-cli-runner-test-')
    @root = Pathname.new(@tmpdir)
    @paths = Rulepack::Paths.for_root(@root)
  end

  def teardown
    Rulepack::Emitter.clear!
    Rulepack::Reporter::ConsoleRenderer.new
    FileUtils.rm_rf(@tmpdir)
  end

  def run_cli(*argv)
    code = nil
    out, err = capture_io do
      code = Rulepack::Common.with_paths(@paths) { Rulepack::CLI::Runner.run(argv.flatten) }
    end
    [code, out, err]
  end

  def write_sandbox_indexes
    @root.join('data').mkpath
    @root.join('build').mkpath
    (@paths.index_yaml_path).write({ version: 3.0, packages: {} }.to_yaml)
    (@paths.build_index_path).write({ version: 3.0, packages: {} }.to_yaml)
  end

  # ─── Help ─────────────────────────────────────────────────────────────────────

  def test_help_exits_zero_and_lists_every_valid_command
    code, out, = run_cli('help')
    assert_equal 0, code
    Rulepack::CLI::COMMANDS.each_key do |command|
      assert_includes out, command, "help must list #{command}"
    end
    assert_includes out, 'Pacman-style commands:'
    assert_includes out, 'Makepkg-style commands:'
    assert_includes out, 'Other commands:'
  end

  # ─── Unknown command ──────────────────────────────────────────────────────────

  def test_unknown_command_fails_with_did_you_mean
    code, out, err = run_cli('instal')
    assert_equal 1, code
    assert_includes err, "Unknown command: 'instal'"
    assert_includes err, 'Did you mean? rulepack install'
    assert_includes err, 'rulepack help'
  end

  # ─── Positional boundary guard ────────────────────────────────────────────────

  def test_max_positional_is_enforced_by_the_table
    code, out, err = run_cli('build', 'extra-arg')
    assert_equal 1, code
    assert_match(/Too many positional arguments\. Usage: rulepack build/, err)
  end

  # ─── Renderer lifecycle ───────────────────────────────────────────────────────

  def test_consecutive_runs_do_not_stack_renderers
    write_sandbox_indexes
    _, out1, = run_cli('status')
    _, out2, = run_cli('status')
    assert_equal out1, out2, 'second run must not repeat narration from the first run'
  end

  # ─── Formats ──────────────────────────────────────────────────────────────────

  def test_json_format_emits_the_result_envelope
    write_sandbox_indexes
    code, out, = run_cli('status', '--format', 'json')
    assert_equal 0, code
    data = JSON.parse(out)
    assert_equal %w[data errors messages status], data.keys.sort
    assert_equal 'success', data['status']
  end

  def test_jsonl_stream_ends_with_a_result_event
    write_sandbox_indexes
    code, out, = run_cli('status', '--format', 'jsonl')
    assert_equal 0, code
    last = JSON.parse(out.lines.last)
    assert_equal 'result', last['event']
    assert_equal 'success', last['payload']['status']
  end

  # ─── status ───────────────────────────────────────────────────────────────────

  def test_status_without_index_prints_hint_and_exits_zero
    code, out, = run_cli('status')
    assert_equal 0, code
    assert_includes out, 'No index found. Run `rulepack build` first.'
  end

  def test_status_renders_the_installed_index_summary
    write_sandbox_indexes
    index = {
      version: 3.0,
      packages: {
        memory: { pkgname: 'memory', installed: [{ platform: 'opencode' }] },
        shell: { pkgname: 'shell', installed: [{ platform: 'crush' }] }
      }
    }
    @paths.index_yaml_path.write(index.to_yaml)

    code, out, = run_cli('status')
    assert_equal 0, code
    assert_includes out, '📦 Rulepack Status'
    assert_includes out, '  Total packages: 2'
    assert_includes out, '  Platforms: 2'
    assert_includes out, '  opencode: 1 package(s)'
    assert_includes out, '    - memory'
  end

  # ─── catalog ──────────────────────────────────────────────────────────────────

  def test_catalog_emits_the_artifact_bytes
    write_sandbox_indexes
    catalog = "{\n  \"version\": \"1.0\"\n}\n"
    @root.join('build', 'catalog.json').write(catalog)

    code, out, = run_cli('catalog')
    assert_equal 0, code
    assert_equal catalog, out
  end

  def test_catalog_without_build_fails
    code, out, err = run_cli('catalog')
    assert_equal 1, code
    assert_includes err, 'Error: Catalog not found. Run `rulepack build` first.'
  end

  # ─── lock (Dir.pwd-anchored by design) ────────────────────────────────────────

  def test_lock_reports_missing_lockfile_without_the_dead_add_hint
    Dir.chdir(@root) do
      code, out, = run_cli('lock')
      assert_equal 0, code
      assert_includes out, 'No lockfile entries.'
      refute_includes out, '--add', 'the advertised --add/--version flags never existed'
    end
  end

  # ─── init-hooks (Paths-scoped since the backend extraction) ───────────────────

  def test_init_hooks_installs_the_hook_inside_the_scoped_root
    @root.join('.git', 'hooks').mkpath
    code, out, = run_cli('init-hooks')
    assert_equal 0, code
    hook = @root.join('.git', 'hooks', 'pre-commit')
    assert hook.exist?, 'the hook must land in the scoped root, not the repo'
    assert_includes hook.read, 'rulepack audit --strict'
    assert_includes out, 'Git pre-commit hook installed successfully'
  end

  def test_init_hooks_fails_outside_a_git_repository
    code, out, err = run_cli('init-hooks')
    assert_equal 1, code
    assert_includes err, 'Not a git repository'
  end

  # ─── verify / fix early returns (crash/mis-render regression) ─────────────────

  def test_verify_with_no_installed_packages_prints_no_spurious_platforms_line
    write_sandbox_indexes
    code, out, = run_cli('verify', '--target', 'opencode')
    assert_equal 0, code
    refute_includes out, 'Platforms (0)', 'the old sniffing ladder misrendered verify/fix shapes'
  end

  # ─── Pacman alias ─────────────────────────────────────────────────────────────

  def test_pacman_alias_q_dispatches_query
    code, out, = run_cli('-Q', 'help')
    assert_equal 0, code
    assert_includes out, 'Rulepack Database Query Tool'
  end

  # ─── Migrated error-path pins (verbatim strings from test_cli_syntax) ─────────

  def test_install_without_target_fails
    write_sandbox_indexes
    code, out, err = run_cli('install')
    assert_equal 1, code
    assert_match(/Please specify target platform\(s\)/, err)
  end

  def test_install_invalid_package_fails
    write_sandbox_indexes
    code, out, err = run_cli('install', 'nonexistentpkg', '--target', 'opencode')
    assert_equal 1, code
    assert_match(/Package 'nonexistentpkg' not found in build index/, err)
  end

  def test_install_project_platform_without_project_path_fails
    write_sandbox_indexes
    code, out, err = run_cli('install', '--target', 'cursor')
    assert_equal 1, code
    assert_match(/is project-scoped\. You must explicitly specify the project path/, err)
  end

  def test_uninstall_without_target_fails
    write_sandbox_indexes
    code, out, err = run_cli('uninstall')
    assert_equal 1, code
    assert_match(/Please specify target platform\(s\)/, err)
  end

  def test_uninstall_invalid_package_fails
    write_sandbox_indexes
    code, out, err = run_cli('uninstall', 'nonexistentpkg', '--target', 'opencode')
    assert_equal 1, code
    assert_match(/Package 'nonexistentpkg' is not registered as installed/, err)
  end

  def test_uninstall_project_platform_without_project_path_fails
    write_sandbox_indexes
    code, out, err = run_cli('uninstall', '--target', 'cursor')
    assert_equal 1, code
    assert_match(/is project-scoped\. You must explicitly specify the project path/, err)
  end

  def test_verify_without_target_fails
    write_sandbox_indexes
    code, out, err = run_cli('verify')
    assert_equal 1, code
    assert_match(/Please specify target platform\(s\)/, err)
  end

  def test_verify_project_platform_without_project_path_fails
    write_sandbox_indexes
    code, out, err = run_cli('verify', '--target', 'cursor')
    assert_equal 1, code
    assert_match(/is project-scoped\. You must explicitly specify the project path/, err)
  end

  def test_fix_without_target_fails
    write_sandbox_indexes
    code, out, err = run_cli('fix')
    assert_equal 1, code
    assert_match(/specify target platform/i, err)
  end

  def test_fix_invalid_package_fails
    write_sandbox_indexes
    code, out, err = run_cli('fix', 'nonexistentpkg', '--target', 'opencode')
    assert_equal 1, code
    assert_match(/not registered as installed/, err)
  end
end
