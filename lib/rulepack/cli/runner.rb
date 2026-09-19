# frozen_string_literal: true

require 'pathname'
require_relative '../common'
require_relative '../cli_parser'
require_relative '../result'
require_relative '../reporter'
require_relative '../emitter'
require_relative '../reporter/console_renderer'
require_relative '../reporter/jsonl_renderer'
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
                     unknown_result(command)
                   end

          render(result)
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
        options = options.merge(row[:defaults]) if row[:defaults]
        options = apply_positional(row, options) if row[:positional]
        if (max = row[:max_positional]) && options[:positional]&.size.to_i > max
          return Rulepack::Result.new(status: :failure, errors: ["Too many positional arguments. Usage: #{row[:usage]}"])
        end

        if row[:call] == :args
          # Scalar-API rows (Query data methods). ArgumentError converts to a
          # failure Result so a missing positional renders like any other
          # usage error ("Missing package name", "Missing search keyword").
          begin
            backend.public_send(row[:method], *row[:args].map { |key| options[key] })
          rescue ArgumentError => e
            Rulepack::Result.new(status: :failure, errors: [e.message])
          end
        else
          backend.public_send(row[:method], options)
        end
      end

      # positional: :target — the first CLI positional is a platform, not a
      # package (check, outdated). CliParser already mapped it to package_name;
      # the mapping is moved to target and the package resolution disabled.
      def apply_positional(row, options)
        options[:target] ||= options[:positional]&.first
        options[:package_name] = nil
        options
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

      def unknown_result(command)
        messages = ["❌ Unknown command: '#{command}'"]
        if defined?(DidYouMean::SpellChecker)
          corrections = DidYouMean::SpellChecker.new(dictionary: VALID_COMMANDS).correct(command)
          messages << "💡 Did you mean? rulepack #{corrections.first}" if corrections.any?
        end
        messages << "\nRun rulepack help to see a list of available commands."
        Rulepack::Result.new(status: :failure, messages: messages)
      end

      def print_help
        puts Rulepack::CLI::Help.text
      end
    end
  end
end
