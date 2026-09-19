# frozen_string_literal: true

require_relative 'encoding_defaults'
require_relative 'common'

module Rulepack
  # BuildCatalog — the `rulepack catalog` backend: reads the build artifact
  # build/catalog.json (written by BuildWriter.generate_catalog). Text mode
  # emits the file bytes verbatim via the :raw_json view; json/yaml carry the
  # raw content in data.
  module BuildCatalog
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
      catalog_path = Rulepack::Common.paths.build_dir.join('catalog.json')
      unless catalog_path.exist?
        return Rulepack::Result.new(
          status: :failure,
          errors: ['Catalog not found. Run `rulepack build` first.']
        )
      end

      Rulepack::Result.new(
        status: :success,
        view: :raw_json,
        data: { raw: catalog_path.read }
      )
    end
  end
end
