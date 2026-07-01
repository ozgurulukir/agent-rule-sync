# frozen_string_literal: true

module Rulepack
  module Reporter
    # Human-readable text rendering for Rulepack::Result objects.
    # This is the default output format for the CLI.
    module TextRenderer
      module_function

      def print(result, out: $stdout)
        result.messages.each { |m| out.puts(m) }

        case result.data
        when Hash then render_hash(result.data, out: out)
        when Array then result.data.each { |item| out.puts(item) }
        end

        result.errors.each { |e| out.puts("Error: #{e}") }
      end

      def render_hash(data, out:)
        return unless data.is_a?(Hash)

        if data[:platform_id] && data.key?(:items) && !data.key?(:ok)
          render_platform_items(data, out: out)
        elsif data.key?(:packages)
          render_packages(data, out: out)
        elsif data.key?(:platforms) && data[:platforms].is_a?(Array)
          render_verify_platforms(data, out: out)
        elsif data.key?(:platforms)
          render_platform_registry(data, out: out)
        elsif data.key?(:package)
          render_package(data, out: out)
        elsif data.key?(:results)
          render_search_results(data, out: out)
        elsif data.key?(:orphans)
          render_orphans(data, out: out)
        elsif data.key?(:dependencies)
          render_dependencies(data, out: out)
        elsif data.key?(:providers)
          render_providers(data, out: out)
        elsif data.key?(:issues)
          render_issues(data, out: out)
        elsif data.key?(:packages_built)
          render_build(data, out: out)
        elsif data.key?(:outdated) && data.key?(:available)
          render_outdated(data, out: out)
        end
      end

      def render_platform_items(data, out:)
        platform_id = data[:platform_id]
        items = Array(data[:items])

        return out.puts("📥 No packages installed on #{platform_id}.") if items.empty?

        out.puts("📥 Installed items on #{platform_id}:") unless already_printed_header?(data)
        items.each do |item|
          source_tag = item[:source] == :manual ? ' [manual]' : ''
          icon = status_icon(item[:status])
          out.puts("  #{icon} #{item[:name]}#{source_tag}")
          out.puts("    Type: #{item[:type]} | Path: #{item[:path]}") if item[:path]
        end
        out.puts("  Total: #{items.size} item(s)")
      end

      def render_packages(data, out:)
        packages = data[:packages] || {}
        out.puts("📦 Packages (#{packages.size}):")
        packages.each do |name, pkg|
          installed = Array(pkg[:installed]).map { |r| r[:platform] }.uniq
          version = Rulepack::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver], pkg[:pkgrel] || 1)
          out.puts("  #{name} (#{version}) [#{pkg[:status] || 'stable'}]")
          out.puts("    Targets: #{Array(pkg[:available_targets]).join(', ')}")
          out.puts("    Installed: #{installed.empty? ? 'none' : installed.join(', ')}")
          out.puts("    Tags: #{Array(pkg[:tags]).join(', ')}")
          out.puts
        end
      end

      def render_platform_registry(data, out:)
        platforms = data[:platforms] || {}
        out.puts("🎯 Platforms (#{platforms.size}):")
        platforms.each do |id, cfg|
          out.puts("  #{id} (#{cfg[:display_name] || id})")
          out.puts("    Type: #{cfg[:type]} | Scope: #{cfg[:scope] || 'user'}")
          out.puts("    Base: #{cfg[:base_path]}")
          out.puts
        end
      end

      def render_verify_platforms(data, out:)
        platforms = data[:platforms] || []
        platforms.each do |p|
          out.puts("\n── #{p[:platform_id]} ──")
          out.puts(p[:message])
          p[:items].each { |item| item[:messages].each { |m| out.puts(m) } }
          p[:orphans].each { |o| out.puts("  ? ORPHAN: #{o[:path]}") }
        end
      end

      def render_package(data, out:)
        pkg = data[:package]
        return unless pkg

        version = Rulepack::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver], pkg[:pkgrel] || 1)
        installed = Array(pkg[:installed]).map { |r| r[:platform] }.uniq
        out.puts("  Version: #{version}")
        out.puts("  Description: #{pkg[:pkgdesc]}")
        out.puts("  Status: #{pkg[:status] || 'stable'}")
        out.puts("  Targets: #{Array(pkg[:available_targets]).join(', ')}")
        out.puts("  Installed: #{installed.empty? ? 'none' : installed.join(', ')}")
        out.puts("  Tags: #{Array(pkg[:tags]).join(', ')}")
        out.puts("  Dependencies: #{Array(pkg[:dependencies]).join(', ') || 'none'}")
        out.puts("  Conflicts: #{Array(pkg[:conflicts]).join(', ') || 'none'}")
        out.puts("  Provides: #{Array(pkg[:provides]).join(', ') || 'none'}")
      end

      def render_search_results(data, out:)
        results = data[:results] || {}
        results.each do |name, pkg|
          version = Rulepack::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver], pkg[:pkgrel] || 1)
          out.puts("  #{name} (#{version}): #{pkg[:pkgdesc]}")
        end
      end

      def render_orphans(data, out:)
        orphans = data[:orphans] || []
        orphans.each do |o|
          out.puts("  • #{o[:name]} on #{o[:platform]} (output: #{o[:output]})")
        end
      end

      def render_dependencies(data, out:)
        deps = data[:dependencies] || []
        deps.each { |d| out.puts("  • #{d}") }
      end

      def render_providers(data, out:)
        providers = data[:providers] || {}
        providers.each do |name, pkg|
          version = Rulepack::Common.format_version(pkg[:epoch] || 0, pkg[:pkgver], pkg[:pkgrel] || 1)
          out.puts("  • #{name} (#{version})")
        end
      end

      def render_issues(data, out:)
        issues = data[:issues] || []
        issues.each { |i| out.puts("  - #{i}") }
      end

      def render_build(data, out:)
        built = data[:packages_built] || []
        failed = data[:packages_failed] || []
        out.puts("  Built: #{built.size} package(s)")
        out.puts("  Failed: #{failed.size} package(s)") if failed.any?
      end

      def render_outdated(data, out:)
        outdated = data[:outdated] || []
        available = data[:available] || []
        out.puts("  Checked: #{Array(data[:targets]).join(', ')}")
        if outdated.any?
          out.puts("  Outdated (#{outdated.size}):")
          outdated.each { |o| out.puts("    • #{o[:pkgname]} on #{o[:platform]}: #{o[:installed_version]} → #{o[:build_version]}") }
        end
        if available.any?
          out.puts("  Available (#{available.size}):")
          available.each { |a| out.puts("    • #{a[:pkgname]} on #{a[:platform]} (#{a[:build_version]})") }
        end
      end

      def status_icon(status)
        case status
        when :ok then '✓'
        when :drift then '⚠'
        when :missing then '✗'
        when :orphan then '?'
        else '•'
        end
      end

      # Avoid duplicate header when the message already printed it.
      def already_printed_header?(_data)
        false
      end
    end
  end
end
