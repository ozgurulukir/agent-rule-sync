#!/usr/bin/env ruby
# frozen_string_literal: true

# Install CLI entry point — thin wrapper around Installer.dispatch
#
# Usage:
#   ruby lib/rulepack/install.rb [package_name] --target <platform|all> [options]
#
# Pacman shorthand:
#   ruby lib/rulepack/install.rb -S [package_name] --target <platform|all>

require_relative 'installer'
require_relative 'common'
require_relative 'cli_parser'

# Gracefully shift pacman -S flag if passed as first argument
ARGV.shift if ARGV.first == '-S'

begin
  opts = Rulepack::CliParser.parse(ARGV)
rescue StandardError => e
  abort "\u{274c} Error: #{e.message}"
end

# Check positional count
if opts[:positional]&.size.to_i > 1
  abort "\u{274c} Error: Too many positional arguments. Usage: rulepack install [package] --target <platform|all>"
end

Rulepack::Install.dispatch(opts)
