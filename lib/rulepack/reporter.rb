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
      raise ArgumentError, "Unsupported format: #{format}" unless SUPPORTED_FORMATS.include?(fmt)

      case fmt
      when :json then JsonRenderer.print(result, out: out)
      when :yaml then out.puts JsonRenderer.sanitize(result.data).to_yaml
      else TextRenderer.print(result, out: out)
      end
    end
  end
end
