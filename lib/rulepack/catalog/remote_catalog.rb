# frozen_string_literal: true

require 'json'
require_relative 'source_repository'

# Remote catalog — reads a remote package index over HTTP.
#
# Purely additive: the existing local workflow is untouched.
# Reuses the redirect-following logic from Source and the Cache.
module Rulepack
  module Catalog
    class RemoteCatalog < SourceRepository
      def initialize(index_url, cache: nil)
        @index_url = index_url
        @cache = cache || Rulepack::Common
        @_index = nil
      end

      # Fetch a package from the remote catalog by name.
      def fetch_package(pkgname)
        index = load_index
        entry = index[pkgname.to_s] || index[pkgname.to_sym]
        return nil unless entry

        url = entry[:url] || entry['url']
        sha256 = entry[:sha256] || entry['sha256']
        return nil unless url

        content, actual_sha = @cache.cached_fetch_url(url, sha256)
        SourceResult.new(content: content, sha256: actual_sha, source_dir: nil)
      end

      # Search the remote index for packages matching a term.
      def search(term)
        index = load_index
        term_re = /#{Regexp.escape(term.to_s)}/i
        index.select do |_key, entry|
          name = entry[:name] || entry['name'] || _key.to_s
          desc = entry[:description] || entry['description'] || ''
          name.match?(term_re) || desc.match?(term_re)
        end.map do |_key, entry|
          {
            name: entry[:name] || entry['name'] || _key.to_s,
            version: entry[:version] || entry['version'] || 'unknown',
            description: entry[:description] || entry['description'] || ''
          }
        end
      end

      # List all available packages in the remote index.
      def list
        index = load_index
        index.map do |_key, entry|
          {
            name: entry[:name] || entry['name'] || _key.to_s,
            version: entry[:version] || entry['version'] || 'unknown',
            description: entry[:description] || entry['description'] || ''
          }
        end
      end

      private

      def load_index
        return @_index if @_index

        content, = @cache.cached_fetch_url(@index_url, nil)
        raw = JSON.parse(content)
        @_index = raw.is_a?(Hash) ? raw : { packages: raw }
        @_index = @_index[:packages] || @_index['packages'] || @_index
        @_index
      end
    end
  end
end
