# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module Rulepack
  module Logging
    module_function

    @_default_log_file = Pathname.new(__dir__).parent.parent.join('build', 'install.log')
    @_log_level = nil
    @_show_timing = false
    @_console_silent = false

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

    # When true, the stdout echo of log() is skipped — narration goes to the
    # log file only. log_error/log_warn keep their stderr diagnostics: stderr
    # is not part of the machine-readable stdout stream (--format
    # json|yaml|jsonl sets this from the CLI runner), so silencing it would
    # only hide information.
    def console_silent
      @_console_silent
    end

    def console_silent=(val)
      @_console_silent = val
    end

    # ─── Logging Methods ────────────────────────────────────────────────────────

    # Log a message with level filtering.
    # Respects log_level: error < warn < info < debug
    def log(msg, level: :info, log_file: nil)
      log_file ||= @_default_log_file
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      line = "[#{timestamp}] #{msg}"
      level_order = { error: 0, warn: 1, info: 2, debug: 3 }

      if !@_console_silent && level_order[level] <= level_order[log_level]
        if Thread.current[:in_spinner] && Thread.current[:spinner_thread]
          print "\r\e[K"
          puts line
          print "\r\e[K\e[36m⠋\e[0m #{Thread.current[:spinner_msg]}"
          $stdout.flush
        else
          puts line
        end
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
