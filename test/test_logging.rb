# frozen_string_literal: true

# Console silencing for machine-readable output. The CLI runner flips this
# flag for --format json|yaml|jsonl so legacy Logging narration never breaks
# the structured stdout stream; the log file must still receive every line.

require_relative 'helper'
require 'fileutils'

class TestLogging < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-logging-test-')
    @log_file = File.join(@tmpdir, 'test.log')
    @original_file = Rulepack::Logging.log_file
  end

  def teardown
    Rulepack::Logging.console_silent = false
    Rulepack::Logging.log_file = @original_file
    FileUtils.rm_rf(@tmpdir)
  end

  def test_console_silent_defaults_to_off
    refute Rulepack::Logging.console_silent
  end

  def test_log_prints_to_console_and_file_by_default
    Rulepack::Logging.log_file = @log_file
    out, err = capture_io do
      Rulepack::Logging.log 'hello'
      Rulepack::Logging.log_warn 'careful'
      Rulepack::Logging.log_error 'boom'
    end
    assert_includes out, 'hello'
    assert_includes err, 'careful'
    assert_includes err, 'boom'
    assert_includes File.read(@log_file), 'hello'
  end

  def test_console_silent_keeps_the_log_file_and_stderr_but_drops_stdout
    Rulepack::Logging.log_file = @log_file
    Rulepack::Logging.console_silent = true
    out, err = capture_io do
      Rulepack::Logging.log 'hello'
      Rulepack::Logging.log_warn 'careful'
      Rulepack::Logging.log_error 'boom'
    end
    # stdout must stay parseable for machine formats; stderr diagnostics and
    # the log file remain the observability surfaces.
    assert_empty out
    assert_includes err, 'careful'
    assert_includes err, 'boom'
    contents = File.read(@log_file)
    assert_includes contents, 'hello'
    assert_includes contents, 'WARN: careful'
    assert_includes contents, 'ERROR: boom'
  end
end
