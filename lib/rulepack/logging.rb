# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require_relative 'emitter'

module Rulepack
  # Logging — the narration file-sink and stderr diagnostics channel.
  #
  # Console narration is NOT printed here: every log line is emitted as an
  # Emitter `:log` event (renderers decide whether/how it reaches stdout) and
  # appended to the log file unconditionally. log_error/log_warn keep their
  # stderr echo at the source so diagnostics survive even with no renderer
  # subscribed.
  module Logging
    module_function

    @_default_log_file = Pathname.new(__dir__).parent.parent.join('build', 'install.log')
    @_log_level = nil
    @_show_timing = false

    def log_file
      @_default_log_file
    end

    def log_file=(path)
      @_default_log_file = Pathname.new(path)
    end

    def log_level
      @_log_level || Rulepack::Config.log_level
    end

    def log_level=(val)
      @_log_level = val
    end

    def show_timing
      @_show_timing
    end

    def show_timing=(val)
      @_show_timing = val
    end

    # ─── Logging Methods ────────────────────────────────────────────────────────

    # Emit a narration event (level-filtered) and append the timestamped line
    # to the log file. The file write is unconditional — level filtering only
    # governs the event, i.e. console visibility.
    def log(msg, level: :info, log_file: nil)
      log_file ||= @_default_log_file
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      line = "[#{timestamp}] #{msg}"
      level_order = { error: 0, warn: 1, info: 2, debug: 3 }

      if level_order[level] <= level_order[log_level]
        Emitter.emit(:log, message: msg, level: level.to_s, time: timestamp)
      end

      FileUtils.mkpath(log_file.dirname)
      File.open(log_file.to_s, File::WRONLY | File::CREAT | File::APPEND, 0600) { |f| f.puts(line) }
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

    # Time an operation and log elapsed time
    def time(operation_name)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      log("⏱  #{format('%.3f', elapsed)}s — #{operation_name}", log_file: nil) if show_timing
      result
    end
  end
end
