# frozen_string_literal: true

# Validates Step 2: no unguarded `exit` calls in lib/.
#
# The only allowed pattern is the guarded direct-execution exit:
#   exit <code> if __FILE__ == $PROGRAM_NAME
# which lets a library file double as a standalone script without
# affecting callers that `require` it.

require 'minitest/autorun'

class TestNoExitInLib < Minitest::Test
  LIB_DIR = File.join(File.expand_path('..', __dir__), 'lib')

  # Guarded exits that are acceptable (file-as-script pattern).
  ALLOWED_PATTERN = /\A\s*exit\b.*\bif\s+__FILE__\s*==\s*\$PROGRAM_NAME\b/.freeze

  def test_no_unguarded_exit_in_lib
    offenders = []

    Dir.glob(File.join(LIB_DIR, '**', '*.rb')).sort.each do |file|
      File.foreach(file, encoding: 'UTF-8').with_index(1) do |line, lineno|
        next unless line.match?(/^\s*exit\b/)
        next if line.match?(ALLOWED_PATTERN)

        offenders << "#{file.sub("#{LIB_DIR}/", '')}:#{lineno}: #{line.strip}"
      end
    end

    assert_empty offenders,
      "Found unguarded exit calls in lib/ (only `exit ... if __FILE__ == $PROGRAM_NAME` is allowed):\n" +
        offenders.join("\n")
  end

  def test_no_capture_script_run_magic_string
    offenders = []

    Dir.glob(File.join(LIB_DIR, '**', '*.rb')).sort.each do |file|
      File.foreach(file, encoding: 'UTF-8').with_index(1) do |line, lineno|
        next unless line.include?('capture_script_run')

        offenders << "#{file.sub("#{LIB_DIR}/", '')}:#{lineno}: #{line.strip}"
      end
    end

    assert_empty offenders,
      "Found capture_script_run magic-string references in lib/:\n" +
        offenders.join("\n")
  end
end