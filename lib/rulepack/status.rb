# frozen_string_literal: true

require_relative 'encoding_defaults'
require_relative 'common'

module Rulepack
  # Status — the `rulepack status` backend: a summary of the installed index.
  # Text rendering routes through the :status view (reporter/text_renderer.rb);
  # the lines there reproduce the former runner-internal print_status output.
  module Status
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

    def run_unscoped(_options = {})
      index = begin
        Rulepack::InstalledIndex.load
      rescue Rulepack::IndexNotFound, Rulepack::IndexCorrupt
        return Rulepack::Result.new(
          status: :success,
          messages: ['  No index found. Run `rulepack build` first.']
        )
      end

      installed_platforms = Hash.new { |h, k| h[k] = [] }
      (index[:packages] || {}).each do |name, pkg|
        Array(pkg[:installed]).each do |rec|
          installed_platforms[rec[:platform]] << name.to_s
        end
      end

      Rulepack::Result.new(
        status: :success,
        view: :status,
        data: {
          total_packages: (index[:packages] || {}).size,
          platforms: installed_platforms
        }
      )
    end
  end
end
