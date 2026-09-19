# frozen_string_literal: true

require_relative 'encoding_defaults'
require_relative 'common'
require_relative 'catalog/remote_catalog'

module Rulepack
  # Remote — the `rulepack remote <search|list>` backend: operation wrapper
  # over Catalog::RemoteCatalog (the HTTP client). The index URL resolves
  # from RULEPACK_REMOTE_INDEX, falling back to the public default.
  module Remote
    DEFAULT_INDEX_URL = 'https://packages.rulepack.dev/index.json'

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
      subcommand, term = Array(options[:positional])
      index_url = ENV['RULEPACK_REMOTE_INDEX'] || DEFAULT_INDEX_URL

      case subcommand
      when 'search'
        return search_usage_result unless term

        results = Rulepack::Catalog::RemoteCatalog.new(index_url).search(term)
        Rulepack::Result.new(
          status: :success,
          view: :remote_search,
          data: { term: term, results: results }
        )
      when 'list'
        packages = Rulepack::Catalog::RemoteCatalog.new(index_url).list
        Rulepack::Result.new(
          status: :success,
          view: :remote_list,
          data: { packages: packages }
        )
      else
        Rulepack::Result.new(
          status: :failure,
          messages: [
            'Usage: rulepack remote <search|list> [args]',
            '  Set RULEPACK_REMOTE_INDEX to override the index URL.'
          ]
        )
      end
    rescue StandardError => e
      Rulepack::Result.new(status: :failure, messages: ["❌ Error: #{e.message}"])
    end

    def search_usage_result
      Rulepack::Result.new(
        status: :failure,
        messages: ['Usage: rulepack remote search <term>']
      )
    end
  end
end
