# frozen_string_literal: true

module Rulepack
  # Structured result object returned by backend operations.
  # CLI and TUI renderers consume this instead of parsing stdout.
  class Result
    attr_reader :status, :data, :errors, :messages, :view

    STATUSES = %i[success partial failure].freeze

    # view: declares which TextRenderer renderer prints this Result's data
    # in text mode (see reporter/text_renderer.rb). nil means "messages carry
    # the text output; data is json/yaml-only". Deliberately excluded from
    # to_h — the json/yaml/jsonl envelope stays {status, data, errors, messages}.
    def initialize(status:, data: nil, errors: [], messages: [], view: nil)
      raise ArgumentError, "Invalid status: #{status}" unless STATUSES.include?(status)

      @status = status
      @data = data
      @errors = Array(errors)
      @messages = Array(messages)
      @view = view
    end

    def success? = @status == :success
    def partial? = @status == :partial
    def failure? = @status == :failure

    def to_h
      { status: @status, data: @data, errors: @errors, messages: @messages }
    end
  end
end
