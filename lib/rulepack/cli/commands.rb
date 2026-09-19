# frozen_string_literal: true

# CLI dispatch table — the single registry mapping command names to backends.
#
# Every user-facing command is exactly one fully-declared row; the Runner is
# dumb: parse → alias remap → look up → execute → render → exit code.
#
# Row shape:
#   backend:        Rulepack module (const_get by Runner)
#   method:         backend method symbol
#   call:           :options (default) — backend.public_send(method, options),
#                   the parsed CliParser hash
#                   :args — backend.public_send(method, *args.map { |k| options[k] })
#                   for scalar-API backends (Query data methods)
#   args:           option keys mapped to scalar parameters (call: :args)
#   defaults:       option overrides merged before dispatch (e.g. check_mode)
#   positional:     :target — the first CLI positional is a platform, routed
#                   to options[:target] (check, outdated); CliParser's default
#                   package_name mapping is cleared
#   max_positional: boundary guard → "Too many positional arguments. Usage: …"
#   group:          :pacman | :makepkg | :other — drives Help sections
#   synopsis:       help line's command column
#   usage:          live usage line (positional-boundary errors)
#   description:    live help description
#   help_lines:     multi-line help entries (remote search/list)
#
# Row insertion order is Help order within each group. PACMAN_ALIASES is
# applied by the Runner before dispatch; backends never see the raw flags.

module Rulepack
  module CLI
    PACMAN_ALIASES = {
      '-S' => 'install', '-R' => 'uninstall', '-Qk' => 'verify',
      '-F' => 'fix', '-Q' => 'query'
    }.freeze

    COMMANDS = {
      # ── Pacman-style ──────────────────────────────────────────────────────────
      'install' => {
        backend: 'Install', method: :dispatch, max_positional: 1, group: :pacman,
        synopsis: 'install <platform|package>',
        usage: 'rulepack install [package] --target <platform|all>',
        description: 'Install packages to a platform'
      },
      'uninstall' => {
        backend: 'Uninstaller', method: :dispatch, max_positional: 1, group: :pacman,
        synopsis: 'uninstall <platform>',
        usage: 'rulepack uninstall [package] --target <platform|all>',
        description: 'Remove packages from a platform'
      },
      'query' => {
        backend: 'Query', method: :run_subcommand, group: :pacman,
        synopsis: 'query <cmd>',
        usage: 'rulepack query <subcommand> [args]',
        description: 'Query package database'
      },
      'fix' => {
        backend: 'Fix', method: :run, group: :pacman,
        synopsis: 'fix [platform]',
        usage: 'rulepack fix [pkg] --target <platform|all> [--auto]',
        description: 'Repair drift (index-disk reconciliation)'
      },

      # ── Makepkg-style ─────────────────────────────────────────────────────────
      'build' => {
        backend: 'BuildAll', method: :run, group: :makepkg,
        synopsis: 'build',
        usage: 'rulepack build [--target <plat[,plat]>]',
        description: 'Build all packages (fetch → transform → artifacts)'
      },
      'bump' => {
        backend: 'Bump', method: :run, max_positional: 1, group: :makepkg,
        synopsis: 'bump [pkg] [--apply]',
        usage: 'rulepack bump [pkg] [--apply]',
        description: 'Check upstream for new versions; --apply to auto-update'
      },

      # ── Other ─────────────────────────────────────────────────────────────────
      'list' => {
        backend: 'Query', method: :packages, call: :args, args: [], max_positional: 0, group: :other,
        synopsis: 'list',
        usage: 'rulepack list',
        description: 'List all packages'
      },
      'show' => {
        backend: 'Query', method: :show, call: :args, args: [:package_name], max_positional: 1, group: :other,
        synopsis: 'show <pkgname>',
        usage: 'rulepack show <pkgname>',
        description: 'Show package details'
      },
      'search' => {
        backend: 'Query', method: :search, call: :args, args: [:package_name], max_positional: 1, group: :other,
        synopsis: 'search <tag>',
        usage: 'rulepack search <tag>',
        description: 'Search packages by tag'
      },
      'status' => {
        backend: 'Status', method: :run, max_positional: 0, group: :other,
        synopsis: 'status',
        usage: 'rulepack status',
        description: 'Show overall system status'
      },
      'audit' => {
        backend: 'Audit', method: :run, max_positional: 0, group: :other,
        synopsis: 'audit [options]',
        usage: 'rulepack audit [--strict] [--target <platform>]',
        description: 'Audit all PKGBUILD descriptors for schema compliance'
      },
      'check' => {
        backend: 'Install', method: :dispatch,
        defaults: { check_mode: true }, positional: :target, max_positional: 1, group: :other,
        synopsis: 'check <platform>',
        usage: 'rulepack check <platform>',
        description: 'Verify installed state matches index'
      },
      'verify' => {
        backend: 'Verify', method: :check, max_positional: 1, group: :other,
        synopsis: 'verify [platform]',
        usage: 'rulepack verify [package] --target <platform|all>',
        description: 'Comprehensive index vs disk reconciliation'
      },
      'outdated' => {
        backend: 'Outdated', method: :run, positional: :target, max_positional: 1, group: :other,
        synopsis: 'outdated [platform]',
        usage: 'rulepack outdated [platform]',
        description: 'Show installed packages older than the build'
      },
      'catalog' => {
        backend: 'BuildCatalog', method: :run, max_positional: 0, group: :other,
        synopsis: 'catalog',
        usage: 'rulepack catalog',
        description: 'Show package catalog (JSON)'
      },
      'platforms' => {
        backend: 'Query', method: :platforms, call: :args, args: [], max_positional: 0, group: :other,
        synopsis: 'platforms',
        usage: 'rulepack platforms',
        description: 'List all platforms'
      },
      'remote' => {
        backend: 'Remote', method: :run, max_positional: 2, group: :other,
        usage: 'rulepack remote <search|list> [args]',
        help_lines: [
          { synopsis: 'remote search <term>', description: 'Search remote package index' },
          { synopsis: 'remote list', description: 'List remote packages' }
        ]
      },
      'lock' => {
        backend: 'Lock', method: :run, max_positional: 0, group: :other,
        synopsis: 'lock',
        usage: 'rulepack lock',
        description: 'Show lockfile status'
      },
      'init-hooks' => {
        backend: 'InitHooks', method: :run, max_positional: 0, group: :other,
        synopsis: 'init-hooks',
        usage: 'rulepack init-hooks',
        description: 'Install git pre-commit hook'
      }
    }.freeze

    # Commands handled directly by the Runner (help).
    LOCAL_COMMANDS = %w[help].freeze

    VALID_COMMANDS = (COMMANDS.keys + LOCAL_COMMANDS).freeze
  end
end
