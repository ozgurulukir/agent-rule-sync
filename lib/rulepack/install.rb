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
require_relative 'models/package'
require_relative 'models/platform'
require_relative 'models/target'
require_relative 'installer'
require_relative 'common'
require_relative 'cli_parser'

# CLI runner block
if __FILE__ == $PROGRAM_NAME
  begin
    opts = Rulepack::CliParser.parse(ARGV)

    # Check positional count
    if opts[:positional]&.size.to_i > 1
      warn "\u{274c} Error: Too many positional arguments. Usage: rulepack install [package] --target <platform|all>"
      exit_code = 1
    else
      result = Rulepack::Install.dispatch(opts)

      if result.failure?
        if (opts[:format] || :text).to_sym == :text
          result.messages.each { |m| warn m }
          result.errors.each { |e| warn "Error: #{e}" }
        else
          Rulepack::Reporter.print(result, format: opts[:format])
        end
        exit_code = 1
      else
        Rulepack::Reporter.print(result, format: opts[:format] || :text)
        exit_code = 0
      end
    end
  rescue StandardError => e
    warn "\u{274c} Error: #{e.message}"
    exit_code = 1
  end
  $rulepack_exit_code = exit_code
  exit exit_code if __FILE__ == $PROGRAM_NAME
end
