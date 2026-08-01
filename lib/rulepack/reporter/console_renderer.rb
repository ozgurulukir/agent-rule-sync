# frozen_string_literal: true

# Console renderer — subscribes to the emitter and reproduces current stdout output.
#
# This is the DEFAULT renderer. It must reproduce today's console output
# byte-for-byte (golden-file tested).
module Rulepack
  module Reporter
    class ConsoleRenderer
      def initialize(out: $stdout)
        @out = out
        @subscriptions = []
        subscribe!
      end

      def subscribe!
        @subscriptions << Rulepack::Emitter.subscribe(:info) do |payload|
          @out.puts payload[:message]
        end

        @subscriptions << Rulepack::Emitter.subscribe(:warn) do |payload|
          @out.puts "\u26a0\ufe0f  #{payload[:message]}"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:error) do |payload|
          @out.puts "\u274c #{payload[:message]}"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:stage_start) do |payload|
          @out.puts "  \u2192 #{payload[:stage]} for #{payload[:platform]} (#{payload[:output]})"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:stage_done) do |payload|
          @out.puts "    \u2713 #{payload[:stage]} (#{payload[:checksum]})"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:package_built) do |payload|
          @out.puts "  \u2713 Built: #{payload[:pkgname]}"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:progress) do |payload|
          @out.puts payload[:message]
        end
      end

      def unsubscribe!
        @subscriptions.each { |id| Rulepack::Emitter.unsubscribe(id) }
        @subscriptions.clear
      end
    end
  end
end
