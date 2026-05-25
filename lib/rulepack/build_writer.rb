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
      build_index_data = {
        version: 3.0,
        generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        packages: index_data[:packages]
      }
      begin
        Rulepack::Common.write_yaml_atomic(Rulepack::Common::BUILD_INDEX_PATH, build_index_data)
        Rulepack::Common.log "📝 Build index written: #{Rulepack::Common::BUILD_INDEX_PATH}"
        puts "\n📝 Build index written: #{Rulepack::Common::BUILD_INDEX_PATH}"
      rescue StandardError => e
        Rulepack::Common.log_error "Failed to write build index: #{e.message}"
        exit 1
      end
    end

    def generate_catalog
      begin
        load Rulepack::Common::RULEPACK_ROOT.join('lib', 'rulepack', 'generate-catalog.rb').to_s
      rescue StandardError => e
        Rulepack::Common.log_error "Failed to generate catalog: #{e.message}"
      end
    end
  end
end
