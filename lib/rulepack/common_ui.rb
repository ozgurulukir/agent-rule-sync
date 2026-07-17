# frozen_string_literal: true

module Rulepack
  module Common
    module_function

    def spin(msg, &block)
      return yield if ENV['RULEPACK_TEST'] || !$stdout.isatty || Rulepack::Logging.log_level == :debug || ENV['CI']

      # Prevent nested spinners
      if Thread.current[:in_spinner]
        return yield
      end

      Thread.current[:in_spinner] = true
      Thread.current[:spinner_msg] = msg
      spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

      thread = Thread.new do
        i = 0
        loop do
          print "\r\e[K\e[36m#{spinner_chars[i]}\e[0m #{Thread.current[:spinner_msg]}"
          $stdout.flush
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
        print "\r\e[K" # Clear line
        $stdout.flush
        Thread.current[:in_spinner] = false
        Thread.current[:spinner_msg] = nil
        Thread.current[:spinner_thread] = nil
      end
      result
    end
  end
end
