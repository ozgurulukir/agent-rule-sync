# Rulepack — PKGBUILD-based Agent Rule Manager

Package-based rule management for AI coding agents, inspired by PKGBUILD/pacman.

> **For developers**: See [AGENTS.md](AGENTS.md) for architecture, creating packages, pipeline details, testing, and project status.

## What Is This?

A **PKGBUILD-inspired package manager** for agent rules and skills:

- **Package format**: Each rule/skill is a package with a `PKGBUILD` descriptor
- **Build pipeline**: Fetch → Transform → Build artifacts per platform → Aggregate vendor skills → Install
- **Multi-platform**: One source → multiple target platforms (OpenCode, Crush, Gemini CLI, etc.)
- **Change detection**: SHA256 checksums track source and built artifacts
- **Index database**: `data/index.yaml` tracks package state, versions, and installations

## Quick Start

```bash
# Build all packages
bin/rulepack build

# Build with timing info
bin/rulepack build --timing

# Install to a user-level platform (Zero Assumptions: target is mandatory)
bin/rulepack install --target opencode              # Real install (all built packages)
bin/rulepack install memory --target opencode       # Real install of a single package (exact match)
bin/rulepack install memory -t opencode --dry-run   # Dry run preview

# Pacman flag shortcut equivalents
bin/rulepack -S --target opencode                   # Equivalent to install --target opencode
bin/rulepack -S memory -t opencode                  # Equivalent to install memory -t opencode

# Install to a project-level platform (Target and Project are mandatory)
bin/rulepack install --target cursor --project .    # Install to current project
bin/rulepack install memory -t cursor --project /path/to/project

# Global Sync (Install all packages to all user-level platforms)
bin/rulepack install --target all

# Verify installed packages and integrity (verify or -Qk)
bin/rulepack verify --target opencode               # Verify all packages on opencode
bin/rulepack -Qk memory -t opencode                 # Verify single package on opencode

# Repair drift (fix or -F)
bin/rulepack fix --target opencode                  # Repair any modified/missing files
bin/rulepack -F memory -t opencode                  # Repair single package

# Audit package descriptors for integrity & platforms coverage
bin/rulepack audit                                  # Audit all packages (schema, local sources, platforms)
bin/rulepack audit --strict                         # Strict audit (requires targets for all 14 platforms)
bin/rulepack audit --target opencode                # Target-specific platform check
bin/rulepack audit --format json                    # Machine-readable output

# Uninstall from platforms (uninstall or -R)
bin/rulepack uninstall --target opencode            # Uninstall all packages from opencode
bin/rulepack -R memory -t cursor --project .        # Uninstall single package from cursor project

# Query database (query or -Q)
bin/rulepack query memory
bin/rulepack -Q security

```

## Project Structure

```
rulepack/
├── bin/rulepack              # CLI entry point
├── lib/rulepack/             # Library modules (20 .rb files)
│   ├── common.rb             # Constants, Config, basic IO
│   ├── installer.rb          # Installer library
│   ├── build.rb              # Build orchestrator
│   ├── query.rb              # Package database queries
│   └── ... (logging, cache, backup, version, source,
│             transform, validation, platform, uninstaller,
│             aggregate, translate, verify, fix,
│             generate-catalog, install CLI, uninstall CLI)
├── data/                     # Single Source of Truth
│   ├── packages/             # Package definitions (9 packages)
│   ├── registry/platforms.yaml  # 14 platform configurations
│   ├── platforms/            # Format profiles (informational)
│   ├── translators/          # 3 custom translators
│   ├── transformers/         # 3 custom transformers
│   └── index.yaml            # Master package database
├── build/                    # Build artifacts (generated)
├── test/                     # Test suite (202 tests)
├── Rakefile
├── README.md
└── AGENTS.md
```

## Supported Platforms (14 agents)

| Agent | Type | Scope | Config Location | Install Command |
|-------|------|-------|-----------------|-----------------|
| [OpenCode](docs/agents/agents/opencode.md) | directory | user | `~/.config/opencode/rules/` | `bin/rulepack install --target opencode` |
| [Oh My Pi](docs/agents/agents/oh-my-pi.md) | directory | user | `~/.config/oh-my-pi/rules/` | `bin/rulepack install --target oh-my-pi` |
| [Crush](docs/agents/agents/crush.md) | skill | user | `/usr/local/share/crush/crush.md` | `bin/rulepack install --target crush` |
| [Goose](docs/agents/agents/goose.md) | skill | user | `~/.local/share/goose/goose.md` | `bin/rulepack install --target goose` |
| [Droid](docs/agents/agents/droid.md) | skill | user | `~/.config/droid/droid.md` | `bin/rulepack install --target droid` |
| [Gemini CLI](docs/agents/agents/gemini-cli.md) | import | user | `~/.config/gemini/GEMINI.md` | `bin/rulepack install --target gemini-cli` |
| [Qwen Code](docs/agents/agents/qwen-code.md) | import | user | `~/.config/qwen/QWEN.md` | `bin/rulepack install --target qwen-code` |
| [Cursor](docs/agents/agents/cursor.md) | directory | project | `.cursor/rules/` | `bin/rulepack install --target cursor --project .` |
| [Windsurf](docs/agents/agents/windsurf.md) | directory | project | `.windsurf/rules/` | `bin/rulepack install --target windsurf --project .` |
| [GitHub Copilot](docs/agents/agents/github-copilot.md) | import | project | `.github/copilot-instructions.md` | `bin/rulepack install --target github-copilot --project .` |
| [Claude Code](docs/agents/agents/claude-code.md) | directory | project | `.claude/rules/` | `bin/rulepack install --target claude-code --project .` |
| [Codex CLI](docs/agents/agents/codex.md) | skill | project | `AGENTS.md` | `bin/rulepack install --target codex --project .` |
| [Antigravity](docs/agents/agents/antigravity.md) | directory | project | `.agent/skills/` | `bin/rulepack install --target antigravity --project .` |
| [Agents](docs/agents/agents/agents.md) | directory | user | `~/.config/agents/rules/` | `bin/rulepack install --target agents` |

**Scope**: `user` = global (home directory), `project` = per-project (requires `--project` flag)

## Interactive Sub-skill Selection

When installing a skill-bundle with 2-50 sub-skills in a real terminal, Rulepack shows an interactive numbered menu (pacman-style):

```
📦 cc-skills-golang contains 44 sub-skills.
Select sub-skills to install:
  1) golang-benchmark
  2) golang-cli
  ...
 44) golang-stay-updated

Enter numbers (e.g. 1,2,3, 5-10, or 'all'):
```

- `1,2,3`, `5-10`, or `1-5,10,50-55` — select ranges
- `all` or empty — install all sub-skills
- Only in a real TTY; pipes/CI skip the menu and install all
- Bundles with >50 sub-skills install all silently
- Use `--select <names>` to skip the menu entirely:

```bash
bin/rulepack install antigravity-skills --select llm-evaluation,prompt-engineer
```

## Query Tool

```bash
bin/rulepack list              # List all packages
bin/rulepack show <pkgname>    # Show package details
bin/rulepack search <tag>      # Search packages by tag
bin/rulepack installed --platform opencode  # List installed for a platform
bin/rulepack platforms         # List available platforms
```

## Validation & Auditing

```bash
bin/rulepack audit                            # Audit all PKGBUILD descriptors (highly recommended)
bin/rulepack audit --strict                   # Strict audit (warn/error on partial platform coverage)
bin/rulepack install opencode --dry-run       # Preview changes
bin/rulepack uninstall opencode --dry-run      # Preview removal
bin/rulepack check opencode                    # Verify installed state
rm -rf build/ && bin/rulepack build            # Full rebuild
```

## Version Management & Upgrades

Packages use pacman-inspired versioning: `epoch:pkgver-pkgrel`.

- **epoch** (default 0): Overrides versioning scheme changes
- **pkgver** (string): Upstream version
- **pkgrel** (default 1): Package release increment

**Upgrade**: Automatic on re-install if newer version detected.  
**Downgrade**: Blocked by default; use `--force` to allow.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RULEPACK_MAX_REDIRECTS` | `3` | Maximum HTTP redirects for URL source fetches |
| `RULEPACK_READ_TIMEOUT` | `30` | HTTP read timeout in seconds |
| `RULEPACK_CACHE_DIR` | `cache` | Cache directory name under `build/` |
| `RULEPACK_GIT_DEPTH` | `1` | Git shallow clone depth |
| `RULEPACK_LOG_LEVEL` | `info` | Log level filtering (`error`, `warn`, `info`, `debug`) |

## License

MIT
