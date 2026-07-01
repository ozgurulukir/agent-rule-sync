#!/usr/bin/env ruby
# frozen_string_literal: true

# Uninstall CLI entry point — thin wrapper around Uninstaller.dispatch
#
# Usage:
#   ruby lib/rulepack/uninstall.rb [package_name] --target <platform|all> [options]
#
# Pacman shorthand:
#   ruby lib/rulepack/uninstall.rb -R [package_name] --target <platform|all>

require_relative 'encoding_defaults'
require_relative 'uninstaller'
require_relative 'common'
require_relative 'cli_parser'

begin
  opts = Rulepack::CliParser.parse(ARGV)
rescue StandardError => e
  abort "\u{274c} Error: #{e.message}"
end

# Check positional count
if opts[:positional]&.size.to_i > 1
  abort "\u{274c} Error: Too many positional arguments. Usage: rulepack uninstall [package] --target <platform|all>"
end

begin
  result = Rulepack::Uninstaller.dispatch(opts)
rescue StandardError => e
  warn "\u{274c} Error: #{e.message}"
  exit 1
end

if result.failure?
  if (opts[:format] || :text).to_sym == :text
    result.messages.each { |m| warn m }
    result.errors.each { |e| warn "Error: #{e}" }
  else
    Rulepack::Reporter.print(result, format: opts[:format])
  end
  exit 1
end

Rulepack::Reporter.print(result, format: opts[:format] || :text)
exit(0)
