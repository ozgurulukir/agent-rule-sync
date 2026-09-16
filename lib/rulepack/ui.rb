# frozen_string_literal: true

# Rulepack::UI — interactive terminal I/O (spinners, confirmations, prompts).
#
# An instance wraps injectable stdin/stdout streams; `interactive?` is pure
# tty detection on those streams, so subprocess runs (pipes) automatically
# behave non-interactively. Tests inject UI::Null (or a scripted instance)
# instead of flipping environment variables.
module Rulepack
  class UI
    attr_reader :stdin, :stdout

    def initialize(stdin: $stdin, stdout: $stdout)
      @stdin = stdin
      @stdout = stdout
    end

    # The process-wide instance used by callers that have no ui: threaded to
    # them yet (strangler scaffold — new code should accept ui: explicitly).
    def self.default
      @default ||= new
    end

    def self.default=(ui)
      @default = ui
    end

    def interactive?
      @stdin.isatty && @stdout.isatty
    end

    # Headless contexts (CI, pipes) must never prompt — callers treat this as
    # "answer no to everything interactive".
    def headless?
      !interactive? || ENV['CI']
    end

    # Run block under a spinner. No-op wrapper when headless or in debug.
    def spin(msg)
      return yield if headless? || Rulepack::Logging.log_level == :debug

      # Prevent nested spinners
      if Thread.current[:in_spinner]
        return yield
      end

      Thread.current[:in_spinner] = true
      Thread.current[:spinner_msg] = msg
      spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

      # Capture msg in a closure so the spinner thread reads the actual message
      # instead of its own (empty) Thread.current[:spinner_msg] — thread-locals
      # are per-thread and not shared between main and spawned threads.
      thread = Thread.new do
        i = 0
        loop do
          @stdout.print "\r\e[K\e[36m#{spinner_chars[i]}\e[0m #{msg}"
          @stdout.flush
          i = (i + 1) % spinner_chars.length
          sleep 0.1
        end
      end
      Thread.current[:spinner_thread] = thread

      begin
        result = yield
      ensure
        thread.kill
        thread.join(0.1) # Wait for it to die
        @stdout.print "\r\e[K"
        @stdout.flush
        Thread.current[:in_spinner] = false
        Thread.current[:spinner_msg] = nil
        Thread.current[:spinner_thread] = nil
      end
      result
    end

    # Yes/no confirmation; returns true only on explicit yes. EOF => false.
    def confirm(prompt)
      return false unless interactive?

      @stdout.print "\n  \e[33m?\e[0m #{prompt} [y/N] "
      input = @stdin.gets
      if input.nil?
        @stdout.puts # newline after EOF so the prompt line terminates
        return false
      end
      %w[y yes].include?(input.chomp.downcase)
    end

    # Collision resolution prompt. Returns one of
    # 'overwrite' | 'append' | 'ignore' | 'stop'; non-interactive => 'stop'.
    def collision_prompt(install_path)
      return 'stop' unless interactive?

      loop do
        @stdout.print "\n  \e[33m?\e[0m Collision detected: #{install_path} exists. Overwrite? [o(verwrite)/a(ppend)/i(gnore)/s(top)] "

        input = @stdin.gets
        return 'stop' if input.nil? # Handle EOF (Ctrl+D)

        case input.chomp.downcase
        when 'o', 'overwrite', 'y', 'yes' then return 'overwrite'
        when 'a', 'append' then return 'append'
        when 'i', 'ignore', 'n', 'no' then return 'ignore'
        when 's', 'stop', 'q', 'quit' then return 'stop'
        else
          @stdout.puts "\n  Invalid input. Please enter 'o', 'a', 'i', or 's'."
        end
      end
    end

    # Non-interactive UI: base-class guards already decline every interactive
    # path (spin yields directly, confirm => false, collision => 'stop'), so
    # overriding interactive? is sufficient.
    class Null < UI
      def interactive?
        false
      end
    end
  end
end
