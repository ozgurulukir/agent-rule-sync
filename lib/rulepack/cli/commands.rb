# frozen_string_literal: true

# Command registry — maps CLI verbs to their backend module and metadata.
#
# Each entry specifies:
#   :backend   — the module to call (responds to .run or .dispatch)
#   :method    — the method name on the backend (default: :run)
#   :renderer  — how to render the result (:reporter or :direct)
#   :needs_target — whether --target is required
#   :needs_project — whether --project is required
#   :description — one-line help text
#
# The CLI dispatcher (bin/rulepack) uses this table instead of a case/when.

module Rulepack
  module CLI
    COMMANDS = {
      'build' => {
        backend: Rulepack::Build,
        method: :run,
        renderer: :reporter,
        needs_target: false,
        needs_project: false,
        description: 'Build all packages (fetch → transform → artifacts)'
      },
      'install' => {
        backend: Rulepack::Install,
        method: :dispatch,
        renderer: :reporter,
        needs_target: true,
        needs_project: false,
        description: 'Install packages to a platform'
      },
      'uninstall' => {
        backend: Rulepack::Uninstaller,
        method: :dispatch,
        renderer: :reporter,
        needs_target: true,
        needs_project: false,
        description: 'Remove packages from a platform'
      },
      'verify' => {
        backend: Rulepack::Verify,
        method: :run,
        renderer: :reporter,
        needs_target: true,
        needs_project: false,
        description: 'Comprehensive index vs disk reconciliation'
      },
      'fix' => {
        backend: Rulepack::Fix,
        method: :run,
        renderer: :reporter,
        needs_target: false,
        needs_project: false,
        description: 'Repair drift (index-disk reconciliation)'
      },
      'outdated' => {
        backend: Rulepack::Outdated,
        method: :run,
        renderer: :reporter,
        needs_target: false,
        needs_project: false,
        description: 'Show installed packages older than the build'
      },
      'audit' => {
        backend: Rulepack::Audit,
        method: :run,
        renderer: :direct,
        needs_target: false,
        needs_project: false,
        description: 'Audit all PKGBUILD descriptors for schema compliance'
      },
      'query' => {
        backend: Rulepack::Query,
        method: :run,
        renderer: :direct,
        needs_target: false,
        needs_project: false,
        description: 'Query package database'
      },
      'bump' => {
        backend: Rulepack::Bump,
        method: :run,
        renderer: :direct,
        needs_target: false,
        needs_project: false,
        description: 'Check upstream for new versions; --apply to auto-update'
      }
    }.freeze

    # Commands that are handled directly by the CLI module (no backend module).
    LOCAL_COMMANDS = %w[list show search status catalog platforms init-hooks help].freeze
  end
end
