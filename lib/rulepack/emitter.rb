# frozen_string_literal: true

# Lightweight event emitter for Rulepack operations.
#
# Supports multiple subscribers. Each subscriber receives (event_type, payload).
# Events are fire-and-forget: subscribers must not raise.
#
# Usage:
#   Rulepack::Emitter.emit(:log, message: 'fetching', level: 'info', time: '...')
#   Rulepack::Emitter.subscribe(:log) { |payload| ... }
#
# Built-in event types (the vocabulary renderers and the jsonl stream carry):
#   :log           — a narration line from Common.log* (payload: {message:, level:, time:})
#   :warn          — a warning (payload: {message:}) — emitted by Logging.log_warn
#   :error         — an error (payload: {message:}) — emitted by Logging.log_error
#   :info          — informational message (payload: {message:})
#   :progress      — progress indicator (payload: {message:})
#   :result        — the final Result snapshot of a --format jsonl run (payload: {payload:})
# Custom event types may be emitted freely; renderers simply ignore unknown ones.
module Rulepack
  module Emitter
    @subscribers = {}.tap { |h| h.compare_by_identity }
    @mutex = Mutex.new

    module_function

    # Subscribe to an event type. Returns a subscription ID for unsubscribe.
    def subscribe(event_type, &block)
      @mutex.synchronize do
        @subscribers[event_type] ||= []
        @subscribers[event_type] << block
        block.object_id
      end
    end

    # Unsubscribe by subscription ID.
    def unsubscribe(sub_id)
      @mutex.synchronize do
        @subscribers.each_value { |list| list.reject! { |b| b.object_id == sub_id } }
      end
    end

    # Emit an event to all subscribers of that type.
    def emit(event_type, payload = {})
      @mutex.synchronize do
        subs = @subscribers[event_type]
        return unless subs

        subs.each do |block|
          block.call(payload)
        rescue StandardError => e
          # Never let a subscriber crash the emitter
          $stderr.puts "[emitter] subscriber error on #{event_type}: #{e.message}"
        end
      end
    end

    # Clear all subscribers (useful in tests).
    def clear!
      @mutex.synchronize { @subscribers.clear }
    end
  end
end
