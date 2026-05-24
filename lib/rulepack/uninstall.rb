#!/usr/bin/env ruby
# frozen_string_literal: true

# Uninstall CLI entry point — thin wrapper around Uninstaller.dispatch
#
# Usage:
#   ruby lib/rulepack/uninstall.rb [package_name] --target <platform|all> [options]
#
# Pacman shorthand:
#   ruby lib/rulepack/uninstall.rb -R [package_name] --target <platform|all>

require_relative 'uninstaller'
require_relative 'common'
require_relative 'cli_parser'

# Gracefully shift pacman -R flag if passed as first argument
ARGV.shift if ARGV.first == '-R'

begin
  opts = Rulepack::CliParser.parse(ARGV)
rescue StandardError => e
  abort "\u{274c} Error: #{e.message}"
end

# Check positional count
if opts[:positional]&.size.to_i > 1
  abort "\u{274c} Error: Too many positional arguments. Usage: rulepack uninstall [package] --target <platform|all>"
end

Rulepack::Uninstaller.dispatch(opts)
