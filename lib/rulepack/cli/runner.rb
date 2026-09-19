# frozen_string_literal: true

require 'pathname'
require_relative '../common'
require_relative '../cli_parser'
require_relative '../result'
require_relative '../reporter'
require_relative '../emitter'
require_relative '../reporter/console_renderer'
require_relative '../reporter/jsonl_renderer'
require_relative '../catalog/remote_catalog'
require_relative '../lockfile'
require_relative 'commands'

module Rulepack
  module CLI
    # The CLI runner: single parse → table/local dispatch → render → exit code.
    #
    # Exit-code rule (global): success → 0, partial/failure → 1.
    # Render rule: narration reaches stdout via Emitter events (ConsoleRenderer
    # or JsonlRenderer); the Result payload renders once via Reporter —
    # except :jsonl, where the result is a single :result event line.
    class Runner
      def self.run(argv)
        new.run(argv)
      end

      def run(argv)
        if argv.include?('--timing')
          Rulepack::Logging.show_timing = true
          argv.delete('--timing')
        end

        command = argv.shift || 'help'
        command = PACMAN_ALIASES.fetch(command, command)
        argv.reject! { |a| PACMAN_ALIASES.key?(a) }

        options = Rulepack::CliParser.parse(argv)
        @format = options[:format] || :text
        # Hold the reference: renderers exist by their subscription side
        # effect. Without the ensure-unsubscribe, two Runner.run invocations
        # in one process (tests, embedding) stack duplicate renderers.
        # Dispatch AND render both stay inside the subscription window — for
        # :jsonl the final :result line is an event emitted by render.
        renderer = wire_renderer

        begin
          result = if command == 'help'
                     print_help
                     Rulepack::Result.new(status: :success)
                   elsif (row = COMMANDS[command])
                     execute_row(command, row, argv, options)
                   else
                     execute_local(command, argv, options)
                   end

          if result.is_a?(Integer) # local handlers may return bare exit codes
            result
          else
            render(result)
          end
        ensure
          renderer.unsubscribe! if renderer.respond_to?(:unsubscribe!)
        end
      rescue Rulepack::Error => e
        warn "Error: #{e.message}"
        1
      end

      private

      # ─── Table dispatch ─────────────────────────────────────────────────────

      def execute_row(command, row, argv, options)
        backend = Rulepack.const_get(row[:backend])
        if row[:raw_argv]
          backend.public_send(row[:method], argv)
        else
          options = row[:transform].call(options) if row[:transform]
          if (max = row[:max_positional]) && options[:positional]&.size.to_i > max
            return Rulepack::Result.new(status: :failure, errors: ["Too many positional arguments. Usage: #{row[:usage]}"])
          end
          backend.public_send(row[:method], options)
        end
      end

      # ─── Local commands ─────────────────────────────────────────────────────

      def execute_local(command, argv, options)
        case command
        when 'query'
          render_query_result(Rulepack::Query.run(argv))
        when 'list'
          render_query_result(Rulepack::Query.run(['list-packages'] + argv))
        when 'show'
          render_query_result(Rulepack::Query.run(['show'] + argv))
        when 'search'
          render_query_result(Rulepack::Query.run(['search'] + argv))
        when 'platforms'
          render_query_result(Rulepack::Query.run(['list-platforms']))
        when 'status'
          print_status
          0
        when 'catalog'
          catalog_path = Rulepack::Common.paths.build_dir.join('catalog.json')
          unless catalog_path.exist?
            return Rulepack::Result.new(status: :failure, errors: ['Catalog not found. Run `rulepack build` first.'])
          end
          puts catalog_path.read
          0
        when 'remote'
          dispatch_remote(argv)
        when 'lock'
          dispatch_lock
        when 'init-hooks'
          init_hooks
        else
          warn "\e[31m❌ Unknown command: '#{command}'\e[0m"
          if defined?(DidYouMean::SpellChecker)
            corrections = DidYouMean::SpellChecker.new(dictionary: VALID_COMMANDS).correct(command)
            warn "💡 Did you mean? \e[1mrulepack #{corrections.first}\e[0m" if corrections.any?
          end
          warn "\nRun \e[1mrulepack help\e[0m to see a list of available commands."
          1
        end
      end

      # Query arms used to let Query.run self-render; now the CLI renders.
      def render_query_result(result)
        render(result)
      end

      def dispatch_remote(argv)
        subcommand = argv.shift
        index_url = ENV['RULEPACK_REMOTE_INDEX'] || 'https://packages.rulepack.dev/index.json'

        case subcommand
        when 'search'
          term = argv.shift
          unless term
            warn 'Usage: rulepack remote search <term>'
            return 1
          end
          catalog = Rulepack::Catalog::RemoteCatalog.new(index_url)
          results = catalog.search(term)
          if results.empty?
            puts "No packages found for '#{term}'."
          else
            results.each do |pkg|
              puts "  #{pkg[:name]} (#{pkg[:version]}) — #{pkg[:description]}"
            end
          end
          0
        when 'list'
          catalog = Rulepack::Catalog::RemoteCatalog.new(index_url)
          catalog.list.each do |pkg|
            puts "  #{pkg[:name]} (#{pkg[:version]})"
          end
          0
        else
          warn 'Usage: rulepack remote <search|list> [args]'
          warn '  Set RULEPACK_REMOTE_INDEX to override the index URL.'
          1
        end
      rescue StandardError => e
        $stderr.puts "❌ Error: #{e.message}"
        1
      end

      def dispatch_lock
        lockfile = Rulepack::Lockfile.new
        entries = lockfile.entries
        if entries.empty?
          puts 'No lockfile entries. Run `rulepack lock --add <pkg> --version <ver>` to pin a package.'
        else
          puts "Lockfile entries (#{entries.size}):"
          entries.each do |name, entry|
            puts "  #{name} @ #{entry['version']}"
          end
        end
        0
      rescue StandardError => e
        $stderr.puts "❌ Error: #{e.message}"
        1
      end

      def print_status
        index = begin
          Rulepack::InstalledIndex.load
        rescue Rulepack::IndexNotFound, Rulepack::IndexCorrupt
          puts '  No index found. Run `rulepack build` first.'
          return
        end
        total = index[:packages]&.size || 0
        installed_platforms = {}
        index[:packages]&.each do |name, pkg|
          Array(pkg[:installed]).each do |rec|
            installed_platforms[rec[:platform]] ||= []
            installed_platforms[rec[:platform]] << name.to_s
          end
        end

        puts '📦 Rulepack Status'
        puts "  Total packages: #{total}"
        puts "  Platforms: #{installed_platforms.size}"
        puts
        installed_platforms.each do |platform, pkgs|
          puts "  #{platform}: #{pkgs.size} package(s)"
          pkgs.each { |p| puts "    - #{p}" }
        end
      end

      def init_hooks
        hook_dir = Rulepack::Common::RULEPACK_ROOT.join('.git', 'hooks')
        unless hook_dir.exist?
          puts '❌ Error: Not a git repository (.git/hooks directory not found).'
          return 1
        end

        pre_commit_hook = hook_dir.join('pre-commit')
        hook_content = <<~HOOK
          #!/bin/sh
          # Rulepack git pre-commit hook
          # Automatically runs PKGBUILD audit and drift verification before commits

          echo "🔍 Rulepack Pre-Commit Audit..."
          ruby bin/rulepack audit --strict
          AUDIT_STATUS=$?
          if [ $AUDIT_STATUS -ne 0 ]; then
            echo "❌ Rulepack pre-commit audit failed! Commit aborted."
            __RULEPACK_HOOK_EXIT__ 1
          fi

          echo "✓ Rulepack pre-commit audit passed."
          __RULEPACK_HOOK_EXIT__ 0
        HOOK

        hook_content = hook_content.gsub('__RULEPACK_HOOK_EXIT__', 'exit')
        File.write(pre_commit_hook, hook_content)
        File.chmod(0o755, pre_commit_hook)
        puts "✅ Git pre-commit hook installed successfully at #{pre_commit_hook.relative_path_from(Rulepack::Common::RULEPACK_ROOT)}"
        0
      end

      # ─── Rendering & exit code ──────────────────────────────────────────────

      def wire_renderer
        if @format == :jsonl
          Rulepack::Reporter::JsonlRenderer.new
        else
          Rulepack::Reporter::ConsoleRenderer.new
        end
      end

      def render(result)
        if @format == :jsonl
          # Stream narration already went out as events; the payload is one line.
          Rulepack::Emitter.emit(:result, payload: Rulepack::Reporter::JsonRenderer.sanitize(result.to_h))
        elsif result.failure?
          render_failure(result)
        else
          Rulepack::Reporter.print(result, format: @format)
        end
        result.success? ? 0 : 1
      end

      def render_failure(result)
        if @format == :text
          if result.messages.empty? && result.errors.empty?
            # Data-bearing failures (e.g. audit) render their full report via
            # the TextRenderer data branches instead of bare messages.
            Rulepack::Reporter.print(result, format: :text)
          else
            result.messages.each { |m| warn m }
            result.errors.each { |e| warn "Error: #{e}" }
          end
        else
          Rulepack::Reporter.print(result, format: @format)
        end
      end

      def print_help
        puts <<~HELP
          Rulepack — Single Source of Truth for Agent Rules & Skills

          Usage: rulepack <command> [options]

          Pacman-style commands:
            install <platform|package>   Install packages to a platform
            uninstall <platform>         Remove packages from a platform
            query <cmd>                  Query package database
            fix [platform]               Repair drift (index-disk reconciliation)

          Makepkg-style commands:
            build                        Build all packages (fetch → transform → artifacts)
            bump [pkg] [--apply]         Check upstream for new versions; --apply to auto-update

          Other commands:
            list                         List all packages
            show <pkgname>               Show package details
            search <tag>                 Search packages by tag
            status                       Show overall system status
            audit [options]              Audit all PKGBUILD descriptors for schema compliance
            check <platform>             Verify installed state matches index
            verify [platform]            Comprehensive index vs disk reconciliation
            outdated [platform]          Show installed packages older than the build
            catalog                      Show package catalog (JSON)
            platforms                    List all platforms
            remote search <term>         Search remote package index
            remote list                  List remote packages
            lock                         Show lockfile status
            init-hooks                   Install git pre-commit hook

          Global Flags:
            --timing                     Show operation timing
            --verbose, -v                Show debug output
            --format text|json|yaml|jsonl  Output format (jsonl = event stream)

          Install Flags (pacman-style):
            --target PLATFORM            Install single package to specific platform
            --needed                     Skip already-installed packages
            --dry-run                    Preview without changes
            --force, -f                  Allow downgrades (pacman -f/--force)

          Exit codes: 0 success, 1 partial (drift, some failures, outdated found) or failure.

          Examples:
            rulepack build && rulepack install opencode
            rulepack install rulepkg --target opencode --needed
            rulepack install opencode --dry-run       # dry-run preview
            rulepack uninstall opencode
            rulepack status
            rulepack search security
            rulepack verify opencode
            rulepack fix opencode
            rulepack outdated --target opencode
            rulepack audit --strict
        HELP
      end
    end
  end
end
