# frozen_string_literal: true

# PackageResolver — virtualizes package namespaces under data/packages/.
#
# Supports three physical layouts while keeping the runtime database flat:
#   data/packages/local/<pkgname>/PKGBUILD     (ignored, local/personal)
#   data/packages/upstream/<pkgname>/PKGBUILD  (tracked, online sources)
#   data/packages/<pkgname>/PKGBUILD           (legacy/flat, tracked)
#
# Search precedence for a given pkgname: local > upstream > legacy.
# This lets a user override a tracked package with a local copy.

require 'pathname'
require 'set'

module Rulepack
  module PackageResolver
    module_function

    # Namespaces that are explicitly namespaced.
    NAMESPACES = %w[local upstream].freeze

    # Namespace label used for flat/legacy packages.
    LEGACY_NAMESPACE = 'core'

    # Returns the Pathname to a PKGBUILD for a given package name,
    # or a non-existent Pathname if the package cannot be resolved.
    def pkgbuild_path(pkgname)
      name = pkgname.to_s
      NAMESPACES.each do |ns|
        path = packages_root.join(ns, name, 'PKGBUILD')
        return path if path.exist?
      end
      packages_root.join(name, 'PKGBUILD')
    end

    # Returns the package directory for a given package name.
    def resolve_pkgdir(pkgname)
      pkgbuild_path(pkgname).dirname
    end

    # Enumerate all discoverable PKGBUILD paths.
    #
    # namespaces:
    #   :all     -> local, upstream, and legacy flat packages
    #   :tracked -> upstream and legacy flat packages (excludes local)
    #
    # Duplicate pkgnames are resolved by precedence; only one path per pkgname
    # is returned.
    def all_pkgbuilds(namespaces: :all)
      by_name = {}

      # Namespaced directories in declared order (local first, then upstream).
      NAMESPACES.each do |ns|
        next if namespaces == :tracked && ns == 'local'

        packages_root.join(ns).glob('*/PKGBUILD').each do |path|
          name = path.dirname.basename.to_s
          by_name[name] ||= path
        end
      end

      # Legacy flat layout has the lowest precedence.
      packages_root.glob('*/PKGBUILD').each do |path|
        name = path.dirname.basename.to_s
        by_name[name] ||= path
      end

      by_name.sort_by { |name, _path| name }.map { |_name, path| path }
    end

    # Yield [path, namespace] for every discoverable PKGBUILD.
    def each_pkgbuild(namespaces: :all, &block)
      return to_enum(:each_pkgbuild, namespaces: namespaces) unless block

      all_pkgbuilds(namespaces: namespaces).each do |path|
        block.call(path, namespace_for(path))
      end
    end

    # Infer the namespace of a PKGBUILD path.
    # Returns 'local', 'upstream', or PackageResolver::LEGACY_NAMESPACE.
    def namespace_for(pkgbuild_path)
      parts = Pathname.new(pkgbuild_path).each_filename.to_a
      idx = parts.index('packages')
      return LEGACY_NAMESPACE unless idx && parts[idx + 1]

      ns = parts[idx + 1]
      NAMESPACES.include?(ns) ? ns : LEGACY_NAMESPACE
    end

    def packages_root
      Rulepack::Common::RULEPACK_ROOT.join('data', 'packages')
    end
  end
end
