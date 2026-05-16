# Rulepack Architecture — PKGBUILD v4

## Overview

The Rulepack system uses a **package-based architecture** inspired by Arch Linux's PKGBUILD. Each rule or skill is a package with a declarative build descriptor. The system builds platform-specific artifacts and installs them to configured agent platforms.

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
├── data/
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
│   ├── translators/                 # Custom translator scripts
│   │   └── rule_to_skill.rb
│   ├── transformers/                # Custom transformer scripts
│   │   ├── add-header.rb
│   │   ├── strip-comments.rb
│   │   └── format-code.rb
│   ├── platforms/                   # Platform format profiles (informational)
│   │   ├── opencode.yaml, crush.yaml, goose.yaml ...
│   ├── index.yaml                   # Master package DB (installed state + metadata)
│   ├── index.json                   # Machine-readable index (auto-generated)
│   └── build/                       # Build artifacts (generated)
│       ├── index.yaml               # Build metadata (intermediate)
│       ├── opencode/                # Built artifacts per platform
│       │   ├── 00-memory.md
│       │   └── ...
│       ├── crush/
│       │   └── skills/vendor/crush.md
│       └── ...
├── lib/
│   └── rulepack/                    # Library modules
│       ├── common.rb                # Constants, Config, basic IO
│       ├── logging.rb, cache.rb, backup.rb, version.rb
│       ├── source.rb, transform.rb, validation.rb
│       ├── platform.rb, uninstall.rb, install.rb
│       ├── build.rb                 # Build orchestrator
│       ├── aggregate.rb             # Vendor skill aggregation
│       ├── query.rb                 # Package database queries
│       └── ...
├── bin/
│   └── rulepack                     # CLI entry point
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
├── README.md                        # Project overview
└── Rakefile                         # Test runner
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
│  PKGBUILDs  │  data/packages/*/PKGBUILD (YAML descriptors)
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   Build Phase       │  bin/rulepack build
│   - Load PKGBUILDs  │  • Validate schema
│   - Fetch sources   │  • Read local/URL (SHA256 verify)
│   - Transform       │  • Apply transformer (copy/strip/custom)
│   - Write artifacts │  • Output → build/<platform>/
│   - Update index    │  • Write build/index.yaml + index.json
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Aggregate Phase   │  bin/rulepack aggregate
│   (skill agents)    │  • Collect rule fragments (format=skill)
│   - Header          │  • Add agent-specific skills
│   - Rules (ordered) │  • Add common skills
│   - Agent extras    │  • Concatenate with "---" separators
│   - Common skills   │  • Write to build/<agent>/skills/vendor/<agent>.md
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Install Phase     │  bin/rulepack install <platform> [--project PATH]
│   - Resolve paths   │  • Lookup platform config (registry)
│   - Create dirs     │  • Compute install paths
│   - Symlink/copy    │  • Perform install (symlink/copy/inject/append)
│   - Update index    │  • Write installed records to data/index.yaml
│   - Vendor copy     │  • For skill agents: copy vendor file to agent location
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Query / Verify    │  bin/rulepack query, bin/rulepack check <platform>
│   - List packages   │  • Inspect data/index.yaml / data/index.json
│   - Show details    │  • Verify installed checksums
│   - Search          │  • Validate sync state
│   - Check           │
└─────────────────────┘
```

---

## Data Flow

**Build** (`lib/rulepack/build.rb`):
1. Load all `PKGBUILD` files from `data/packages/*/`
2. For each source entry: read local file or fetch URL (with SHA256 verification)
3. Apply transformer per target (built-in or custom Ruby script)
4. Write built artifact to `build/<platform>/<output>`
5. Record checksums in `build/index.yaml`
6. Generate `index.json` (machine-readable)

**Aggregate** (`lib/rulepack/aggregate.rb`):
1. Load `data/index.yaml` to find packages with `format: skill` targets
2. For each skill agent (crush, goose, droid, codex):
   - Read agent-specific header (if any)
   - Collect all rule fragments in `order` sequence
   - Append common skills (`data/skills/common/*.md`)
   - Append agent-specific extras (`data/skills/agent-specific/<agent>/*.md`)
   - Write concatenated vendor skill to `build/<agent>/skills/vendor/<agent>.md`

**Install** (`lib/rulepack/install.rb`):
1. Load `build/index.yaml` and platform registry
2. For project-level platforms, resolve `--project` dir (default: `Dir.pwd`)
3. For each package with target matching platform:
   - Resolve install path (directory: `rules_dir`/`skills_dir`, import: `config_file`, skill: `skill_file`)
   - Perform install:
     - `symlink`: create relative symlink (replace if stale)
     - `copy`: copy if checksum differs
     - `inject`: prepend `@import` line to config (deduplicate)
     - `append`: append content (vendor skill aggregation)
   - Record installation in `data/index.yaml` (platform, output, checksum, timestamp)
4. For skill platforms: run aggregation, then copy vendor file to agent's location

**Uninstall** (`lib/rulepack/uninstaller.rb`):
1. Load `data/index.yaml`, find all installed records for platform
2. For each installed artifact: remove symlink/file
3. Clean installed records from `data/index.yaml`
4. For skill platforms: re-aggregate (excluding removed packages) and copy updated vendor file
5. Write index atomically

**Query** (`lib/rulepack/query.rb`):
- Commands: `list-packages`, `list-platforms`, `installed --platform <p>`, `show <pkg>`, `search <tag>`, `check`
- Prefers `data/index.yaml`, falls back to `data/index.json`

---

## Index Database

`data/index.yaml` (master package database):

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

`data/index.json` is auto-generated from `index.yaml` for programmatic access.

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

Custom transformers: Ruby scripts in `data/transformers/` defining a `Transform` class:

```ruby
# data/transformers/example.rb
class Transform
  def initialize(content:, pkgname:)
    @content = content    # Source file content (string)
    @pkgname = pkgname    # Package name (symbol, optional)
  end

  def transform
    # Modify @content as needed
    @content
  end
end
```

---

## Translator System

The **translate step** runs *before* the transform step. It converts content from one format family to another — e.g., flat rule → skill, markdown → import.

Custom translators: Ruby scripts in `data/translators/` defining a `Translator` class:

```ruby
# data/translators/example.rb
class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname]
    # Transform content
    content
  end
end
```

---

## Platform Registry

Platforms are defined in `data/registry/platforms.yaml`. This is the central configuration for all supported agents, their types, scopes, base paths, and install methods.

---

## Skill Aggregation

For skill-based agents (crush, goose, droid, codex), the system aggregates rule fragments and skills into a single vendor skill file. This is handled by `lib/rulepack/aggregate.rb`.

The aggregation:
1. Reads agent-specific header from `data/skills/agent-specific/<agent>/*.md`
2. Collects all rule fragments in `order` sequence
3. Appends common skills from `data/skills/common/*.md`
4. Concatenates with `---\n\n` separators
5. Writes to `build/<agent>/skills/vendor/<agent>.md`

---

## Caching

The system caches:
- **HTTP fetches**: by SHA256 of fetched content
- **Git clones**: by commit hash
- **Extracted sources**: in `cache/<key>/extracted/`

Cache directory: `cache/` (configurable via `RULEPACK_CACHE_DIR`).

---

## Version Management

Packages use pacman-style versioning: `epoch:pkgver-pkgrel`.

- **epoch** (default 0): Overrides versioning scheme changes
- **pkgver** (string): Upstream version
- **pkgrel** (default 1): Package release increment

Upgrade: Automatic on re-install if newer version detected.
Downgrade: Blocked by default; use `--force` to allow.

---

## Security

- **Path traversal protection**: All file paths validated with `realpath` to ensure they stay within repo
- **Safe YAML loading**: `YAML.safe_load` used everywhere
- **Command injection prevention**: All `system()` calls use array form
- **Checksum verification**: All sources verified against expected SHA256
