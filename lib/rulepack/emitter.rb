# frozen_string_literal: true

# Lightweight event emitter for Rulepack operations.
#
# Supports multiple subscribers. Each subscriber receives (event_type, payload).
# Events are fire-and-forget: subscribers must not raise.
#
# Usage:
#   Rulepack::Emitter.emit(:stage_start, stage: 'build', platform: 'opencode')
#   Rulepack::Emitter.subscribe(:stage_start) { |payload| ... }
#
# Built-in event types:
#   :stage_start   — a pipeline stage begins (payload: {stage:, platform:})
#   :stage_done    — a pipeline stage completes (payload: {stage:, platform:})
#   :package_built — a package finished building (payload: {pkgname:, status:})
#   :target_built  — a target artifact was written (payload: {pkgname:, platform:, output:, checksum:})
#   :warn          — a warning occurred (payload: {message:})
#   :error         — an error occurred (payload: {message:})
#   :info          — informational message (payload: {message:})
#   :progress      — progress indicator (payload: {message:})
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
