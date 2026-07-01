# frozen_string_literal: true

require 'json'

module Rulepack
  module Reporter
    # JSON rendering for Rulepack::Result objects.
    module JsonRenderer
      module_function

      def print(result, out: $stdout)
        out.puts sanitize(result.to_h).to_json
      end

      # Recursively convert non-JSON-friendly values (Pathname, Symbol) into
      # plain strings so the output is safe for `JSON.generate`.
      def sanitize(obj)
        case obj
        when Hash
          obj.transform_keys { |k| k.is_a?(Symbol) ? k.to_s : k }
             .transform_values { |v| sanitize(v) }
        when Array
          obj.map { |v| sanitize(v) }
        when Pathname
          obj.to_s
        when Symbol
          obj.to_s
        else
          obj
        end
      end
    end
  end
end
