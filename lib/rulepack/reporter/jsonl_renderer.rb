# frozen_string_literal: true

require 'json'

# JSONL renderer — emits one JSON object per event (additive, --format jsonl).
module Rulepack
  module Reporter
    class JsonlRenderer
      def initialize(out: $stdout)
        @out = out
        @subscriptions = []
        subscribe!
      end

      def subscribe!
        %i[stage_start stage_done package_built target_built warn error info progress].each do |event_type|
          @subscriptions << Rulepack::Emitter.subscribe(event_type) do |payload|
            @out.puts JSON.generate({ event: event_type.to_s, **payload })
          end
        end
      end

      def unsubscribe!
        @subscriptions.each { |id| Rulepack::Emitter.unsubscribe(id) }
        @subscriptions.clear
      end
    end
  end
end
