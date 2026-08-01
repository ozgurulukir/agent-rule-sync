# frozen_string_literal: true

# Typed error hierarchy for Rulepack.
#
# Lives in the LIBRARY (not bin/rulepack) so any consumer — CLI, test suite,
# gem user, future MCP server — can rely on Rulepack::Error being defined the
# moment any Rulepack code is loaded.
#
# Rescue Rulepack::Error to catch every Rulepack-originated failure.
# Rescue a subclass to dispatch on a specific cause without parsing messages.
module Rulepack
  # Base class for all Rulepack errors.
  class Error < StandardError; end

  # ── Configuration / user-input errors ────────────────────────────────────
  class ConfigError < Error; end

  # CLI option parsing failures (raised by CliParser).
  class CliError < ConfigError; end

  # A flag that requires a value was given none (e.g. `--target` with no arg).
  class MissingOptionValue < CliError; end

  # A flag was given a value outside its allowed set (e.g. `--format xml`).
  class InvalidOptionValue < CliError; end

  # PKGBUILD descriptor errors.
  class PkgbuildError < ConfigError; end
  class PkgbuildNotFound < PkgbuildError; end
  class InvalidPkgbuild < PkgbuildError; end

  # ── Security errors ──────────────────────────────────────────────────────
  class SecurityError < Error; end
  class PathTraversalError < SecurityError; end

  # ── Runtime / state errors ───────────────────────────────────────────────
  class StateError < Error; end
  class IndexNotFound < StateError; end
  class BuildIndexNotFound < StateError; end
  class UnknownPlatform < StateError; end
end
