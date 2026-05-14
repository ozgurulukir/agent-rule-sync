# Repository Guidelines — PKGBUILD-based SSoT v4

## Project Overview

This repository implements a **Single Source of Truth (SSoT)** management system for agent rules, skills, and documentation using a **package-based architecture** (PKGBUILD format). Each rule or skill is a package with a declarative build descriptor. The system fetches, transforms, builds, and distributes content to multiple agent platforms through a streamlined pipeline.

**Core Purpose**: Maintain one authoritative source for agent behavior definitions (rules, skills, docs) as individual packages, automatically propagate updates to multiple target platforms with change detection, custom transformers, and per-platform format conversion.

---

## Quick Links

- **[Architecture](docs/agents/ARCHITECTURE.md)** — System design, pipeline, data flow
- **[Platforms](docs/agents/PLATFORMS.md)** — All supported agents and configuration
- **[Usage](docs/agents/USAGE.md)** — Commands, workflows, installation guide
- **[Reference](docs/agents/REFERENCE.md)** — PKGBUILD format, transformer API, index schema
- **[Transforms](docs/agents/TRANSFORMS.md)** — Transformer system documentation
- **[Upstream](docs/agents/UPSTREAM.md)** — Upstream source management
- **[Agent Guides](docs/agents/agents/)** — Per-agent detailed reference

---

## Supported Platforms (12 agents)

| Agent | Type | Scope | Config Location | Install Command |
|-------|------|-------|-----------------|-----------------|
| [OpenCode](docs/agents/agents/opencode.md) | directory | user | `~/.config/opencode/rules/` | `bin/ssot install opencode` |
| [Oh My Pi](docs/agents/agents/oh-my-pi.md) | directory | user | `~/.config/oh-my-pi/rules/` | `bin/ssot install oh-my-pi` |
| [Crush](docs/agents/agents/crush.md) | skill | user | `/usr/local/share/crush/crush.md` | `bin/ssot install crush` |
| [Goose](docs/agents/agents/goose.md) | skill | user | `~/.local/share/goose/goose.md` | `bin/ssot install goose` |
| [Droid](docs/agents/agents/droid.md) | skill | user | `~/.config/droid/droid.md` | `bin/ssot install droid` |
| [Gemini CLI](docs/agents/agents/gemini-cli.md) | import | user | `~/.config/gemini/GEMINI.md` | `bin/ssot install gemini-cli` |
| [Qwen Code](docs/agents/agents/qwen-code.md) | import | user | `~/.config/qwen/QWEN.md` | `bin/ssot install qwen-code` |
| [Cursor](docs/agents/agents/cursor.md) | directory | project | `.cursor/rules/` | `bin/ssot install cursor --project .` |
| [Windsurf](docs/agents/agents/windsurf.md) | directory | project | `.windsurf/rules/` | `bin/ssot install windsurf --project .` |
| [GitHub Copilot](docs/agents/agents/github-copilot.md) | import | project | `.github/copilot-instructions.md` | `bin/ssot install github-copilot --project .` |
| [Claude Code](docs/agents/agents/claude-code.md) | directory | project | `.claude/rules/` | `bin/ssot install claude-code --project .` |
| [Codex CLI](docs/agents/agents/codex.md) | skill | project | `AGENTS.md` | `bin/ssot install codex --project .` |

**Scope**: `user` = global (home directory), `project` = per-project (requires `--project` flag)

See [Platforms](docs/agents/PLATFORMS.md) for full details.

---

## Architecture & Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                     PKGBUILD Packages (ssot/packages/)            │
│  Each package: pkgname, source, targets[platform], transformer  │
│  memory/PKGBUILD, shell/PKGBUILD, vibe-security/PKGBUILD        │
└────────────────────────────┬─────────────────────────────────────┘
                             │ build (ssot/build.rb)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Build Artifacts (ssot/build/<platform>/)   │
│  Platform-specific outputs: rules, skills, imports              │
│  opencode/00-memory.md, crush/skills/vendor/crush.md            │
└────────────────────────────┬─────────────────────────────────────┘
                             │ aggregate (ssot/aggregate-skills.rb)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                   Vendor Skills (ssot/build/<platform>/skills/vendor/) │
│  Combined skill bundles per agent: crush.md, goose.md, droid.md │
└────────────────────────────┬─────────────────────────────────────┘
                             │ install (ssot/install.rb)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Target Agent Platforms                         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐      │
│  │   OpenCode  │  │   Crush      │  │   Gemini CLI       │      │
│  │ (directory) │  │   (skill)    │  │   (import)         │      │
│  └─────────────┘  └──────────────┘  └────────────────────┘      │
└──────────────────────────────────────────────────────────────────┘
```

**Note**: PKGBUILD/pacman is used as **architectural inspiration** (package descriptor format, versioning scheme, build pipeline). SSoT does not track Arch Linux packages or use pacman as a dependency. It is a standalone system for agent skill/rule distribution.

**Single Entry Point**: `bin/ssot` wraps all pipeline commands: `build`, `install`, `uninstall`, `list`, `show`, `search`, `status`, `check`, `platforms`, `help`.

**Key Pipeline Steps**:

1. **Build** (`ssot/build.rb`) — Load all PKGBUILDs from `ssot/packages/`, fetch sources (local/URL with SHA256), apply transformers (copy/strip-frontmatter/custom), write platform-specific artifacts to `ssot/build/<platform>/`, update `ssot/build/index.yaml` and `ssot/index.yaml` with build metadata.

2. **Aggregate** (`ssot/aggregate-skills.rb`) — For skill-based agents (Crush, Goose, Droid), collect rule fragments and common/agent-specific skills, concatenate into a single vendored skill file per agent under `ssot/build/<agent>/skills/vendor/`.

3. **Install** (`ssot/install.rb <platform> [--dry-run]`) — Read `ssot/index.yaml`, for each package built for target platform, install via symlink/copy/inject/append depending on format and platform registry. Update `ssot/index.yaml` with installed state.

4. **Query** (`ssot/query.rb`) — Inspect package database: list packages, show details, search, check installed status.

---

## Package Dependencies

Skills and rules are **text files** — they are inherently independent. A skill may reference external tools (e.g., `awk`, `python`) but these are **system-level dependencies**, not package dependencies. SSoT documents tool requirements but does not manage them; installation of system tools is the **user's responsibility**.

- **No inter-package dependencies**: Skills/rules do not depend on each other.
- **No hierarchical resolution**: There is no package hierarchy; users control install order.
- **No dependency resolution**: The system does not perform topological sorting or cycle detection.
- **Tool prerequisites**: If a skill requires a system tool, it is documented in the package description. SSoT does not verify or install system packages.

---

## Version Management

The system uses a **pacman-inspired versioning scheme**:

- **epoch** (integer, default 0): Overrides upstream versioning scheme changes
- **pkgver** (string): Upstream version (e.g., `'1.0.0'`, `'2026.05'`)
- **pkgrel** (integer, default 1): Package release increment (bump for repackaging)

**Comparison order**: epoch → pkgver (alphanumeric segments) → pkgrel. Higher wins.

**Upgrade**: Automatic on re-install if newer version detected.  
**Downgrade**: Blocked by default; use `--force` to override.

---

## Uninstall

**Uninstall** (`ssot/uninstall.rb <platform> [--dry-run]`) — Remove packages from a target platform.

- Removes symlinks/files (respects `target_dir` overrides)
- Cleans installed records from `ssot/index.yaml`
- Re-aggregates vendor skills for skill-based agents (to remove package contributions)
- Idempotent: safe to run multiple times

```bash
# Preview what would be removed
bin/ssot uninstall opencode --dry-run

# Actually uninstall
bin/ssot uninstall opencode

# After uninstall, verify
bin/ssot check opencode
```

**Note**: For skill-based platforms (Crush, Goose, Droid), uninstall removes the package's contribution from the vendored skill file and regenerates it. For directory platforms, symlinks/files are removed. For import platforms, `@import` lines are not automatically removed (manual config edit required — future enhancement).

---

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `ssot/` | Single Source of Truth root |
| `ssot/packages/` | **Package definitions** — each subdir contains PKGBUILD and source files |
| `ssot/packages/<pkg>/PKGBUILD` | Package build descriptor (pkgname, source, targets, transformer) |
| `ssot/packages/<pkg>/src/` | Raw source files for that package (rules, skill content) |
| `ssot/skills/` | **User skill/repo workspace** — local skill content, upstream repos, vendor output |
| `ssot/skills/common/` | Shared skill definitions (referenced by vendor aggregation) |
| `ssot/skills/agent-specific/` | Per-agent skill overrides (referenced by vendor aggregation) |
| `ssot/registry/platforms.yaml` | **Platform registry** — defines platform types, paths, install methods |

**Note**: Old system files (`scripts/`, `ssot/schema.yaml`, `ssot/rules/`, `ssot/docs/`, `ssot/vendor/`) are no longer used by the new PKGBUILD system.

---

**Development Commands**

**Single Entry Point** (preferred):

```bash
bin/ssot build              # Build all packages + aggregate vendor skills
bin/ssot install opencode   # Install to platform
bin/ssot uninstall opencode # Uninstall from platform
bin/ssot list               # List all packages
bin/ssot status             # Show system status
bin/ssot show memory        # Show package details
bin/ssot search security    # Search packages
bin/ssot platforms           # List platforms
bin/ssot check opencode     # Verify installed state
bin/ssot help               # Show help
```

**Pipeline Execution** (run from repo root):

```bash
# Build all packages: fetch, transform, write artifacts, update index
ruby ssot/build.rb

# Aggregate vendor skill files for skill-based agents (Crush, Goose, Droid)
ruby ssot/aggregate-skills.rb

# Install packages to a target platform
ruby ssot/install.rb <platform> [--dry-run]

# Query package database
ruby ssot/query.rb <command> [options]
```

**Common Commands**:
```bash
# Full workflow: build → aggregate → install
ruby ssot/build.rb && ruby ssot/aggregate-skills.rb && ruby ssot/install.rb opencode

# Preview without changes
ruby ssot/install.rb opencode --dry-run

# Uninstall from a platform
ruby ssot/uninstall.rb opencode
ruby ssot/uninstall.rb opencode --dry-run

# Query installed packages
ruby ssot/query.rb installed --platform opencode

# List all packages
ruby ssot/query.rb list-packages

# Show package details
ruby ssot/query.rb show <pkgname>

# Search packages by tag
ruby ssot/query.rb search <tag>

# Force downgrade (if needed)
ruby ssot/install.rb opencode --force
```

---

## PKGBUILD Format

Each package is defined in `ssot/packages/<pkgname>/PKGBUILD` (YAML):

```yaml
---
pkgname: memory
pkgver: '1.0.0'
pkgrel: 1              # package release (incremented for rebuilds)
epoch: 0               # upstream versioning override (default: 0)
pkgdesc: Workstation Memory Constraints rule
arch: any
order: 0  # ordering in vendor skill aggregation (lower first)

### Source Entry

```yaml
source:
  - type: local
    path: src/00-memory.md
  # Alternative: URL (with SHA256)
  # - type: url
  #   url: https://example.com/rules/memory.md
  #   sha256: "abc123..."
  # Alternative: Git repository
  # - type: git
  #   url: https://github.com/owner/repo.git
  #   ref: main            # branch, tag, or commit hash (default: main)
  #   path: skills/        # path within repo (default: .)
  #   depth: 1             # shallow clone (optional)
```

**Notes**:
- `local` type: `path` relative to package directory or absolute
- `url` type: `sha256` required; PKGBUILD auto-updates on fetch
- `git` type: clones repository, uses commit hash as checksum; `path` points to file/dir inside repo; `depth=1` recommended for speed

# Targets: where to deploy this package
targets:
  - platform: opencode
    format: directory
    output: 00-memory.md
    transformer: copy
    install:
      type: symlink
  - platform: gemini-cli
    format: import
    output: memory-rule.md
    transformer: strip-frontmatter
    install:
      type: copy
      target_dir: imports/
  - platform: crush
    format: skill
    output: memory-skill.md
    transformer: copy
    # install config inherited from platform registry (skill_install: copy)

checksums:
  source: null   # auto-populated by build
  built: {}      # auto-populated per platform

dependencies: []  # other packages required
conflicts: []    # packages that cannot coexist
provides: ['workstation-constraint']  # virtual capabilities
tags:
  - constraints
  - memory
maintainer: null
license: MIT
```

### Required PKGBUILD Fields
- `pkgname` — unique package identifier
- `pkgver` — version string
- `pkgrel` — package release (integer, default 1, increment for rebuilds)
- `epoch` — upstream versioning override (integer, default 0)
- `pkgdesc` — short description
- `arch` — architecture (currently only `any` supported)
- `order` — ordering in vendor skill aggregation (lower first)
- `source` — at least one source entry with `type` (`local`, `url`, or `git`) and `path`/`url`
- `targets` — array of deployment targets, each with `platform`, `format`, `output`

### Target Format Types
| format | Mechanism | Example Agents |
|--------|-----------|----------------|
| `directory` | Symlink or copy file into platform's rules/skills dir | OpenCode, Oh My Pi |
| `import` | Inject `@import` line into platform config file | Gemini CLI, Qwen Code |
| `skill` | Copy or append skill file to platform's skill dir | Crush, Goose, Droid |
| `skill-bundle` | Copy entire directory tree of skills to platform's skills dir | OpenCode, Cursor, Windsurf, Claude Code |

### Install Types (per target)
- `symlink` — create symbolic link (directory agents, rules)
- `copy` — copy file (skills, import agents)
- `append` — append content to existing skill file (rare; platform default usually `copy`)
- `inject` — prepend `@import` directive to config file (import agents)

**Precedence**: Target's `install` config overrides platform's `skill_install`/`rule_install` defaults. If unspecified, falls back to platform registry.

### skill-bundle Format (Directory Platforms)

For repositories containing multiple skills (e.g., `cc-skills-golang`), use `format: skill-bundle` to deploy an entire skill directory tree as one package:

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

  - platform: cursor
    format: skill-bundle
    output: .
    transformer: copy
    install:
      type: copy
      target_dir: cc-skills-golang/   # → .cursor/skills/cc-skills-golang/
```

**Requirements**:
- `output` must be `.` (literal period) — acts as a directory marker
- `install.type` must be `copy`
- `install.target_dir` is **required** — subdirectory under platform's `skills_dir`
- `source` can be `local` (directory path) or `git` (cloned repository)
- For `git` source: `url`, `ref` (branch/tag/commit), `path` (subdir within repo), `depth` (optional) supported

**Behavior**:
- Build: Entire source directory is copied recursively to `ssot/build/<platform>/<pkgname>/`
- Install: Contents are copied recursively to `<platform base_path>/<skills_dir>/<target_dir>/`
- Uninstall: Target directory tree is removed
- Index: `output` recorded as `.`; no single-file checksum (directory checksum future work)

**Supported Platforms**: Any `directory`-type platform with a `skills_dir` (OpenCode, Cursor, Windsurf, Claude Code). Not applicable to `skill` or `import` platforms.

---


## Platform Registry

Platforms are defined in `ssot/registry/platforms.yaml`:

```yaml
opencode:
  type: directory
  display_name: OpenCode
  base_path: ~/.config/opencode/
  rules_dir: rules/
  skills_dir: skills/
  docs_dir: docs/
  rule_install:
    type: symlink
  skill_install:
    type: copy

crush:
  type: skill
  display_name: Crush
  base_path: /usr/local/share/crush/
  skill_file: crush.md
  rule_install: null
  skill_install:
    type: copy  # vendor skill file copied to base_path/skill_file

gemini-cli:
  type: import
  display_name: Gemini CLI
  base_path: ~/.config/gemini/
  config_file: cli_config.yaml
  rule_install:
    type: inject
    directive: '@import'
  skill_install:
    type: inject
```

### Platform Types
- `directory` — file-based agent; rules go to `rules_dir`, skills to `skills_dir`
- `import` — config-based agent; `@import` lines injected into `config_file`
- `skill` — skill-file agent; vendored skill copied/appended to `skill_file`

---

## Index Database

`ssot/index.yaml` is the master package database (YAML). Structure:

```yaml
version: 3.0
generated: '2026-05-14T07:56:48Z'
packages:
  memory:
    pkgver: 1.0.0
    pkgdesc: Workstation Memory Constraints rule
    order: 0
    status: stable
    installed:
      - platform: opencode
        version: 1.0.0
        output: 00-memory.md
        checksum: 5cf17063...
        installed_at: '2026-05-14T07:56:48Z'
    available_targets: [opencode, gemini-cli, crush]
    dependencies: []
    conflicts: []
    provides: ['workstation-constraint']
    tags: [constraints, memory, performance]
    checksums:
      source: 5cf17063...
      built:
        opencode: 5cf17063...
        gemini-cli: 5cf17063...
        crush: 5cf17063...
```

**Editors**: `build.rb` updates build metadata (`available_targets`, `checksums.built`); `install.rb` updates `installed` list. Do not edit manually — use `query.rb` to inspect.

---

## Code Conventions

- **Ruby ≥ 2.7**, standard library only (no gems)
- **Frozen string literals** throughout
- **Pathname API** for all path operations (`Pathname#join`, `#expand_path`, `#realpath`)
- **YAML-first** configuration (PKGBUILD, registry)
- **Error handling**: `warn` for non-fatal, `raise` for fatal
- **Security**: Path traversal validation on all user-supplied paths (`output`, `target_dir`, `target_file`), transformer path realpath checks
- **Idempotency**: `--dry-run` makes zero filesystem changes; installs are idempotent (symlink replace, append dedup)

---

## Transformer Pattern

Built-in transformers:
- `copy` — identity (no change)
- `strip-frontmatter` — remove YAML frontmatter (`---` blocks)

Custom transformers: Ruby script defining `Transform` class with `.transform(content, pkgname: nil)` method. Reference in PKGBUILD as `transformer: custom:path/to/transformer.rb`. Paths are resolved relative to repo root (`ssot/`), validated with `realpath` to prevent symlink attacks.

**Example Custom Transformers** (in `ssot/transformers/`):
- `add-header.rb` — prepend title/header from frontmatter
- `strip-comments.rb` — remove HTML comments and normalize whitespace
- `format-code.rb` — auto-detect and tag code blocks (Ruby/Python)

See `ssot/transformers/` for implementations.

---

## Important Files

| `ssot/packages/` | Package source tree (PKGBUILD + src/) |
| `ssot/registry/platforms.yaml` | Platform definitions |
| `ssot/transformers/` | Custom transformer implementations |
| `ssot/build.rb` | Build orchestrator |
| `ssot/aggregate-skills.rb` | Vendor skill aggregation |
| `ssot/install.rb` | Platform installer |
| `ssot/uninstall.rb` | Platform uninstaller |
| `ssot/query.rb` | Package database query tool |
| `ssot/index.yaml` | Master package database |
| `ssot/index.json` | Machine-readable index |
| `ssot/build/index.yaml` | Build metadata (intermediate) |

---

## Testing & QA

### Automated Test Suite

Run the full test suite with `rake test` (Minitest):

```bash
rake test              # All tests (36 tests)
rake test_unit         # Unit tests only (25 tests)
rake test_integration  # Integration tests only (11 tests)
```

**Test coverage** (36 tests, 62 assertions, all passing):

| File | Tests | Coverage |
|------|-------|----------|
| `test/test_common.rb` | 25 | `compare_versions`, `format_version`, `validate_output_filename`, `validate_target_dir`, `expand_user_path`, `strip_frontmatter` |
| `test/test_integration.rb` | 11 | Build index, skill-bundle manifest, version comparison, index schema migration (pkgrel/epoch), transaction rollback (backup/restore/cleanup), cache integration |

### Manual Validation

```bash
# Dry-run install to preview changes
bin/ssot install opencode --dry-run

# Dry-run uninstall to preview removal
bin/ssot uninstall opencode --dry-run

# Check that installed state matches index (returns non-zero if mismatch)
bin/ssot check opencode

# Query installed packages
bin/ssot list
bin/ssot search security

# Full rebuild + reinstall
rm -rf ssot/build/ && bin/ssot build && bin/ssot install opencode

# Full cycle: install → verify → uninstall → verify
bin/ssot install opencode && bin/ssot check opencode && bin/ssot uninstall opencode && bin/ssot check opencode
```

---

## Migration from Old System

**Old system** (`scripts/` directory, `schema.yaml`-driven) is **deprecated**. New system uses PKGBUILD packages.

To migrate:
1. Move rule/skill content to `ssot/packages/<pkg>/src/`
2. Write PKGBUILD descriptor for each package
3. Add platform targets with appropriate `format` and `transformer`
4. Run `ruby ssot/build.rb && ruby ssot/aggregate-skills.rb`
5. Install: `ruby ssot/install.rb <platform>`
6. Update `ssot/registry/platforms.yaml` if new platforms added

**Old scripts** (`scripts/fetch-upstream.rb`, `scripts/transform.rb`, etc.) are preserved for backward compatibility but **should not be used**. New canonical scripts live in `ssot/` root.

---

## License

MIT — same as the upstream TCI project and vibe-security skill.
