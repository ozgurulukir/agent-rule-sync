# Rulepack — PKGBUILD-based Agent Rule Manager

_An Elegant Tool For A More Civilized Age_

Package-based rule management for AI coding agents, inspired by PKGBUILD/pacman.

> **For developers**: See [AGENTS.md](AGENTS.md) for architecture, creating packages, pipeline details, testing, and project status.

## What Is This?

A **PKGBUILD-inspired package manager** for agent rules and skills:

- **Package format**: Each rule/skill is a package with a `PKGBUILD` descriptor
- **Build pipeline**: 4-stage sequential pipeline (Fetch → Auto-derive Translator → Dynamic Schema Engine → Transformer) mapping dynamically via registry formatting profiles
- **Multi-platform**: One source → multiple target platforms (OpenCode, Crush, Gemini CLI, etc.)
- **Change detection**: SHA256 checksums track source and built artifacts
- **Index database**: `data/index.yaml` tracks package state, versions, and installations

## Quick Start

```bash
# Build all packages
bin/rulepack build

# Build with timing info
bin/rulepack build --timing

# Check upstream for new versions (git-sourced packages)
bin/rulepack bump                                  # Check all
bin/rulepack bump vibe-security                    # Check single
bin/rulepack bump --apply                          # Auto-update + rebuild

# Install to a user-level platform (Zero Assumptions: target is mandatory)
bin/rulepack install --target opencode              # Real install (all built packages)
bin/rulepack install memory --target opencode       # Real install of a single package (exact match)
bin/rulepack install memory -t opencode --dry-run   # Dry run preview

# Pacman flag shortcut equivalents (as options on subcommands)
bin/rulepack install -S --target opencode            # Equivalent to install --target opencode
bin/rulepack install -S memory -t opencode           # Equivalent to install memory -t opencode

# Install to a project-level platform (Target and Project are mandatory)
bin/rulepack install --target cursor --project .    # Install to current project
bin/rulepack install memory -t cursor --project /path/to/project

# Global Sync (Install all packages to all user-level platforms)
bin/rulepack install --target all

# Rules installation mode (--rules-to)
bin/rulepack install -t opencode --rules-to rules_dir    # (Default) Symlinks rules to rules/ directory
bin/rulepack install -t opencode --rules-to rules_file   # Appends rules into AGENTS.md instead

# Verify installed packages and integrity (verify or -Qk)
bin/rulepack verify --target opencode               # Verify all packages on opencode
bin/rulepack verify -Qk memory -t opencode           # Verify single package on opencode

# Repair drift (fix or -F)
bin/rulepack fix --target opencode                  # Repair any modified/missing files
bin/rulepack fix -F memory -t opencode               # Repair single package

# Check for outdated installs or packages newer than your install
bin/rulepack outdated -t opencode                   # Compare installed versions to build index
bin/rulepack outdated -t opencode --format json     # Machine-readable

# Audit package descriptors for integrity & platforms coverage
bin/rulepack audit                                  # Audit all packages (schema, local sources, platforms)
bin/rulepack audit --strict                         # Strict audit (requires targets for all 14 platforms)
bin/rulepack audit --target opencode                # Target-specific platform check
bin/rulepack audit --format json                    # Machine-readable output

# Uninstall from platforms (uninstall or -R)
bin/rulepack uninstall --target opencode            # Uninstall all packages from opencode
bin/rulepack uninstall -R memory -t cursor --project . # Uninstall single package from cursor project

# Query database (query)
bin/rulepack query show memory                      # Show package details
bin/rulepack query search security                  # Search packages by tag or term
bin/rulepack query installed opencode               # Show installed packages (and manual/orphan items)

# Install Git pre-commit hooks
bin/rulepack init-hooks                             # Audits PKGBUILDs automatically on commit
```

## Typical Workflow

A normal day with Rulepack looks like this:

```bash
# 1. Build the current package set
bin/rulepack build

# 2. Install or refresh rules/skills on your platform(s)
bin/rulepack install --target opencode

# 3. Check what you have installed
bin/rulepack query installed opencode

# 4. Detect drift, missing files, or manual changes
bin/rulepack verify --target opencode

# 5. If anything drifted, repair it
bin/rulepack fix --target opencode

# 6. Check if newer package versions exist in the build
bin/rulepack outdated -t opencode
```

For git-sourced packages, periodically check upstream:

```bash
bin/rulepack bump              # See what's new
bin/rulepack bump --apply      # Update PKGBUILD versions and rebuild
```

## Project Structure

```
rulepack/
├── bin/rulepack              # CLI entry point
├── lib/rulepack/             # Library modules (47 .rb files)
│   ├── common.rb             # Facade — delegates to submodules (70 LOC)
│   ├── installer.rb          # Installer orchestrator (split via InstallPlan + InstallExecute)
│   ├── cli_parser.rb         # Unified command-line argument parser
│   ├── build.rb              # Build orchestrator (~100 LOC → delegates to 3 submodules)
│   ├── build_loader.rb       # PKGBUILD discovery, loading, and validation
│   ├── build_per_pkg.rb      # Per-package fetch + pipeline + checksum loop
│   ├── build_writer.rb       # Writes build/index.yaml and build/catalog.json
│   ├── build_pipeline.rb     # 4-stage sequential build pipeline state machine
│   ├── schema_engine.rb      # Centralized dynamic formatting and emoji/bullet normalizer
│   ├── schema_migration.rb   # data/index.yaml version-migration (idempotent while-loop, v1→v2→v3)
│   ├── cache.rb              # Build cache with LRU eviction and configurable MB limit
│   ├── verify.rb             # Verification/drift namespace
│   ├── fix.rb                # Drift self-healing namespace
│   ├── uninstaller.rb        # Surgical uninstallation namespace
│   ├── query.rb              # Frozen COMMANDS dispatch table; 10 cmds + 10 aliases via send()
│   ├── lib/                  # Decomposed installer components
│   │   ├── transaction.rb    # Backups, journals, and atomic rollbacks
│   │   ├── install_handlers.rb # Link/copy/marker append low-level handlers
│   │   ├── skill_bundle.rb   # Sub-skills selection, caching, and manifest audits
│   │   └── tui_selector.rb   # Multi-select terminal draws and keyboard prompts
│   └── ... (logging, backup, version, source, transform, validation,
│             platform, aggregate, translate, generate-catalog,
│             install CLI, uninstall CLI, fix CLI, outdated, reporter)
├── data/                     # Single Source of Truth (SSOT)
│   ├── packages/             # Package definitions (19 packages)
│   ├── registry/platforms.yaml  # 14 platform configurations
│   ├── platforms/            # Format profiles (informational)
│   ├── translators/          # Custom translation layers (6 translators)
│   ├── transformers/         # Custom transform filters
│   └── index.yaml            # Master package database (schema v3.0)
├── build/                    # Build artifacts (generated)
├── test/                     # Test suite (331 runs, 1017 assertions, 0 failures, 0 errors, 2 skips)
├── docs/agents/              # Developer reference (ARCHITECTURE, PLATFORMS, REFERENCE, TRANSFORMS)
├── Rakefile
├── README.md
└── AGENTS.md
```

## Supported Platforms (14 agents)

| Agent | Type | Scope | Config Location | Install Command |
|-------|------|-------|-----------------|-----------------|
| [OpenCode](docs/agents/platforms/opencode.md) | directory | user | `~/.config/opencode/rules/` or `AGENTS.md` | `bin/rulepack install --target opencode` |
| [Oh My Pi](docs/agents/platforms/oh-my-pi.md) | directory | user | `~/.omp/agent/rules/` or `AGENTS.md` | `bin/rulepack install --target oh-my-pi` |
| [Crush](docs/agents/platforms/crush.md) | skill | user | `~/.config/crush/crush.md` | `bin/rulepack install --target crush` |
| [Goose](docs/agents/platforms/goose.md) | skill | user | `~/.local/share/goose/goose.md` | `bin/rulepack install --target goose` |
| [Droid](docs/agents/platforms/droid.md) | skill | user | `~/.factory/AGENTS.md` | `bin/rulepack install --target droid` |
| [Gemini CLI](docs/agents/platforms/gemini-cli.md) | directory | user | `~/.gemini/GEMINI.md` | `bin/rulepack install --target gemini-cli` |
| [Qwen Code](docs/agents/platforms/qwen-code.md) | import | user | `~/.config/qwen/config.yaml` | `bin/rulepack install --target qwen-code` |
| [Cursor](docs/agents/platforms/cursor.md) | directory | project | `.cursor/rules/` | `bin/rulepack install --target cursor --project .` |
| [Windsurf](docs/agents/platforms/windsurf.md) | directory | project | `.windsurf/rules/` | `bin/rulepack install --target windsurf --project .` |
| [GitHub Copilot](docs/agents/platforms/github-copilot.md) | import | project | `.github/copilot-instructions.md` | `bin/rulepack install --target github-copilot --project .` |
| [Claude Code](docs/agents/platforms/claude-code.md) | directory | project | `.claude/rules/` | `bin/rulepack install --target claude-code --project .` |
| [Codex CLI](docs/agents/platforms/codex.md) | skill | project | `AGENTS.md` | `bin/rulepack install --target codex --project .` |
| [Antigravity](docs/agents/platforms/antigravity.md) | directory | user | `~/.gemini/GEMINI.md` | `bin/rulepack install --target antigravity` |
| [Agents](docs/agents/platforms/agents.md) | directory | user | `~/.agents/rules/` | `bin/rulepack install --target agents` |

**Scope**: `user` = global (home directory), `project` = per-project (requires `--project` flag)

**Agent support**: 5 platforms support `format: agent` packages via their `agents_dir` — OpenCode, Oh My Pi, Cursor, Windsurf, Claude Code. See [AGENTS.md](AGENTS.md#agent-format) for details.

## Agent Packages

Agent packages (`pkg_type: agent`) install custom agent definitions to platform-specific agent directories. The build pipeline automatically translates agent files to each platform's expected format:

- **OpenCode**: YAML frontmatter injected via `agent_to_opencode.rb`
- **Cursor**: `agent.json` manifest generated from PKGBUILD `agent_config` field via `agent_to_cursor.rb`
- **Claude Code**: Section schema added via `agent_to_claude_code.rb`
- **Oh My Pi / Windsurf**: Plain markdown copied as-is (auto-discovered)

Example — install the Ruby type signature agent:

```bash
bin/rulepack build
bin/rulepack install ruby-update-signatures --target oh-my-pi
bin/rulepack install ruby-update-signatures --target opencode
bin/rulepack install ruby-update-signatures --target cursor --project /path/to/project
```

## Interactive Sub-skill Selection

When installing a skill-bundle with 2-150 sub-skills in a real terminal, Rulepack shows an interactive selection menu (TUI):

```
┌──────────────────────────────────────────────────────────┐
│  Rulepack Interactive Selector: cc-skills-golang          │
└──────────────────────────────────────────────────────────┘
  Use [↑/↓] (or j/k) to Navigate, [Space] to Toggle, [Enter] to Confirm
  Press [a] for All, [n] for None, [i] to Invert, [q] to Quit

▸ ⬢ [x] golang-benchmark  — golang-benchmark
  ⬢ [x] golang-cli — golang-cli
  ⬢ [x] golang-code-style — golang-code-style
```

- `Space` — Toggle individual sub-skills
- `a` — Select all
- `n` — Deselect all
- `i` — Invert selection
- `Enter` — Confirm and install selected sub-skills
- Only in a real TTY; pipes/CI skip the menu and install all sub-skills
- Use `--select <names>` to skip the menu entirely:

```bash
bin/rulepack install antigravity-skills --select llm-evaluation,prompt-engineer
```

## Query Tool

```bash
# Top-level shortcuts
bin/rulepack list              # List all packages
bin/rulepack show <pkgname>    # Show package details
bin/rulepack search <tag>      # Search packages by tag
bin/rulepack platforms         # List available platforms

# Canonical query subcommand (full feature set)
bin/rulepack query list-packages              # List all packages with metadata
bin/rulepack query show <pkgname>             # Show detailed package info
bin/rulepack query search <keyword>           # Search packages by name/description/tags
bin/rulepack query installed --platform crush # Show installed packages for a platform
bin/rulepack query orphans                    # List orphaned packages
bin/rulepack query provides <capability>      # Show packages providing a capability
```

## Validation & Auditing

```bash
bin/rulepack audit                            # Audit all PKGBUILD descriptors (highly recommended)
bin/rulepack audit --strict                   # Strict audit (warn/error on partial platform coverage)
bin/rulepack install opencode --dry-run       # Preview changes
bin/rulepack uninstall opencode --dry-run      # Preview removal
bin/rulepack install --check --target opencode        # Verify installed state
rm -rf build/ && bin/rulepack build            # Full rebuild
```

## Version Management & Upgrades

Packages use pacman-inspired versioning: `epoch:pkgver-pkgrel`.

- **epoch** (default 0): Overrides versioning scheme changes
- **pkgver** (string): Upstream version
- **pkgrel** (default 1): Package release increment

**Upgrade**: Automatic on re-install if newer version detected.
**Downgrade**: Blocked by default; use `--force` to allow.

## Git Pre-Commit Hook

Install the pre-commit hook to automatically run strict audits before every git commit:

```bash
bin/rulepack init-hooks
```

This ensures no broken package descriptors (`PKGBUILD`) or platform schema violations escape into your shared repository.

## Local Registry Overrides

You can override target platform settings locally (e.g. custom installation paths for Cursor or Windsurf) without modifying the shared `data/registry/platforms.yaml` file.

Create a file named `.rulepack.local.yaml` in your project root or `~/.config/rulepack/config.yaml` in your user home:

```yaml
platforms:
  cursor:
    base_path: "/my/custom/cursor-rules-directory"
```

This configuration will be merged automatically into the platforms registry at runtime.

## Git HTTP Fallback

If `git` is not installed on the system, or if a `git clone` fails due to network/firewall constraints, Rulepack automatically falls back to an HTTP tarball download. It parses the Git URL, downloads the appropriate branch/ref as a `.tar.gz` archive using Ruby's core HTTP client, and extracts it directly using standard library tools, maintaining a seamless, zero-dependency environment.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RULEPACK_MAX_REDIRECTS` | `3` | Maximum HTTP redirects for URL source fetches |
| `RULEPACK_READ_TIMEOUT` | `30` | HTTP read timeout in seconds |
| `RULEPACK_CACHE_DIR` | `cache` | Cache directory name under project root |
| `RULEPACK_GIT_DEPTH` | `1` | Git shallow clone depth |
| `RULEPACK_LOG_LEVEL` | `info` | Log level filtering (`error`, `warn`, `info`, `debug`) |

## Code Quality & Security Fixes (2026-05-29)

Full details with claim-verify-act evidence: [`docs/improvement-plan/OPEN-ITEMS.md`](docs/improvement-plan/OPEN-ITEMS.md) (29 items completed).

Key fixes: `pkgver_func` shell execution (P-J), HTTP 30x redirect handling (P-K), `strip-frontmatter` enforcement (P-L), multi-package checksum verification (P-M), symlink path traversal prevention (P-N), library `exit 1` → `raise ArgumentError` (P-O), TUI selector timeout (P-T).

**Test gate**: 331 unit/integration tests — **0 failures, 0 errors** (E2E gated behind `NETWORK_E2E`).

---

## License

MIT
