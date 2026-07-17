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
      spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

      thread = Thread.new do
        i = 0
        loop do
          print "\r\e[K\e[36m#{spinner_chars[i]}\e[0m #{msg}"
          i = (i + 1) % spinner_chars.length
          sleep 0.1
        end
      end

      begin
        result = yield
      ensure
        thread.kill
        print "\r\e[K" # Clear line
        Thread.current[:in_spinner] = false
      end
      result
    end
  end
end
