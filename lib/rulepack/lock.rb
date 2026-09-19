# frozen_string_literal: true

require_relative 'encoding_defaults'
require_relative 'common'
require_relative 'lockfile'

module Rulepack
  # Lock — the `rulepack lock` backend: a read-only report over the lockfile
  # store (Rulepack::Lockfile remains the store class: add/remove/write!).
  # The lockfile anchors to the working directory by design.
  module Lock
    module_function

    def run(options = {}, paths: nil, ui: nil, lockfile: nil)
      if ui
        Rulepack::Common.with_ui(ui) { run(options, paths: paths, lockfile: lockfile) }
      elsif paths
        Rulepack::Common.with_paths(paths) { run_unscoped(lockfile) }
      else
        run_unscoped(lockfile)
      end
    end

    def run_unscoped(lockfile = nil)
      entries = (lockfile || Rulepack::Lockfile.new).entries
      Rulepack::Result.new(
        status: :success,
        view: :lock,
        data: { entries: entries }
      )
    rescue StandardError => e
      Rulepack::Result.new(status: :failure, messages: ["❌ Error: #{e.message}"])
    end
  end
end
