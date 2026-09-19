# frozen_string_literal: true

require_relative 'commands'

module Rulepack
  module CLI
    # Help — the command reference, derived from the dispatch table. Group
    # sections render rows in table insertion order, so a new row is
    # automatically documented; the flags/examples tail is static because it
    # documents parser vocabulary, not rows. Description alignment uses the
    # global synopsis width so all groups share one column.
    module Help
      GROUP_TITLES = [
        ['Pacman-style commands:', :pacman],
        ['Makepkg-style commands:', :makepkg],
        ['Other commands:', :other]
      ].freeze

      STATIC_TAIL = <<~TAIL
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
      TAIL

      module_function

      def entries_for(row)
        row[:help_lines] || [{ synopsis: row[:synopsis], description: row[:description] }]
      end

      def text
        entries = COMMANDS.flat_map { |_name, row| entries_for(row) }
        width = entries.map { |e| e[:synopsis].size }.max

        lines = [
          'Rulepack — Single Source of Truth for Agent Rules & Skills',
          '',
          'Usage: rulepack <command> [options]'
        ]
        GROUP_TITLES.each do |title, group|
          lines << ''
          lines << title
          COMMANDS.each_value do |row|
            next if row[:group] != group

            entries_for(row).each do |entry|
              lines << format("  %-#{width}s   %s", entry[:synopsis], entry[:description])
            end
          end
        end
        lines << '' << STATIC_TAIL
        lines.join("\n")
      end
    end
  end
end
