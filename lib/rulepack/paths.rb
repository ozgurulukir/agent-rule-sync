# frozen_string_literal: true

# Rulepack::Paths — frozen value object locating the runtime data stores.
#
# A Paths instance is a pure function of its root (plus optional overrides
# for split-root setups, e.g. tests where the build tree and the installed
# index live in different directories). Backend entry points accept a
# `paths:` keyword; when omitted they resolve through the scoped context in
# Rulepack::Common (see Common.with_paths), which defaults to Paths.for_root
# of the repository root.
module Rulepack
  class Paths
    attr_reader :root, :build_dir, :build_index_path, :index_yaml_path

    def initialize(root:, build_dir: nil, index_yaml_path: nil, build_index_path: nil)
      @root = Pathname.new(root).expand_path
      @build_dir = Pathname.new(build_dir || @root.join('build'))
      @build_index_path = Pathname.new(build_index_path || @build_dir.join('index.yaml'))
      @index_yaml_path = Pathname.new(index_yaml_path || @root.join('data', 'index.yaml'))
      freeze
    end

    def self.for_root(root)
      new(root: root)
    end

    # Derived locations — the single place that knows the layout of build/.
    def git_sources_dir(name = nil)
      name ? @build_dir.join('git-sources', name) : @build_dir.join('git-sources')
    end

    def store_dir
      @build_dir.join('store')
    end

    def platform_dir(platform, pkgname = nil)
      pkgname ? @build_dir.join(platform, pkgname.to_s) : @build_dir.join(platform)
    end

    # Keyword-merge with overrides (used by Common.with_paths). Returns a new
    # frozen instance; keys not overridden are inherited. Overriding build_dir
    # re-derives build_index_path unless one is given explicitly.
    def merge(build_dir: nil, index_yaml_path: nil, build_index_path: nil)
      self.class.new(
        root: @root,
        build_dir: build_dir || @build_dir,
        index_yaml_path: index_yaml_path || @index_yaml_path,
        build_index_path: build_index_path || (build_dir ? nil : @build_index_path)
      )
    end
  end
end
