# Changelog

All notable changes to Rulepack will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Network failure integration tests for git clone timeouts and fetch failures
- API documentation in `docs/agents/API.md`

### Changed
- Consider extracting Rulepack::Common sub-modules (IO, Validator, Version) to reduce god module complexity

### Planned
- Add OptionParser for consistent CLI argument parsing across all commands
- Implement connection pooling for HTTP fetches to improve performance

## [1.0.0] - 2026-05-16

### Added
- **P9.1**: Security fix — replaced `YAML.load` with `YAML.safe_load` in test suite
- **P9**: `rulepack verify` command — index-disk reconciliation (detect drift + orphans)
- **P9**: `rulepack fix` command — automated repair (clear broken records, reinstall, orphan removal)
- **P6.3**: Configurable constants via environment variables
  - `RULEPACK_MAX_REDIRECTS` (default: 3)
  - `RULEPACK_READ_TIMEOUT` (default: 30)
  - `RULEPACK_CACHE_DIR` (default: "cache")
  - `RULEPACK_GIT_DEPTH` (default: 1)
  - `RULEPACK_LOG_LEVEL` (default: "info")
- **P6.2**: Platform registry caching — 3x fewer YAML reads per install run
- **P6.1**: Performance monitoring with `--timing` flag
- **P5.5**: Actionable error messages with fix suggestions
- **P5.4**: Shared `project_root_for` method to eliminate duplication
- **P5.3**: Removed unnecessary wrapper functions in build.rb
- **P5.2**: Unified logging across all modules
- **P5.1**: Eliminated duplicate cache functions (147 lines of dead code removed)
- **P1.2**: Git path traversal validation
- **P1.1**: Transaction atomicity & index write coalescing
- **P0.4**: Content validation (empty file checks)
- **P0.3**: Pre-install impact analysis (--dry-run improvements)
- **P0.2**: Platform prerequisite validation
- **P0.1**: Single entry point CLI (`bin/rulepack`)

### Security
- Replaced unsafe `YAML.load` with `YAML.safe_load` in test files
- All `system()` calls use array form to prevent command injection
- Path traversal protection for git sources

### Documentation
- 8 comprehensive guides in `docs/agents/`
- Per-platform documentation for 14 agent platforms
- Architecture, reference, usage, and transforms documentation

## [0.9.0] - 2026-05-14

### Added
- Initial public release of Rulepack
- Support for 14 agent platforms (opencode, cursor, claude-code, etc.)
- PKGBUILD-inspired package management for AI agent rules/skills
- Build, install, uninstall, query, and verify commands
- Comprehensive caching and validation layer
- Skill-bundle support with manifest generation
- Transform and translation pipeline

[Unreleased]: https://github.com/your-org/rulepack/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/your-org/rulepack/releases/tag/v1.0.0
[0.9.0]: https://github.com/your-org/rulepack/releases/tag/v0.9.0
