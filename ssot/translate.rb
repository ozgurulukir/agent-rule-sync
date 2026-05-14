#!/usr/bin/env ruby
# frozen_string_literal: true

# ssot/translate.rb — Standalone translator runner
# Usage: ruby ssot/translate.rb <translator_spec> [input_file] [output_file]
#   translator_spec: 'copy' | 'identity' | 'custom:path/to/translator.rb'
#   input_file:  path to read content from (default: stdin)
#   output_file: path to write result to (default: stdout)
#
# Example:
#   ruby ssot/translate.rb custom:translators/normalize-markdown.rb input.md output.md
#   cat input.md | ruby ssot/translate.rb copy > output.md

require 'yaml'
require 'pathname'
require_relative 'lib/common'

SSOT_ROOT = Pathname.new(__dir__).expand_path

def run_translator(translator_spec, content, pkgname: nil)
  Ssot::Lib::Common.apply_translator(translator_spec, content, pkgname: pkgname)
end

if __FILE__ == $PROGRAM_NAME
  translator_spec = ARGV.shift
  input_file = ARGV.shift
  output_file = ARGV.shift

  unless translator_spec
    warn "Usage: ruby ssot/translate.rb <translator_spec> [input_file] [output_file]"
    warn "  translator_spec: 'copy' | 'identity' | 'custom:<relative/path>'"
    warn "  input_file:  path (default: stdin)"
    warn "  output_file: path (default: stdout)"
    exit 1
  end

  # Read input
  content = if input_file
              Pathname.new(input_file).read
            else
              STDIN.read
            end

  # Apply translator
  result = run_translator(translator_spec, content)

  # Write output
  if output_file
    Pathname.new(output_file).write(result)
    puts "✓ Translated #{content.bytesize}B → #{result.bytesize}B (#{translator_spec})"
  else
    puts result
  end
end
