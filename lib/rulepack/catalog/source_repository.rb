# frozen_string_literal: true

# Source Repository interface — separates "where a package comes from"
# from "how it is built".
#
# Implementations:
#   LocalCatalog  — wraps existing Source/Cache primitives (current behavior)
#   RemoteCatalog — reads a remote index over HTTP (Step 9)
module Rulepack
  module Catalog
    # Result of fetching a source.
    SourceResult = Data.define(:content, :sha256, :source_dir)

    class SourceRepository
      # Fetch source content and return [content, sha256].
      # For directory sources, content may be nil and source_dir is set.
      def fetch(source_cfg, pkg_dir: nil)
        raise NotImplementedError, "#{self.class} must implement #fetch"
      end

      # Resolve a source configuration to a directory path.
      def directory(source_cfg, pkg_dir: nil)
        raise NotImplementedError, "#{self.class} must implement #directory"
      end
    end
  end
end
