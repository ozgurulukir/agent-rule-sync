# frozen_string_literal: true

module Rulepack
  module Common
    module_function

      # ─── Shared Logging ──────────────────────────────────────────────────────────

      # Set the default log file for shared logging
      def set_log_file(path)
        @_default_log_file = Pathname.new(path)
      end

      # Log a message with level filtering.
      # Respects $LOG_LEVEL (global, set per-module): error < warn < info < debug
      def log(msg, level: :info, log_file: nil)
        log_file ||= @_default_log_file
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        line = "[#{timestamp}] #{msg}"
        level_order = { error: 0, warn: 1, info: 2, debug: 3 }
        if level_order[level] <= level_order[$LOG_LEVEL || Rulepack::Config.log_level]
          puts line
        end
        FileUtils.mkpath(log_file.dirname)
        File.open(log_file.to_s, 'a') { |f| f.puts(line) }
      end

      def log_error(msg, log_file: nil)
        warn "❌ #{msg}"
        log("ERROR: #{msg}", level: :error, log_file: log_file)
      end

      def log_warn(msg, log_file: nil)
        warn "⚠️  #{msg}"
        log("WARN: #{msg}", level: :warn, log_file: log_file)
      end

      def log_debug(msg, log_file: nil)
        log("DEBUG: #{msg}", level: :debug, log_file: log_file)
      end

      # Time an operation and log elapsed time (respects $SHOW_TIMING)
      def time(operation_name)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        if $SHOW_TIMING
          log("⏱  #{format('%.3f', elapsed)}s — #{operation_name}", log_file: nil)
        end
        result
      end
    end
end
