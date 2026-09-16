# frozen_string_literal: true

require 'yaml'
require_relative 'reporter/text_renderer'
require_relative 'reporter/json_renderer'

module Rulepack
  # Renders a Rulepack::Result in text, JSON, or YAML format.
  module Reporter
    module_function

    SUPPORTED_FORMATS = %i[text json yaml].freeze

    def print(result, format: :text, out: $stdout)
      fmt = format.to_sym
      unless SUPPORTED_FORMATS.include?(fmt)
        hint = ' (jsonl is a stream format: the CLI renders it via JsonlRenderer, not Reporter)' if fmt == :jsonl
        raise Rulepack::InvalidOptionValue, "Unsupported format: #{format}#{hint}"
      end

      case fmt
      when :json then JsonRenderer.print(result, out: out)
      when :yaml then out.puts JsonRenderer.sanitize(result.to_h).to_yaml
      else TextRenderer.print(result, out: out)
      end
    end
  end
end
