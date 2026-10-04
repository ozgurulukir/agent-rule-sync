# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')

require 'minitest/autorun'
require 'rulepack'
require_relative '../lib/rulepack/file_backups'

# FileBackups is the one backup implementation; these tests pin the scoped
# Paths anchoring (P-AR d — backups for a relocated scope stay inside that
# scope) and the choreography both index stores delegate to.
class TestFileBackups < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-file-backups-test-')
    @root = Pathname.new(@tmpdir)
    @paths = Rulepack::Paths.for_root(@root)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def in_sandbox
    Rulepack::Common.with_paths(@paths) { yield }
  end

  def test_backup_file_anchors_at_scoped_paths_root
    file = @root.join('note.md')
    file.write('hello')

    backup = in_sandbox { Rulepack::Common.backup_file(file) }

    refute_nil backup
    assert backup.exist?
    assert_equal 'hello', backup.read
    assert_equal @root.join('data', 'backups', "session-#{$$}"), backup.parent
  end

  def test_backup_file_copies_directories_recursively
    dir = @root.join('bundle')
    dir.mkpath
    dir.join('inner.md').write('deep')

    backup = in_sandbox { Rulepack::Common.backup_file(dir) }

    refute_nil backup
    assert_equal 'deep', backup.join('inner.md').read
  end

  def test_backup_file_returns_nil_for_missing_path
    assert_nil in_sandbox { Rulepack::Common.backup_file(@root.join('nope.md')) }
  end

  def test_numbered_backup_restore_roundtrip
    index = @root.join('data', 'index.yaml')
    index.parent.mkpath
    index.write('v1')

    backup = in_sandbox { Rulepack::FileBackups.numbered_backup(index, index.parent) }
    index.write('v2')
    assert in_sandbox { Rulepack::FileBackups.restore(backup, index) }

    assert_equal 'v1', index.read
  end

  def test_numbered_backup_returns_nil_when_nothing_to_back_up
    assert_nil in_sandbox { Rulepack::FileBackups.numbered_backup(@root.join('nope.yaml'), @root) }
  end

  def test_restore_returns_false_for_missing_backup
    refute in_sandbox { Rulepack::FileBackups.restore(@root.join('nope.bak'), @root.join('index.yaml')) }
  end

  def test_cleanup_removes_only_matching_backups
    keep = @root.join('keep.txt')
    keep.write('keep me')
    stale = @root.join('index.yaml.bak.1')
    stale.write('stale')

    in_sandbox { Rulepack::FileBackups.cleanup(@root.join('index.yaml.bak.*'), label: 'index') }

    refute stale.exist?
    assert keep.exist?
  end

  def test_cleanup_dead_sessions_removes_dead_pid_dirs_only
    dead = @root.join('data', 'backups', 'session-999999999')
    dead.mkpath
    dead.join('1-file.md').write('x')
    live = @root.join('data', 'backups', "session-#{$$}")
    live.mkpath
    live.join('1-file.md').write('x')

    in_sandbox { Rulepack::FileBackups.cleanup_dead_sessions }

    refute dead.exist?, 'backup dir of a dead pid should be removed'
    assert live.exist?, 'backup dir of this live process should be kept'
  end
end
