# frozen_string_literal: true

require 'json'

# JSONL renderer — emits one JSON object per event (additive, --format jsonl).
module Rulepack
  module Reporter
    class JsonlRenderer
      # out: nil means "current $stdout at emit time" (dynamic capture).
      def initialize(out: nil)
        @out = out
        @subscriptions = []
        subscribe!
      end

      def emit_out
        @out || $stdout
      end

      def subscribe!
        %i[stage_start stage_done package_built target_built warn error info progress].each do |event_type|
          @subscriptions << Rulepack::Emitter.subscribe(event_type) do |payload|
            emit_out.puts JSON.generate({ event: event_type.to_s, **payload })
          end
        end

        # Final Result snapshot, emitted once by the CLI runner.
        @subscriptions << Rulepack::Emitter.subscribe(:result) do |payload|
          emit_out.puts JSON.generate({ event: 'result', **payload })
        end
      end

      def unsubscribe!
        @subscriptions.each { |id| Rulepack::Emitter.unsubscribe(id) }
        @subscriptions.clear
      end
    end
  end
end
