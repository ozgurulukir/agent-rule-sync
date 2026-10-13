# frozen_string_literal: true

# Covers Rulepack::UI#ask — the interactive fallback behind the missing
# --target prompts (install/uninstall/fix/verify). The contract: silent nil
# when the streams are not a terminal (pipes, capture_io, CI), the
# "? <prompt>" banner plus stripped input when interactive, and nil (with the
# prompt line terminated) on EOF so callers can fall back to a hard error.

require_relative 'helper'
require 'stringio'

class TestUI < Minitest::Test
  # The ask prompt renders a yellow "?" with ANSI escapes; captured verbatim
  # here so assertions compare exact output rather than fragile substrings.
  PROMPT = "\n  \e[33m?\e[0m Target platform(s)? ".freeze

  # StringIO#isatty is always false, so a plain pair reads as non-interactive.
  # Stub isatty on both streams to simulate the real tty combination that
  # interactive? requires; ask only consults interactive?.
  def interactive_ui(stdin, stdout)
    stdin.define_singleton_method(:isatty) { true }
    stdout.define_singleton_method(:isatty) { true }
    Rulepack::UI.new(stdin: stdin, stdout: stdout)
  end

  def test_ask_returns_nil_and_prints_nothing_when_not_interactive
    out = StringIO.new
    ui = Rulepack::UI.new(stdin: StringIO.new("opencode\n"), stdout: out)

    assert_nil ui.ask('Target platform(s)?')
    assert_empty out.string
  end

  def test_ask_prints_prompt_and_returns_stripped_input_when_interactive
    out = StringIO.new
    ui = interactive_ui(StringIO.new("  opencode, all  \n"), out)

    assert_equal 'opencode, all', ui.ask('Target platform(s)?')
    assert_equal PROMPT, out.string
  end

  def test_ask_returns_nil_on_eof_and_terminates_the_prompt_line
    out = StringIO.new
    ui = interactive_ui(StringIO.new(''), out)

    assert_nil ui.ask('Target platform(s)?')
    assert_equal PROMPT + "\n", out.string
  end

  def test_ui_null_declines_ask_even_with_buffered_input
    out = StringIO.new
    ui = Rulepack::UI::Null.new(stdin: StringIO.new("opencode\n"), stdout: out)

    assert_nil ui.ask('Target platform(s)?')
    assert_empty out.string
  end
end
