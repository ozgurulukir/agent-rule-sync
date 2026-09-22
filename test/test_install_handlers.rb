# frozen_string_literal: true

require_relative 'helper'
require_relative '../lib/rulepack/lib/install_handlers'
require_relative '../lib/rulepack/lib/transaction'

class TestInstallHandlers < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-handlers-test-')
    @ctx = Struct.new(:dry_run, :collision_strategy, :quiet, :journal).new(false, 'overwrite', true, [])
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    # backup_file anchors at the repo RULEPACK_ROOT (see P-AR(d)) — drop this
    # test session's backups so the repo tree stays clean.
    FileUtils.rm_rf(Rulepack::Common::RULEPACK_ROOT.join('data', 'backups', "session-#{$$}"))
  end

  def test_do_structured_inject_yaml
    install_path = Pathname.new(@tmpdir).join('config.yaml')
    platform_cfg = { rule_install: { directive: '@import', inject_key: 'imports', format: 'yaml' } }

    Rulepack::InstallHandlers.do_structured_inject(install_path, platform_cfg, 'rules.md', 'test-pkg', @ctx)

    assert install_path.exist?
    data = YAML.safe_load(install_path.read, permitted_classes: [Symbol], symbolize_names: true)
    assert_equal ['@import "rules.md"'], data[:imports]

    # Test idempotency
    Rulepack::InstallHandlers.do_structured_inject(install_path, platform_cfg, 'rules.md', 'test-pkg', @ctx)
    data = YAML.safe_load(install_path.read, permitted_classes: [Symbol], symbolize_names: true)
    assert_equal ['@import "rules.md"'], data[:imports]
  end

  def test_do_structured_inject_json
    install_path = Pathname.new(@tmpdir).join('config.json')
    platform_cfg = { rule_install: { directive: '@import', inject_key: 'imports', format: 'json' } }

    Rulepack::InstallHandlers.do_structured_inject(install_path, platform_cfg, 'rules.md', 'test-pkg', @ctx)

    assert install_path.exist?
    data = JSON.parse(install_path.read)
    assert_equal ['@import "rules.md"'], data['imports']
  end

  # ─── do_json_merge ────────────────────────────────────────────────────────────

  def test_do_json_merge_deep_merges_backs_up_and_rolls_back
    install_path = Pathname.new(@tmpdir).join('config.json')
    install_path.write(JSON.pretty_generate('nested' => { 'y' => 2 }, 'list' => [2], 'keep' => true))
    built_path = Pathname.new(@tmpdir).join('built.json')
    built_path.write(JSON.pretty_generate('a' => 1, 'nested' => { 'x' => 1 }, 'list' => [1]))
    original = install_path.read

    Rulepack::InstallHandlers.do_json_merge(built_path, install_path, 'test-pkg', @ctx)

    assert_equal(
      { 'a' => 1, 'nested' => { 'x' => 1, 'y' => 2 }, 'list' => [2, 1], 'keep' => true },
      JSON.parse(install_path.read),
      'hashes merge recursively, arrays union, built scalars win'
    )

    entry = @ctx.journal.first
    assert_equal :modify_file, entry[:action]
    assert_equal install_path, entry[:path]
    assert entry[:backup].exist?, 'the rollback backup must exist on disk'
    assert_equal original, entry[:backup].read

    Rulepack::Transaction.rollback_journal(@ctx.journal)
    assert_equal original, install_path.read, 'rollback must restore the original content'
  end

  def test_do_json_merge_creates_file_when_missing
    built_path = Pathname.new(@tmpdir).join('built.json')
    built_path.write(JSON.pretty_generate('a' => 1))
    install_path = Pathname.new(@tmpdir).join('config.json')

    Rulepack::InstallHandlers.do_json_merge(built_path, install_path, 'test-pkg', @ctx)

    assert_equal({ 'a' => 1 }, JSON.parse(install_path.read))
    assert_equal :create_file, @ctx.journal.first[:action]
    assert_nil @ctx.journal.first[:backup], 'a created file has no backup'
  end

  def test_do_json_merge_invalid_built_json_raises_state_error
    built_path = Pathname.new(@tmpdir).join('built.json')
    built_path.write('not json {')
    install_path = Pathname.new(@tmpdir).join('config.json')

    error = assert_raises(Rulepack::StateError) do
      Rulepack::InstallHandlers.do_json_merge(built_path, install_path, 'test-pkg', @ctx)
    end
    assert_match(/Failed to parse built JSON/, error.message)
    refute install_path.exist?, 'nothing may be written when the built artifact is unparseable'
  end

  def test_do_json_merge_invalid_existing_json_raises_after_backup
    install_path = Pathname.new(@tmpdir).join('config.json')
    install_path.write('not json {')
    built_path = Pathname.new(@tmpdir).join('built.json')
    built_path.write(JSON.pretty_generate('a' => 1))

    error = assert_raises(Rulepack::StateError) do
      Rulepack::InstallHandlers.do_json_merge(built_path, install_path, 'test-pkg', @ctx)
    end
    assert_match(/Failed to parse existing JSON/, error.message)

    entry = @ctx.journal.first
    assert_equal :modify_file, entry[:action]
    assert entry[:backup].exist?, 'the pre-merge backup is taken before parsing the existing file'
    assert_equal 'not json {', entry[:backup].read
  end

  # ─── do_yaml_merge ────────────────────────────────────────────────────────────

  def test_do_yaml_merge_deep_merges_with_symbol_keys_and_backs_up
    install_path = Pathname.new(@tmpdir).join('config.yaml')
    install_path.write("keep: true\nnested:\n  y: 2\nlist: [2]\n")
    built_path = Pathname.new(@tmpdir).join('built.yaml')
    built_path.write("a: 1\nnested:\n  x: 1\nlist: [1]\n")

    Rulepack::InstallHandlers.do_yaml_merge(built_path, install_path, 'test-pkg', @ctx)

    data = YAML.safe_load(install_path.read, permitted_classes: [Symbol], symbolize_names: true)
    assert_equal({ keep: true, a: 1, nested: { x: 1, y: 2 }, list: [2, 1] }, data)

    entry = @ctx.journal.first
    assert_equal :modify_file, entry[:action]
    assert entry[:backup].exist?
    assert_equal "keep: true\nnested:\n  y: 2\nlist: [2]\n", entry[:backup].read
  end

  def test_do_yaml_merge_creates_file_when_missing
    built_path = Pathname.new(@tmpdir).join('built.yaml')
    built_path.write("a: 1\n")
    install_path = Pathname.new(@tmpdir).join('config.yaml')

    Rulepack::InstallHandlers.do_yaml_merge(built_path, install_path, 'test-pkg', @ctx)

    data = YAML.safe_load(install_path.read, permitted_classes: [Symbol], symbolize_names: true)
    assert_equal({ a: 1 }, data)
    assert_equal :create_file, @ctx.journal.first[:action]
  end

  def test_do_yaml_merge_invalid_built_yaml_raises_state_error
    built_path = Pathname.new(@tmpdir).join('built.yaml')
    built_path.write("a: [unclosed\n  b: {")
    install_path = Pathname.new(@tmpdir).join('config.yaml')

    error = assert_raises(Rulepack::StateError) do
      Rulepack::InstallHandlers.do_yaml_merge(built_path, install_path, 'test-pkg', @ctx)
    end
    assert_match(/Failed to parse built YAML/, error.message)
    refute install_path.exist?
  end
end
