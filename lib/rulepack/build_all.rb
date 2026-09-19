# frozen_string_literal: true

require_relative 'encoding_defaults'
require_relative 'common'

module Rulepack
  # Composite backend for the build command: Build → Aggregate, run in
  # order, short-circuiting on failure. The merge semantics are the former
  # Runner#run_phases: the failing phase's Result is returned unmerged, data
  # is flat-merged across phases, partial status propagates, and the first
  # data-bearing phase's view routes the merged result's text rendering.
  #
  # Second caller: Bump.invoke_build (rebuild after applying version bumps).
  module BuildAll
    module_function

    def run(options = {}, paths: nil, ui: nil)
      if ui
        Rulepack::Common.with_ui(ui) { run(options, paths: paths) }
      elsif paths
        Rulepack::Common.with_paths(paths) { run_unscoped(options) }
      else
        run_unscoped(options)
      end
    end

    def run_unscoped(options = {})
      build_result = Rulepack::Build.run(options)
      return build_result if build_result.failure?

      aggregate_result = Rulepack::Aggregate.run(options)
      return aggregate_result if aggregate_result.failure?

      Rulepack::Result.new(
        status: aggregate_result.status == :success ? build_result.status : aggregate_result.status,
        data: (build_result.data || {}).merge(aggregate_result.data || {}),
        messages: build_result.messages + aggregate_result.messages,
        view: :build
      )
    end
  end
end
