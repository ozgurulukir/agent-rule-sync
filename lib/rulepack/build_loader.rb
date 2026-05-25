# frozen_string_literal: true

# Build Loader — PKGBUILD discovery, loading, validation, and index initialization.
#
# Extracted from build.rb (P-B: split 430 LOC build.rb into 3 focused files).

require 'pathname'
require_relative 'common'

module Rulepack
  module BuildLoader
    module_function

    def discover_pkgbuilds
      Rulepack::Common::RULEPACK_ROOT.join('data', 'packages').glob('*/PKGBUILD')
    end

    def load_and_validate_pkgbuild(pkgbuild_path)
      pkg_dir = pkgbuild_path.dirname
      pkg = Rulepack::Common.load_pkgbuild(pkg_dir)

      pkgname = pkg[:pkgname].to_sym

      # Set default epoch/pkgrel before validation (PKGBUILD may omit them)
      pkg[:epoch] = 0 unless pkg.key?(:epoch)
      pkg[:pkgrel] = 1 unless pkg.key?(:pkgrel)

      # Validate PKGBUILD
      validation_error = Rulepack::Common.validate_pkgbuild(pkg, pkg_dir)
      if validation_error != true
        Rulepack::Common.log_error "PKGBUILD validation failed for #{pkgname}: #{validation_error}"
        return nil
      end

      [pkg, pkgname]
    rescue StandardError => e
      Rulepack::Common.log_error "Failed to load #{pkgbuild_path}: #{e.message}"
      nil
    end

    def init_pkg_index(pkg)
      pkgname = pkg[:pkgname].to_sym
      {
        pkgver: pkg[:pkgver],
        pkgrel: pkg[:pkgrel],
        epoch: pkg[:epoch],
        pkgdesc: pkg[:pkgdesc],
        order: pkg[:order] || 0,
        status: 'stable',
        installed: [],
        available_targets: [],
        dependencies: pkg[:dependencies] || [],
        conflicts: pkg[:conflicts] || [],
        provides: pkg[:provides] || [],
        tags: pkg[:tags] || [],
        checksums: { source: nil, built: {} }
      }
    end

    def update_pkg_index_from_pkg(pkg_index, pkg)
      # Always update version fields (epoch/pkgrel may have changed in PKGBUILD)
      pkg_index[:pkgver] = pkg[:pkgver]
      pkg_index[:pkgrel] = pkg[:pkgrel]
      pkg_index[:epoch] = pkg[:epoch]
      # Always update targets (they may have changed)
      pkg_index[:targets] = pkg[:targets] || []
    end
  end
end
