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
