# frozen_string_literal: true

# Logging contract after the Emitter migration: every log line is emitted as
# a :log Emitter event (level-filtered) and appended to the log file
# unconditionally. log_error/log_warn keep their stderr echo at the source
# and additionally emit structured :error/:warn events for machine formats.
# Console rendering of :log events is the renderers' job (test_reporter).

require_relative 'helper'
require 'fileutils'
require 'rulepack/emitter'

class TestLogging < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-logging-test-')
    @log_file = File.join(@tmpdir, 'test.log')
    @original_file = Rulepack::Logging.log_file
    @original_log_level_env = ENV['RULEPACK_LOG_LEVEL']
    ENV.delete('RULEPACK_LOG_LEVEL')
  end

  def teardown
    Rulepack::Logging.log_file = @original_file
    if @original_log_level_env.nil?
      ENV.delete('RULEPACK_LOG_LEVEL')
    else
      ENV['RULEPACK_LOG_LEVEL'] = @original_log_level_env
    end
    FileUtils.rm_rf(@tmpdir)
  end

  def collect_log_events
    events = []
    sub = Rulepack::Emitter.subscribe(:log) { |payload| events << payload }
    yield events
  ensure
    Rulepack::Emitter.unsubscribe(sub)
  end

  def test_log_emits_a_levelled_event_and_appends_the_file_line
    Rulepack::Logging.log_file = @log_file
    collect_log_events do |events|
      Rulepack::Logging.log 'hello'
      assert_equal 1, events.size
      assert_equal 'hello', events.first[:message]
      assert_equal 'info', events.first[:level]
      assert_match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, events.first[:time])
    end
    assert_includes File.read(@log_file), 'hello'
  end

  def test_log_file_append_is_unconditional_even_without_subscribers
    Rulepack::Logging.log_file = @log_file
    Rulepack::Logging.log 'recorded-anyway'
    assert_includes File.read(@log_file), 'recorded-anyway'
  end

  def test_warn_and_error_keep_stderr_echo_and_reach_event_and_file
    Rulepack::Logging.log_file = @log_file
    collect_log_events do |events|
      _out, err = capture_io do
        Rulepack::Logging.log_warn 'careful'
        Rulepack::Logging.log_error 'boom'
      end
      assert_includes err, 'careful'
      assert_includes err, 'boom'
      assert_equal %w[warn error], events.map { |e| e[:level] }
    end
    contents = File.read(@log_file)
    assert_includes contents, 'WARN: careful'
    assert_includes contents, 'ERROR: boom'
  end

  def test_debug_events_are_level_filtered_but_still_written_to_the_file
    Rulepack::Logging.log_file = @log_file
    collect_log_events do |events|
      capture_io do
        Rulepack::Logging.log_debug 'quiet'
      end
      assert_empty events, 'debug must not surface at the default info level'
    end
    assert_includes File.read(@log_file), 'DEBUG: quiet'
  end

  def test_log_warn_and_log_error_also_emit_structured_warn_and_error_events
    Rulepack::Logging.log_file = @log_file
    structured = []
    subs = %i[warn error].map do |type|
      Rulepack::Emitter.subscribe(type) { |payload| structured << [type, payload[:message]] }
    end
    begin
      capture_io do
        Rulepack::Logging.log_warn 'careful'
        Rulepack::Logging.log_error 'boom'
      end
    ensure
      subs.each { |sub| Rulepack::Emitter.unsubscribe(sub) }
    end
    assert_equal [[:warn, 'careful'], [:error, 'boom']], structured
  end
end
