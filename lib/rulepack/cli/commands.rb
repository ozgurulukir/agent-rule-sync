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
        backend: 'Outdated', method: :run, positional: :target, max_positional: 1,
        usage: 'rulepack outdated [platform]',
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
        defaults: { check_mode: true }, positional: :target, max_positional: 1,
        usage: 'rulepack check <platform>',
        description: 'Verify installed state matches index'
      },
      'query' => {
        backend: 'Query', method: :run_subcommand,
        usage: 'rulepack query <subcommand> [args]',
        description: 'Query package database'
      },
      'list' => {
        backend: 'Query', method: :packages, call: :args, args: [], max_positional: 0,
        usage: 'rulepack list',
        description: 'List all packages'
      },
      'show' => {
        backend: 'Query', method: :show, call: :args, args: [:package_name], max_positional: 1,
        usage: 'rulepack show <pkgname>',
        description: 'Show package details'
      },
      'search' => {
        backend: 'Query', method: :search, call: :args, args: [:package_name], max_positional: 1,
        usage: 'rulepack search <tag>',
        description: 'Search packages by tag'
      },
      'platforms' => {
        backend: 'Query', method: :platforms, call: :args, args: [], max_positional: 0,
        usage: 'rulepack platforms',
        description: 'List all platforms'
      },
      'status' => {
        backend: 'Status', method: :run,
        description: 'Show overall system status'
      },
      'catalog' => {
        backend: 'BuildCatalog', method: :run,
        description: 'Show package catalog (JSON)'
      },
      'remote' => {
        backend: 'Remote', method: :run, max_positional: 2,
        usage: 'rulepack remote <search|list> [args]',
        description: 'Search remote package index'
      },
      'lock' => {
        backend: 'Lock', method: :run,
        description: 'Show lockfile status'
      },
      'init-hooks' => {
        backend: 'InitHooks', method: :run,
        description: 'Install git pre-commit hook'
      }
    }.freeze

    # Commands handled directly by the Runner (help).
    LOCAL_COMMANDS = %w[help].freeze

    VALID_COMMANDS = (COMMANDS.keys + LOCAL_COMMANDS).freeze
  end
end
