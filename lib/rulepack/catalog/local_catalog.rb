# frozen_string_literal: true

require_relative 'source_repository'

# Local catalog — wraps existing Source/Cache primitives.
#
# This is the default implementation, preserving current behavior.
# It delegates to Rulepack::Common (which delegates to Source and Cache).
module Rulepack
  module Catalog
    class LocalCatalog < SourceRepository
      def fetch(source_cfg, pkg_dir: nil)
        case source_cfg[:type]
        when 'local'
          content, sha256 = Rulepack::Common.read_source(source_cfg, pkg_dir)
          SourceResult.new(content: content, sha256: sha256, source_dir: nil)
        when 'url'
          content, sha256 = Rulepack::Common.cached_fetch_url(source_cfg[:url], source_cfg[:sha256])
          SourceResult.new(content: content, sha256: sha256, source_dir: nil)
        when 'git'
          git_url = source_cfg[:url]
          git_ref = source_cfg[:ref] || 'main'
          git_path = Pathname.new(source_cfg[:path] || '.')
          git_depth = source_cfg[:depth] || 1
          content, sha256 = Rulepack::Common.cached_fetch_git_file(git_url, git_ref, git_path, depth: git_depth)
          SourceResult.new(content: content, sha256: sha256, source_dir: nil)
        else
          raise Rulepack::ConfigError, "Unsupported source type: #{source_cfg[:type]}"
        end
      end

      def directory(source_cfg, pkg_dir: nil)
        case source_cfg[:type]
        when 'local'
          src_path = source_cfg[:path]
          dir = if src_path.start_with?('/') || src_path.start_with?('~')
                  Pathname.new(Rulepack::Common.expand_user_path(src_path))
                else
                  pkg_dir.join(src_path)
                end
          dir.cleanpath
        when 'git'
          git_url = source_cfg[:url]
          git_ref = source_cfg[:ref] || 'main'
          git_path = Pathname.new(source_cfg[:path] || '.')
          git_depth = source_cfg[:depth] || 1
          cached_dir, commit_hash = Rulepack::Common.cached_fetch_git_dir(git_url, git_ref, git_path,
                                                                         depth: git_depth)
          persistent_dir = Rulepack::Common.build_dir.join('git-sources', File.basename(git_url).sub(/\.git$/, ''))
          FileUtils.rm_rf(persistent_dir)
          FileUtils.mkpath(persistent_dir.parent)
          FileUtils.cp_r(cached_dir, persistent_dir)
          persistent_dir
        else
          raise Rulepack::ConfigError, "Directory fetch not supported for source type: #{source_cfg[:type]}"
        end
      end
    end
  end
end
