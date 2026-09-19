# frozen_string_literal: true

# Build Writer — Build index and catalog output.
#
# Extracted from build.rb (P-B: split 430 LOC build.rb into 3 focused files).

require 'json'
require_relative 'common'

module Rulepack
  module BuildWriter
    module_function

    def write_build_index(index_data)
      begin
        Rulepack::BuildIndex.write(index_data)
        Rulepack::Common.log "📝 Build index written: #{Rulepack::Common.paths.build_index_path}"
        puts "\n📝 Build index written: #{Rulepack::Common.paths.build_index_path}"
        true
      rescue StandardError => e
        Rulepack::Common.log_error "Failed to write build index: #{e.message}"
        false
      end
    end

    def generate_catalog
      begin
        require_relative 'generate-catalog'
        Rulepack::CatalogGenerator.main
      rescue StandardError => e
        Rulepack::Common.log_error "Failed to generate catalog: #{e.message}"
      end
    end
  end
end
