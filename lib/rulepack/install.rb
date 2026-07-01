#!/usr/bin/env ruby
# frozen_string_literal: true

# Install CLI entry point — thin wrapper around Installer.dispatch
#
# Usage:
#   ruby lib/rulepack/install.rb [package_name] --target <platform|all> [options]
#
# Pacman shorthand:
#   ruby lib/rulepack/install.rb -S [package_name] --target <platform|all>

require_relative 'encoding_defaults'
require_relative 'installer'
require_relative 'common'
require_relative 'cli_parser'

begin
  opts = Rulepack::CliParser.parse(ARGV)
rescue StandardError => e
  abort "\u{274c} Error: #{e.message}"
end

# Check positional count
if opts[:positional]&.size.to_i > 1
  abort "\u{274c} Error: Too many positional arguments. Usage: rulepack install [package] --target <platform|all>"
end

begin
  result = Rulepack::Install.dispatch(opts)
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
