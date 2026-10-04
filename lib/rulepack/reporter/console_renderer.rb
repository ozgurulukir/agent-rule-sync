# frozen_string_literal: true

# Console renderer — subscribes to the emitter and reproduces current stdout output.
#
# This is the DEFAULT renderer. It must reproduce today's console output
# byte-for-byte (golden-file tested).
#
# :log events (the Common.log* narration channel) render exactly like the
# former Logging stdout echo did — timestamped, spinner-aware. `log_stdout:
# false` (json/yaml envelope formats) suppresses only that stdout echo; the
# emitter keeps firing and the log file keeps receiving every line.
module Rulepack
  module Reporter
    class ConsoleRenderer
      # out: nil means "current $stdout at emit time" so test stdout-capture
      # (and any stream redirection) applies to events too.
      def initialize(out: nil, log_stdout: true)
        @out = out
        @log_stdout = log_stdout
        @subscriptions = []
        subscribe!
      end

      def emit_out
        @out || $stdout
      end

      def subscribe!
        @subscriptions << Rulepack::Emitter.subscribe(:log) do |payload|
          next unless @log_stdout

          render_log_line(payload)
        end

        @subscriptions << Rulepack::Emitter.subscribe(:info) do |payload|
          emit_out.puts payload[:message]
        end

        @subscriptions << Rulepack::Emitter.subscribe(:warn) do |payload|
          emit_out.puts "\u26a0\ufe0f  #{payload[:message]}"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:error) do |payload|
          emit_out.puts "\u274c #{payload[:message]}"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:stage_start) do |payload|
          emit_out.puts "  \u2192 #{payload[:stage]} for #{payload[:platform]} (#{payload[:output]})"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:stage_done) do |payload|
          emit_out.puts "    \u2713 #{payload[:stage]} (#{payload[:checksum]})"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:package_built) do |payload|
          emit_out.puts "  \u2713 Built: #{payload[:pkgname]}"
        end

        @subscriptions << Rulepack::Emitter.subscribe(:progress) do |payload|
          emit_out.puts payload[:message]
        end
      end

      def unsubscribe!
        @subscriptions.each { |id| Rulepack::Emitter.unsubscribe(id) }
        @subscriptions.clear
      end

      private

      # Byte-compatible with the former Logging.log stdout branch, including
      # the spinner-clear/redraw interplay (Thread.current is shared: narration
      # happens on the thread that owns the spinner).
      def render_log_line(payload)
        line = "[#{payload[:time]}] #{payload[:message]}"
        if Thread.current[:in_spinner] && Thread.current[:spinner_thread]
          emit_out.print "\r\e[K"
          emit_out.puts line
          emit_out.print "\r\e[K\e[36m⠋\e[0m #{Thread.current[:spinner_msg]}"
          emit_out.flush
        else
          emit_out.puts line
        end
      end
    end
  end
end
