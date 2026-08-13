# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')

require 'minitest/autorun'
require 'rulepack'

class TestEmitter < Minitest::Test
  def setup
    Rulepack::Emitter.clear!
  end

  def test_subscribe_and_emit
    received = []
    Rulepack::Emitter.subscribe(:info) { |p| received << p[:message] }
    Rulepack::Emitter.emit(:info, message: 'hello')
    assert_equal ['hello'], received
  end

  def test_multiple_subscribers
    received1 = []
    received2 = []
    Rulepack::Emitter.subscribe(:info) { |p| received1 << p[:message] }
    Rulepack::Emitter.subscribe(:info) { |p| received2 << p[:message] }
    Rulepack::Emitter.emit(:info, message: 'test')
    assert_equal ['test'], received1
    assert_equal ['test'], received2
  end

  def test_unsubscribe
    received = []
    id = Rulepack::Emitter.subscribe(:info) { |p| received << p[:message] }
    Rulepack::Emitter.emit(:info, message: 'first')
    Rulepack::Emitter.unsubscribe(id)
    Rulepack::Emitter.emit(:info, message: 'second')
    assert_equal ['first'], received
  end

  def test_no_subscribers_does_not_raise
    Rulepack::Emitter.emit(:nonexistent, foo: 'bar')
  end

  def test_subscriber_error_does_not_crash_emitter
    Rulepack::Emitter.subscribe(:info) { |_p| raise 'oops' }
    Rulepack::Emitter.emit(:info, message: 'crash test')
  end

  def test_clear_removes_all_subscribers
    received = []
    Rulepack::Emitter.subscribe(:info) { |p| received << p[:message] }
    Rulepack::Emitter.clear!
    Rulepack::Emitter.emit(:info, message: 'after clear')
    assert_empty received
  end

  def test_console_renderer_subscribes
    renderer = Rulepack::Reporter::ConsoleRenderer.new(out: StringIO.new)
    assert_operator renderer.instance_variable_get(:@subscriptions).length, :>, 0
    renderer.unsubscribe!
  end

  def test_jsonl_renderer_subscribes
    renderer = Rulepack::Reporter::JsonlRenderer.new(out: StringIO.new)
    assert_operator renderer.instance_variable_get(:@subscriptions).length, :>, 0
    renderer.unsubscribe!
  end

  def test_jsonl_renderer_output_format
    out = StringIO.new
    renderer = Rulepack::Reporter::JsonlRenderer.new(out: out)
    Rulepack::Emitter.emit(:info, message: 'test-jsonl')
    renderer.unsubscribe!
    out.rewind
    line = JSON.parse(out.read.strip)
    assert_equal 'info', line['event']
    assert_equal 'test-jsonl', line['message']
  end
end
