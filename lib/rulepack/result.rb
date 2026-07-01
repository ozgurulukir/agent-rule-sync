# frozen_string_literal: true

module Rulepack
  # Structured result object returned by backend operations.
  # CLI and TUI renderers consume this instead of parsing stdout.
  class Result
    attr_reader :status, :data, :errors, :messages

    STATUSES = %i[success partial failure].freeze

    def initialize(status:, data: nil, errors: [], messages: [])
      raise ArgumentError, "Invalid status: #{status}" unless STATUSES.include?(status)

      @status = status
      @data = data
      @errors = Array(errors)
      @messages = Array(messages)
    end

    def success? = @status == :success
    def partial? = @status == :partial
    def failure? = @status == :failure

    def to_h
      { status: @status, data: @data, errors: @errors, messages: @messages }
    end
  end
end
