# Rulepack — PKGBUILD-based Agent Rule Manager

Package-based rule management for AI coding agents, inspired by PKGBUILD/pacman.

## What Is This?

> "The PKGBUILD — an elegant manifest for a more civilized age."
> This project adapts that philosophy to coding agent rules and skill management.

A **PKGBUILD-inspired package manager** for agent rules and skills:

- **Package format**: Each rule/skill is a package with a `PKGBUILD` descriptor
- **Build pipeline**: Fetch → Transform → Build artifacts per platform → Aggregate vendor skills → Install
- **Multi-platform**: One source → multiple target platforms (OpenCode, Crush, Gemini CLI, etc.)
- **Change detection**: SHA256 checksums track source and built artifacts
- **Index database**: `data/index.yaml` tracks package state, versions, and installations

> **Note**: PKGBUILD/pacman is used as **architectural inspiration** (package descriptor format, versioning scheme, build pipeline). Rulepack does not track Arch Linux packages or use pacman as a dependency.

## Quick Start

```bash
# Build all packages
bin/rulepack build

# Build with timing info
bin/rulepack build --timing

# Aggregate vendor skills (for skill-based agents)
bin/rulepack aggregate

# Install to a user-level platform
bin/rulepack install opencode          # real install
bin/rulepack install opencode --dry-run  # preview
bin/rulepack install --all --dry-run    # preview install to all platforms
bin/rulepack install --targets memory   # show target platforms for a package

# Install to a project-level platform (run from project root)
bin/rulepack install cursor --project .   # install to current project
bin/rulepack install cursor --project ~/projects/myapp

# Verify installed state
bin/rulepack check opencode

# Uninstall from a platform
bin/rulepack uninstall opencode         # user-level
bin/rulepack uninstall cursor --project .  # project-level

# Verify index matches disk (detect drift)
bin/rulepack verify opencode           # specific platform
bin/rulepack verify                    # all platforms

# Repair drift automatically
bin/rulepack fix opencode              # reinstall broken packages
bin/rulepack fix opencode --dry-run    # preview only

# Query package database
bin/rulepack list
bin/rulepack show memory
bin/rulepack search security
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
│   └── ... (logging.rb, cache.rb, backup.rb, version.rb, source.rb,
│             transform.rb, validation.rb, platform.rb, uninstaller.rb,
│             aggregate.rb, translate.rb, verify.rb, fix.rb,
│             generate-catalog.rb, install.rb (CLI), uninstall.rb (CLI))
├── data/                     # Data files
│   ├── packages/             # Package definitions (10 packages)
│   ├── registry/
│   │   └── platforms.yaml    # 14 platform configurations
│   ├── platforms/            # Format profiles (14 agents)
│   ├── translators/          # 3 custom translators
│   ├── transformers/         # 3 custom transformers
│   ├── skills/
│   │   ├── common/
│   │   └── agent-specific/
│   ├── archive/
│   └── index.yaml            # Master package database
├── build/                    # Build artifacts (generated)
│   ├── index.yaml
│   ├── catalog.json
│   ├── opencode/
│   ├── crush/
│   └── gemini-cli/...
├── test/                     # Test suite (202 tests)
├── Rakefile
├── README.md
└── AGENTS.md
```

## Package Dependencies

Skills and rules are **text files** — they are inherently independent. A skill may reference external tools (e.g., `awk`, `python`) but these are **system-level dependencies**, not package dependencies. Rulepack documents tool requirements but does not manage them; installation of system tools is the **user's responsibility**.

- **No inter-package dependencies**: Skills/rules do not depend on each other.
- **No hierarchical resolution**: There is no package hierarchy; users control install order.
- **No dependency resolution**: The system does not perform topological sorting or cycle detection.
- **Tool prerequisites**: If a skill requires a system tool, it is documented in the package description. Rulepack does not verify or install system packages.

## Creating a New Package

1. Create package directory: `data/packages/<pkgname>/`
2. Add source file: `data/packages/<pkgname>/src/<filename>.md`
3. Write `PKGBUILD` descriptor
4. Build and install: `ruby lib/rulepack/build.rb && ruby lib/rulepack/install.rb <platform>`

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
    translate: custom:translators/rule_to_skill.rb
    transformer: strip-frontmatter

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

Custom transformers: Ruby script defining `Transform` class with `.transform(content, pkgname: nil)` method. Reference in PKGBUILD as `transformer: custom:path/to/transformer.rb`. Paths are resolved relative to repo root (`rulepack/`), validated with `realpath` to prevent symlink attacks.

**Example Custom Transformers** (in `data/transformers/`):
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
bin/rulepack install golang-security --select auth,sql

# Install all sub-skills (default)
bin/rulepack install golang-security
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
| Antigravity | directory | project | `.agent/skills/` | [Antigravity](docs/agents/agents/antigravity.md) |
| Agents | directory | user | `~/.config/agents/` | [Agents](docs/agents/agents/agents.md) |

**Scope**: `user` = global (home directory), `project` = per-project (requires `--project` flag)

See [Platforms](docs/agents/PLATFORMS.md) for the complete reference.

## Interactive Sub-skill Selection

When installing a skill-bundle with multiple sub-skills in a terminal, Rulepack shows an interactive numbered menu (pacman-style):

```
📦 antigravity-skills contains 306 sub-skills.
Select sub-skills to install:
  1) accessibility-compliance-accessibility-audit
  2) agent-orchestration-improve-agent
  ...
  306) workflow-patterns

Enter numbers (e.g. 1,2,3, 5-10, or 'all'):
```

- Enter `1,2,3` or `5-10` to select ranges
- Enter `all` or press Enter to install everything
- Runs only in a real TTY (no menu in pipes/CI)
- Use `--select <names>` to skip the menu entirely

## Query Tool

```bash
# List all packages
bin/rulepack list

# Show package details
bin/rulepack show memory

# Search by tag
bin/rulepack search security

# List installed packages on a platform
bin/rulepack installed --platform opencode   # or: ruby lib/rulepack/query.rb installed --platform opencode

# List available platforms
bin/rulepack platforms
```

## Validation

```bash
# Dry-run install (no filesystem changes)
bin/rulepack install opencode --dry-run

# Dry-run install with timing
bin/rulepack install opencode --dry-run --timing

# Uninstall dry-run
bin/rulepack uninstall opencode --dry-run

# Verify installed state matches index
bin/rulepack check opencode

# Full rebuild
rm -rf build/ && bin/rulepack build
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
rake test              # All tests (202 tests, 663 assertions)
rake test_unit         # Unit tests only (48 tests)
rake test_integration  # Integration tests only (29 tests)
rake test_cache        # Cache tests (24 tests)
rake test_pkgbuild     # PKGBUILD validation tests (31 tests)
rake test_platform     # Platform registry tests (33 tests)
rake test_uninstall    # Uninstall tests (7 tests)
rake test_query        # Query tests (16 tests)
rake test_translate    # Translate tests (4 tests)
rake test_aggregate    # Aggregate tests (4 tests)
rake test_e2e          # End-to-end pipeline tests (14 tests)
```

**Test coverage** (202 tests, 663 assertions, 0 failures):
- **test_common.rb** (48): version comparison, format_version, filename/dir validation, user path expansion, frontmatter stripping
- **test_integration.rb** (29): build index, skill-bundle manifest (6 tests), version comparison, schema migration, transaction rollback, cache integration
- **test_cache.rb** (24): cache key generation, cache dir, source_cached?, cache_source, get_cached_source, fetch errors
- **test_pkgbuild_validation.rb** (31): load_pkgbuild, validate_pkgbuild (valid + all invalid field types)
- **test_platform.rb** (33): platform registry, path resolution, safe_relative, prerequisites
- **test_uninstall.rb** (7): index mutation, dry-run, dedup, disk write verification
- **test_query.rb** (16): list, show, search, installed, check, orphans, depends, provides
- **test_translate.rb** (4): translator loading, apply_translator
- **test_aggregate.rb** (4): skill agent detection, vendor file creation
- **test_end_to_end.rb** (14): build → install → check → uninstall across all platform types

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
ruby lib/rulepack/install.rb opencode --force
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RULEPACK_MAX_REDIRECTS` | `3` | Maximum HTTP redirects for URL source fetches |
| `RULEPACK_READ_TIMEOUT` | `30` | HTTP read timeout in seconds |
| `RULEPACK_CACHE_DIR` | `cache` | Cache directory name under `data/` |
| `RULEPACK_GIT_DEPTH` | `1` | Git shallow clone depth |
| `RULEPACK_LOG_LEVEL` | `info` | Log level filtering (`error`, `warn`, `info`, `debug`) |

## Deprecated: Old System

Old system files (`scripts/`, `data/schema.yaml`, `data/rules/`, `data/docs/`, `data/vendor/`) are from the previous schema-driven pipeline. They are **deprecated** and no longer used. The new PKGBUILD-based workflow (`data/` directory) is the canonical implementation.

## License

MIT
