# Agent Rule Sync — PKGBUILD-based SSoT v4

Package-based Single Source of Truth management for AI agent rules and skills.

## What Is This?

> "The PKGBUILD — an elegant manifest for a more civilized age."
> This project adapts that philosophy to coding agent rules and skill management.

A **PKGBUILD-inspired package manager** for agent rules and skills:

- **Package format**: Each rule/skill is a package with a `PKGBUILD` descriptor
- **Build pipeline**: Fetch → Transform → Build artifacts per platform → Aggregate vendor skills → Install
- **Multi-platform**: One source → multiple target platforms (OpenCode, Crush, Gemini CLI, etc.)
- **Change detection**: SHA256 checksums track source and built artifacts
- **Index database**: `ssot/index.yaml` tracks package state, versions, and installations

> **Note**: PKGBUILD/pacman is used as **architectural inspiration** (package descriptor format, versioning scheme, build pipeline). SSoT does not track Arch Linux packages or use pacman as a dependency.

## Quick Start

```bash
# Build all packages
bin/ssot build

# Aggregate vendor skills (for skill-based agents)
bin/ssot aggregate  # or: ruby ssot/aggregate-skills.rb

# Install to a user-level platform
bin/ssot install opencode          # real install
bin/ssot install opencode --dry-run  # preview
bin/ssot install --all --dry-run    # preview install to all platforms
bin/ssot install --targets memory   # show target platforms for a package

# Install to a project-level platform (run from project root)
bin/ssot install cursor --project .   # install to current project
bin/ssot install cursor --project ~/projects/myapp

# Verify installed state
bin/ssot check opencode

# Uninstall from a platform
bin/ssot uninstall opencode         # user-level
bin/ssot uninstall cursor --project .  # project-level

# Query package database
bin/ssot list
bin/ssot show memory
bin/ssot search security
```

## Project Structure

```
agent-rule-sync/
├── ssot/                           # Single Source of Truth root
│   ├── lib/                        # Library modules
│   │   ├── common.rb               # Shared utilities (version, cache, fetch, validate)
│   │   └── install.rb              # Installer library (modular API)
│   ├── packages/                   # Package definitions (each has PKGBUILD + src/)
│   │   ├── memory/PKGBUILD
│   │   │   └── src/00-memory.md
│   │   ├── shell/PKGBUILD
│   │   └── vibe-security/PKGBUILD
│   ├── registry/
│   │   └── platforms.yaml  # Platform configurations
│   ├── transformers/       # Custom transformer scripts
│   ├── build.rb            # Build orchestrator
│   ├── aggregate-skills.rb # Vendor skill aggregator
│   ├── install.rb          # Platform installer (CLI entry point — delegates to lib/install.rb)
│   ├── uninstall.rb        # Platform uninstaller
│   ├── query.rb            # Package database queries
│   ├── index.yaml          # Master package database
│   └── build/              # Build artifacts (generated)
│       ├── index.yaml
│       ├── opencode/
│       ├── crush/
│       └── gemini-cli/
├── README.md
└── AGENTS.md               # Developer guidelines
```

## Package Dependencies

Skills and rules are **text files** — they are inherently independent. A skill may reference external tools (e.g., `awk`, `python`) but these are **system-level dependencies**, not package dependencies. SSoT documents tool requirements but does not manage them; installation of system tools is the **user's responsibility**.

- **No inter-package dependencies**: Skills/rules do not depend on each other.
- **No hierarchical resolution**: There is no package hierarchy; users control install order.
- **No dependency resolution**: The system does not perform topological sorting or cycle detection.
- **Tool prerequisites**: If a skill requires a system tool, it is documented in the package description. SSoT does not verify or install system packages.

## Creating a New Package

1. Create package directory: `ssot/packages/<pkgname>/`
2. Add source file: `ssot/packages/<pkgname>/src/<filename>.md`
3. Write `PKGBUILD` descriptor
4. Build and install: `ruby ssot/build.rb && ruby ssot/install.rb <platform>`

## PKGBUILD Example

```yaml
---
pkgname: my-rule
pkgver: '1.0.0'
pkgrel: 1
epoch: 0
pkgdesc: My custom rule
arch: any
order: 0

source:
  - type: local
    path: src/my-rule.md

targets:
  - platform: opencode
    format: directory
    output: 00-my-rule.md
    transformer: copy
    install:
      type: symlink

  - platform: crush
    format: skill
    output: my-rule-skill.md
    transformer: copy

checksums:
  source: null
  built: {}

dependencies: []
conflicts: []
provides: []
tags: []
maintainer: null
license: MIT
```

## Transformer Pattern

Built-in transformers:
- `copy` — identity (no change)
- `strip-frontmatter` — remove YAML frontmatter (`---` blocks)

Custom transformers: Ruby script defining `Transform` class with `.transform(content, pkgname: nil)` method. Reference in PKGBUILD as `transformer: custom:path/to/transformer.rb`. Paths are resolved relative to repo root (`ssot/`), validated with `realpath` to prevent symlink attacks.

**Example Custom Transformers** (in `ssot/transformers/`):
- `add-header.rb` — prepend title/header from frontmatter
- `strip-comments.rb` — remove HTML comments and normalize whitespace
- `format-code.rb` — auto-detect and tag code blocks (Ruby/Python)

## skill-bundle Format

For multi-skill repositories (e.g. `cc-skills-golang`), use `format: skill-bundle` to deploy an entire skill directory tree as one package:

```yaml
pkgname: cc-skills-golang
pkgver: '2026.05'
pkgdesc: Collection of Go security skills
arch: any
order: 10

source:
  - type: local
    path: skills   # cloned repo's skills/ directory

targets:
  - platform: opencode
    format: skill-bundle
    output: .                # directory marker (must be exactly ".")
    transformer: copy
    install:
      type: copy
      target_dir: cc-skills-golang/   # → ~/.config/opencode/skills/cc-skills-golang/
```

**Requirements**: `output` must be `.`, `install.target_dir` required, `install.type` must be `copy`. Supported on `directory`-type platforms (OpenCode, Cursor, Windsurf, Claude Code). Git source is also supported. See [Reference](docs/agents/REFERENCE.md) for full details.

**Sub-skill Selection** (`--select`):
```bash
# Install only specific sub-skills
bin/ssot install golang-security --select auth,sql

# Install all sub-skills (default)
bin/ssot install golang-security
```

**Meta-packages** (pacman-style):
```yaml
pkgname: golang-security-all
depends:
  - golang-security/auth
  - golang-security/sql-injection
```

## Quick Links

- **[Architecture](docs/agents/ARCHITECTURE.md)** — System design, pipeline, data flow
- **[Platforms](docs/agents/PLATFORMS.md)** — All supported agents and their configuration
- **[Usage](docs/agents/USAGE.md)** — Commands, workflows, installation guide
- **[Reference](docs/agents/REFERENCE.md)** — PKGBUILD format, transformer API, index schema
- **[Transforms](docs/agents/TRANSFORMS.md)** — Transformer system (built-in + custom)
- **[Upstream](docs/agents/UPSTREAM.md)** — Upstream source tracking
- **[Agent Guides](docs/agents/agents/README.md)** — Per-agent detailed reference

## Supported Platforms

| Agent | Type | Scope | Config | Guide |
|-------|------|-------|--------|-------|
| OpenCode | directory | user | `~/.config/opencode/rules/` | [OpenCode](docs/agents/agents/opencode.md) |
| Oh My Pi | directory | user | `~/.config/oh-my-pi/rules/` | [Oh My Pi](docs/agents/agents/oh-my-pi.md) |
| Crush | skill | user | `/usr/local/share/crush/crush.md` | [Crush](docs/agents/agents/crush.md) |
| Goose | skill | user | `~/.local/share/goose/goose.md` | [Goose](docs/agents/agents/goose.md) |
| Droid | skill | user | `~/.config/droid/droid.md` | [Droid](docs/agents/agents/droid.md) |
| Gemini CLI | import | user | `~/.config/gemini/GEMINI.md` | [Gemini CLI](docs/agents/agents/gemini-cli.md) |
| Qwen Code | import | user | `~/.config/qwen/QWEN.md` | [Qwen Code](docs/agents/agents/qwen-code.md) |
| Cursor | directory | project | `.cursor/rules/` | [Cursor](docs/agents/agents/cursor.md) |
| Windsurf | directory | project | `.windsurf/rules/` | [Windsurf](docs/agents/agents/windsurf.md) |
| GitHub Copilot | import | project | `.github/copilot-instructions.md` | [GitHub Copilot](docs/agents/agents/github-copilot.md) |
| Claude Code | directory | project | `.claude/rules/` | [Claude Code](docs/agents/agents/claude-code.md) |
| Codex CLI | skill | project | `AGENTS.md` | [Codex CLI](docs/agents/agents/codex.md) |

**Scope**: `user` = global (home directory), `project` = per-project (requires `--project` flag)

See [Platforms](docs/agents/PLATFORMS.md) for the complete reference.

## Query Tool

```bash
# List all packages
bin/ssot list

# Show package details
bin/ssot show memory

# Search by tag
bin/ssot search security

# List installed packages on a platform
bin/ssot installed --platform opencode   # or: ruby ssot/query.rb installed --platform opencode

# List available platforms
bin/ssot platforms
```

## Validation

```bash
# Dry-run install (no filesystem changes)
bin/ssot install opencode --dry-run

# Uninstall dry-run
bin/ssot uninstall opencode --dry-run

# Verify installed state matches index
bin/ssot check opencode

# Full rebuild
rm -rf ssot/build/ && bin/ssot build
```

The system validates:
- PKGBUILD required fields (pkgname, pkgver, pkgrel, epoch, source, targets)
- Output path traversal (no `..`, no absolute paths)
- Transformer existence and symlink safety (realpath check)
- Platform configuration (required fields per type)
- SHA256 checksums for URL sources
- Platform prerequisites (system tools: ruby, python, bash, node — warns if missing)
- Empty content after transform (warns on build)

## Testing

Run the automated test suite with `rake test` (Minitest):

```bash
rake test              # All tests (172 tests, 399 assertions)
rake test_unit         # Unit tests only (48 tests)
rake test_integration  # Integration tests only (29 tests)
rake test_cache        # Cache tests (24 tests)
rake test_pkgbuild     # PKGBUILD validation tests (23 tests)
rake test_platform     # Platform registry tests (22 tests)
rake test_uninstall    # Uninstall tests (7 tests)
```

**Test coverage** (172 tests, 399 assertions, 0 failures):
- **test_common.rb** (48): version comparison, format_version, filename/dir validation, user path expansion, frontmatter stripping
- **test_integration.rb** (29): build index, skill-bundle manifest (6 tests), version comparison, schema migration, transaction rollback, cache integration
- **test_cache.rb** (24): cache key generation, cache dir, source_cached?, cache_source, get_cached_source, fetch errors
- **test_pkgbuild_validation.rb** (23): load_pkgbuild, validate_pkgbuild (valid + all invalid field types)
- **test_platform.rb** (22): platform registry, path resolution, safe_relative, prerequisites
- **test_uninstall.rb** (7): index mutation, dry-run, dedup, disk write verification

## Version Management & Upgrades

Packages use a three-component version scheme inspired by pacman:

- `epoch` — overrides upstream versioning scheme changes (default: 0)
- `pkgver` — upstream version string (e.g., `'1.0.0'`, `'2026.05'`)
- `pkgrel` — package release increment for repackaging (default: 1)

**Comparison**: epoch → pkgver (alphanumeric segments) → pkgrel. Higher wins.

**Upgrade**: Re-installing automatically upgrades if newer version detected.  
**Downgrade**: Blocked by default; use `--force` to allow.

```bash
# Force downgrade (not recommended unless necessary)
ruby ssot/install.rb opencode --force
```

## Deprecated: Old System

Old system files (`scripts/`, `ssot/schema.yaml`, `ssot/rules/`, `ssot/docs/`, `ssot/vendor/`) are from the previous schema-driven pipeline. They are **deprecated** and no longer used. The new PKGBUILD-based workflow (`ssot/` directory) is the canonical implementation.

## License

MIT
