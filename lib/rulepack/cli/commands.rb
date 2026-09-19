# frozen_string_literal: true

# CLI dispatch table — the single registry mapping command names to backends.
#
# Rows come in two shapes:
#   { backend:, method:, transform:, max_positional:, usage:, raw_argv: }
#     — Runner calls backend.public_send(method, options) (the parsed CliParser
#       hash), or (argv) when raw_argv: true (commands with private flags).
#
# PACMAN_ALIASES is applied by the Runner before dispatch; backends never
# see the raw flags.

module Rulepack
  module CLI
    PACMAN_ALIASES = {
      '-S' => 'install', '-R' => 'uninstall', '-Qk' => 'verify',
      '-F' => 'fix', '-Q' => 'query'
    }.freeze

    COMMANDS = {
      'build' => {
        backend: 'BuildAll', method: :run,
        description: 'Build all packages (fetch → transform → artifacts) and aggregate vendor skills'
      },
      'install' => {
        backend: 'Install', method: :dispatch, max_positional: 1,
        usage: 'rulepack install [package] --target <platform|all>',
        description: 'Install packages to a platform'
      },
      'uninstall' => {
        backend: 'Uninstaller', method: :dispatch, max_positional: 1,
        usage: 'rulepack uninstall [package] --target <platform|all>',
        description: 'Remove packages from a platform'
      },
      'verify' => {
        backend: 'Verify', method: :check,
        description: 'Comprehensive index vs disk reconciliation'
      },
      'fix' => {
        backend: 'Fix', method: :run,
        description: 'Repair drift (index-disk reconciliation)'
      },
      'outdated' => {
        backend: 'Outdated', method: :run,
        description: 'Show installed packages older than the build'
      },
      'audit' => {
        backend: 'Audit', method: :run,
        description: 'Audit all PKGBUILD descriptors for schema compliance'
      },
      'bump' => {
        backend: 'Bump', method: :run, max_positional: 1,
        usage: 'rulepack bump [pkg] [--apply]',
        description: 'Check upstream for new versions; --apply to auto-update'
      },
      'check' => {
        backend: 'Install', method: :dispatch,
        transform: lambda { |opts|
          # check <platform> positional maps to --target
          target = opts[:target] || opts[:positional]&.first
          opts.merge(check_mode: true, target: target, package_name: nil, positional: [])
        },
        description: 'Verify installed state matches index'
      }
    }.freeze

    # Commands handled directly by the Runner (forwarding, local files, help).
    LOCAL_COMMANDS = %w[query list show search status catalog platforms remote lock init-hooks help].freeze

    VALID_COMMANDS = (COMMANDS.keys + LOCAL_COMMANDS).freeze
  end
end
