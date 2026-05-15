# SSoT Architecture — PKGBUILD v4

## Overview

The Single Source of Truth (SSoT) system uses a **package-based architecture** inspired by Arch Linux's PKGBUILD. Each rule or skill is a package with a declarative build descriptor. The system builds platform-specific artifacts and installs them to configured agent platforms.

**Design goals**:
- Single authoritative source → multiple agent platforms
- Per-platform format transformation
- Change detection via SHA256 checksums
- Atomic installs with rollback capability
- Support for both user-level (global) and project-level (repo) platforms

---

## Directory Structure

```
your-project/
├── ssot/
│   ├── packages/                     # Package definitions (each = PKGBUILD + src/)
│   │   ├── memory/PKGBUILD
│   │   │   └── src/00-memory.md
│   │   ├── shell/PKGBUILD
│   │   │   └── src/01-shell.md
│   │   ├── vibe-security/PKGBUILD
│   │   │   └── src/SKILL.md
│   │   ├── cursor-compat/PKGBUILD      # Cursor IDE compatibility rules
│   │   │   └── src/AGENTS.md
│   │   └── ...
│   ├── registry/
│   │   └── platforms.yaml           # Platform definitions (type, paths, install methods)
│   ├── lib/                         # Library modules
│   │   ├── common.rb                # Constants, Config, basic IO
│   │   ├── logging.rb, cache.rb, backup.rb, version.rb
│   │   ├── source.rb, transform.rb, validation.rb
│   │   ├── platform.rb, uninstall.rb, install.rb
│   ├── translators/                 # Custom translator scripts
│   │   └── rule-to-skill.rb
│   ├── transformers/                # Custom transformer scripts
│   │   ├── add-header.rb
│   │   ├── strip-comments.rb
│   │   └── format-code.rb
│   ├── platforms/                   # Platform format profiles (informational)
│   │   ├── opencode.yaml, crush.yaml, goose.yaml ...
│   ├── build.rb                     # Build orchestrator
│   ├── aggregate-skills.rb          # Vendor skill aggregation
│   ├── install.rb                   # Platform installer (CLI)
│   ├── uninstall.rb                 # Platform uninstaller
│   ├── query.rb                     # Package database queries
│   ├── index.yaml                   # Master package DB (installed state + metadata)
│   ├── index.json                   # Machine-readable index (auto-generated)
│   └── build/
│       ├── index.yaml               # Build metadata (intermediate)
│       ├── opencode/                # Built artifacts per platform
│       │   ├── 00-memory.md
│       │   └── ...
│       ├── crush/
│       │   └── skills/vendor/crush.md
│       └── ...
├── docs/
│   └── agents/
│       ├── README.md                # This doc index
│       ├── ARCHITECTURE.md          # (this file)
│       ├── PLATFORMS.md             # Platform reference
│       ├── USAGE.md                 # User guide
│       ├── REFERENCE.md             # PKGBUILD/API reference
│       ├── TRANSFORMS.md            # Transformer docs
│       ├── UPSTREAM.md              # Upstream source tracking
│       └── agents/                  # Per-agent guides
│           ├── opencode.md
│           ├── cursor.md
│           └── ...
├── AGENTS.md                        # Repository AI assistant guidelines
└── README.md                        # Project overview
```

---

## Platform Categories

Agents fall into two configuration scopes:

### User-Level Platforms

Global configuration stored in the user's home directory, applies across all projects.

| Platform | Type | Base Path | Format |
|----------|------|-----------|--------|
| OpenCode | directory | `~/.config/opencode/` | Symlinked rule files |
| Oh My Pi | directory | `~/.config/oh-my-pi/` | Symlinked rule files |
| Crush | skill | `/usr/local/share/crush/` | Single skill file |
| Goose | skill | `~/.local/share/goose/` | Single skill file (guardrails.md) |
| Droid | skill | `~/.config/droid/` | Single skill file (AGENTS.md) |
| Gemini CLI | import | `~/.config/gemini/` | `@import` lines in GEMINI.md |
| Qwen Code | import | `~/.config/qwen/` | `@import` lines in QWEN.md |
| Agents | directory | `~/.config/agents/` | Symlinked rule files |

### Project-Level Platforms

Configuration stored in the project repository, version-controlled alongside code.

| Platform | Type | Base Path (relative) | Format |
|----------|------|---------------------|--------|
| Cursor | directory | `.` → `.cursor/rules/` | Symlinked rule files |
| Windsurf | directory | `.` → `.windsurf/rules/` | Symlinked rule files |
| GitHub Copilot | import | `.` → `.github/` | Separate instruction file |
| Claude Code | directory | `.` → `.claude/rules/` | Symlinked rule files |
| Codex CLI | skill | `.` → `AGENTS.md` | Single skill file |
| Antigravity | directory | `.` → `.agent/skills/` | Skill-bundle directory |

> **Key difference**: User-level platforms install to fixed paths in `$HOME`. Project-level platforms require `--project PATH` flag during install/uninstall, and paths are resolved relative to the project root.

---

## Pipeline

```
┌─────────────┐
│  PKGBUILDs  │  ssot/packages/*/PKGBUILD (YAML descriptors)
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   Build Phase       │  ruby ssot/build.rb
│   - Load PKGBUILDs  │  • Validate schema
│   - Fetch sources   │  • Read local/URL (SHA256 verify)
│   - Transform       │  • Apply transformer (copy/strip/custom)
│   - Write artifacts │  • Output → ssot/build/<platform>/
│   - Update index    │  • Write build/index.yaml + index.json
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Aggregate Phase   │  ruby ssot/aggregate-skills.rb
│   (skill agents)    │  • Collect rule fragments (format=skill)
│   - Header          │  • Add agent-specific skills
│   - Rules (ordered) │  • Add common skills
│   - Agent extras    │  • Concatenate with "---" separators
│   - Common skills   │  • Write to build/<agent>/skills/vendor/<agent>.md
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Install Phase     │  ruby ssot/install.rb <platform> [--project PATH]
│   - Resolve paths   │  • Lookup platform config (registry)
│   - Create dirs     │  • Compute install paths
│   - Symlink/copy    │  • Perform install (symlink/copy/inject/append)
│   - Update index    │  • Write installed records to index.yaml
│   - Vendor copy     │  • For skill agents: copy vendor file to agent location
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Query / Verify    │  ruby ssot/query.rb, ruby ssot/install.rb --check
│   - List packages   │  • Inspect index.yaml / index.json
│   - Show details    │  • Verify installed checksums
│   - Search          │  • Validate sync state
│   - Check           │
└─────────────────────┘
```

---

## Data Flow

**Build** (`build.rb`):
1. Load all `PKGBUILD` files from `packages/*/`
2. For each source entry: read local file or fetch URL (with SHA256 verification)
3. Apply transformer per target (built-in or custom Ruby script)
4. Write built artifact to `build/<platform>/<output>`
5. Record checksums in `build/index.yaml`
6. Generate `index.json` (machine-readable)

**Aggregate** (`aggregate-skills.rb`):
1. Load `index.yaml` to find packages with `format: skill` targets
2. For each skill agent (crush, goose, droid, codex):
   - Read agent-specific header (if any)
   - Collect all rule fragments in `order` sequence
   - Append common skills (`skills/common/*.md`)
   - Append agent-specific extras (`skills/agent-specific/<agent>/*.md`)
   - Write concatenated vendor skill to `build/<agent>/skills/vendor/<agent>.md`

**Install** (`install.rb`):
1. Load `build/index.yaml` and platform registry
2. For project-level platforms, resolve `--project` dir (default: `Dir.pwd`)
3. For each package with target matching platform:
   - Resolve install path (directory: `rules_dir`/`skills_dir`, import: `config_file`, skill: `skill_file`)
   - Perform install:
     - `symlink`: create relative symlink (replace if stale)
     - `copy`: copy if checksum differs
     - `inject`: prepend `@import` line to config (deduplicate)
     - `append`: append content (vendor skill aggregation)
   - Record installation in `index.yaml` (platform, output, checksum, timestamp)
4. For skill platforms: run aggregation, then copy vendor file to agent's location

**Uninstall** (`uninstall.rb`):
1. Load `index.yaml`, find all installed records for platform
2. For each installed artifact: remove symlink/file
3. Clean installed records from `index.yaml`
4. For skill platforms: re-aggregate (excluding removed packages) and copy updated vendor file
5. Write index atomically

**Query** (`query.rb`):
- Commands: `list-packages`, `list-platforms`, `installed --platform <p>`, `show <pkg>`, `search <tag>`, `check`
- Prefers `index.yaml`, falls back to `index.json`

---

## Index Database

`ssot/index.yaml` (master package database):

```yaml
version: 3.0
generated: '2026-05-14T...'
packages:
  memory:
    pkgver: 1.0.0
    pkgdesc: Workstation Memory Constraints rule
    order: 0
    status: stable
    installed:
      - platform: opencode
        output: 00-memory.md
        checksum: <sha256>
        installed_at: '2026-05-14T...'
      - platform: cursor
        output: workstation-memory.md
        checksum: <sha256>
        installed_at: '2026-05-14T...'
    available_targets: [opencode, cursor, windsurf, ...]
    dependencies: []
    conflicts: []
    provides: [workstation-constraint]
    tags: [constraints, memory]
    checksums:
      source: <sha256>
      built:
        opencode: <sha256>
        cursor: <sha256>
    targets:
      - platform: opencode
        format: directory
        output: 00-memory.md
        transformer: copy
      - platform: cursor
        format: directory
        output: workstation-memory.md
        transformer: copy
```

Key fields:
- `installed[]` — one record per platform+output combination
- `checksums.built[<platform>]` — artifact checksum after transformation
- `available_targets` — list of platforms this package can deploy to
- `targets[]` — raw target definitions from PKGBUILD

`ssot/index.json` is auto-generated from `index.yaml` for programmatic access.

---

## PKGBUILD Format

See [Reference](REFERENCE.md) for full specification.

**Minimal example:**
```yaml
---
pkgname: my-rule
pkgver: '1.0.0'
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

checksums:
  source: null   # auto-filled by build
  built: {}
```

---

## Transformer System

Built-in transformers:
- `copy` — identity (no transformation)
- `strip-frontmatter` — remove YAML frontmatter block (`---` delimited)

Custom transformers: Ruby scripts in `ssot/transformers/` defining a `Transform` class:

```ruby
class Transform
  def initialize(content:, pkgname:)
    @content = content
    @pkgname = pkgname
  end

  def transform
    # ... modify @content ...
    @content
  end
end
```

Referenced as `transformer: custom:transformers/example.rb`. Path resolved relative to repo root, validated with `realpath` to prevent symlink attacks.

See [Transforms](TRANSFORMS.md) for details.

---

## Security

- **Path traversal**: All `output` and `target_dir` values validated (no `..`, no absolute paths)
- **Transformer injection**: Custom transformer paths resolved with `realpath` and must be within repo root
- **URL sources**: SHA256 checksum enforced; redirects followed but content validated
- **Index writes**: Atomic via tempfile + rename
- **Dry-run**: Zero filesystem changes

---

## See Also

- [Platforms](PLATFORMS.md) — Complete platform reference
- [Usage](USAGE.md) — Installation and workflow guide
- [Reference](REFERENCE.md) — PKGBUILD schema, transformer API, index format
- [Transforms](TRANSFORMS.md) — Transformer documentation
- [Upstream](UPSTREAM.md) — Upstream source management
