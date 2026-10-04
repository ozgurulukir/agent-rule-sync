# frozen_string_literal: true

require_relative 'helper'
require 'rulepack/installer'

class TestTransactionRollback < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-rollback-test-')
    @base = Pathname.new(@tmpdir)
    @built_path = @base.join('built_file.txt')
    @built_path.write("built-content\n")
    @install_path = @base.join('installed_file.txt')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_journal_creation_and_rollback_file
    ctx = Rulepack::Install::InstallContext.new(
      dry_run: false,
      journal: []
    )

    # Simulated install of a new file
    Rulepack::Transaction.record_journal(ctx, { action: :create_file, path: @install_path })
    @install_path.write("installed-content\n")
    assert @install_path.exist?

    # Verify rollback deletes the created file
    Rulepack::Transaction.rollback_journal(ctx.journal)
    refute @install_path.exist?
  end

  def test_journal_creation_and_rollback_dir
    ctx = Rulepack::Install::InstallContext.new(
      dry_run: false,
      journal: []
    )

    # Simulated install of a new directory
    install_dir = @base.join('installed_dir')
    Rulepack::Transaction.record_journal(ctx, { action: :create_dir, path: install_dir })
    install_dir.mkpath
    assert install_dir.exist?

    # Verify rollback deletes the created directory
    Rulepack::Transaction.rollback_journal(ctx.journal)
    refute install_dir.exist?
  end

  def test_journal_replace_file_rollback
    ctx = Rulepack::Install::InstallContext.new(
      dry_run: false,
      journal: []
    )

    # Place an existing file
    @install_path.write("original-content\n")

    # Perform replace simulation
    backup_path = Rulepack::Common.backup_file(@install_path)
    Rulepack::Transaction.record_journal(ctx, { action: :replace_file, path: @install_path, backup: backup_path })
    @install_path.write("replaced-content\n")

    assert_equal "replaced-content\n", @install_path.read

    # Rollback should restore original content
    Rulepack::Transaction.rollback_journal(ctx.journal)
    assert @install_path.exist?
    assert_equal "original-content\n", @install_path.read
  end

  def test_journal_modify_file_rollback
    ctx = Rulepack::Install::InstallContext.new(
      dry_run: false,
      journal: []
    )

    # Place an existing file
    @install_path.write("original-content\n")

    # Perform modification simulation (e.g. append)
    backup_path = Rulepack::Common.backup_file(@install_path)
    Rulepack::Transaction.record_journal(ctx, { action: :modify_file, path: @install_path, backup: backup_path })
    @install_path.write("original-content\nappended-content\n")

    assert_equal "original-content\nappended-content\n", @install_path.read

    # Rollback should restore original content
    Rulepack::Transaction.rollback_journal(ctx.journal)
    assert @install_path.exist?
    assert_equal "original-content\n", @install_path.read
  end

  def test_journal_replace_dir_rollback
    ctx = Rulepack::Install::InstallContext.new(
      dry_run: false,
      journal: []
    )

    # Place an existing directory
    install_dir = @base.join('installed_dir')
    install_dir.mkpath
    install_dir.join('file1.txt').write("original-1\n")

    # Perform replace simulation
    backup_path = Rulepack::Common.backup_file(install_dir)
    Rulepack::Transaction.record_journal(ctx, { action: :replace_dir, path: install_dir, backup: backup_path })
    FileUtils.rm_rf(install_dir)
    install_dir.mkpath
    install_dir.join('file1.txt').write("replaced-1\n")

    assert_equal "replaced-1\n", install_dir.join('file1.txt').read

    # Rollback should restore original directory and its files
    Rulepack::Transaction.rollback_journal(ctx.journal)
    assert install_dir.exist?
    assert_equal "original-1\n", install_dir.join('file1.txt').read
  end

  def test_check_prerequisites_version_matching
    # Let's mock the tool version parsing by defining prerequisites
    # and ensuring check_prerequisites executes and correctly verifies ruby version.
    # Ruby version is guaranteed to be present and match '>=2.0'
    fake_cfg = {
      prerequisites: {
        tools: ['ruby'],
        versions: { ruby: '>=2.0' }
      }
    }

    # We expect ruby to be found and no warnings printed because version requirement is met
    missing = Rulepack::Common.check_prerequisites(fake_cfg)
    assert_empty missing
  end

  def test_check_prerequisites_version_mismatch
    # Mismatch operator version check (ruby version is not >= 999.0)
    fake_cfg = {
      prerequisites: {
        tools: ['ruby'],
        versions: { ruby: '>=999.0' }
      }
    }

    # Should print warning (captured in test logs) but not add to missing tools list (informational only)
    missing = Rulepack::Common.check_prerequisites(fake_cfg)
    assert_empty missing
  end

  # ─── Restore-outcome return (surfaced in install Result data) ────────────────

  def test_rollback_without_backup_reports_not_restored
    outcome = Rulepack::Transaction.transaction_rollback(StandardError.new('boom'), nil, nil)
    assert_equal false, outcome[:index_restored]
    assert_nil outcome[:backup]
  end

  def test_rollback_with_backup_reports_restored
    paths = Rulepack::Paths.for_root(@base)
    Rulepack::Common.with_paths(paths) do
      @base.join('data').mkpath
      (paths.index_yaml_path).write({ version: 3.0, packages: {} }.to_yaml)
      backup_path = Rulepack::InstalledIndex.backup
      assert backup_path, 'backup must exist for the restore path'

      outcome = nil
      capture_io do
        outcome = Rulepack::Transaction.transaction_rollback(StandardError.new('boom'), backup_path, nil)
      end
      assert_equal true, outcome[:index_restored]
      assert_equal backup_path.to_s, outcome[:backup]
    end
  end
end
