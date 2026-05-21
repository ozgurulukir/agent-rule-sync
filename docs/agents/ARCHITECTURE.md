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
│   ├── packages/              # Package definitions (each = PKGBUILD + src/)
│   │   ├── <pkgname>/PKGBUILD
│   │   └── src/<source-files>
│   ├── registry/
│   │   └── platforms.yaml           # Platform definitions (type, paths, install methods)
│   ├── translators/                 # Custom translator scripts
│   │   ├── rule_to_skill.rb         # Rule → skill format
│   │   ├── rule_to_import.rb         # Rule → import format
│   │   ├── normalize_markdown.rb     # Markdown normalization
│   │   ├── agent_to_opencode.rb     # Agent → OpenCode frontmatter
│   │   ├── agent_to_cursor.rb       # Agent → Cursor manifest
│   │   └── agent_to_claude_code.rb  # Agent → Claude Code sections
│   ├── transformers/                # Custom transformer scripts
│   │   ├── add-header.rb
│   │   ├── strip-comments.rb
│   │   └── format-code.rb
│   ├── platforms/                   # Platform format profiles (informational)
│   │   ├── opencode.yaml, crush.yaml, goose.yaml ...
│   ├── index.yaml                   # Master package DB (installed state + metadata)
│   └── build/                       # Build artifacts (generated)
│       ├── index.yaml               # Build metadata (intermediate)
│       ├── catalog.json             # Package catalog (auto-generated)
│       ├── <platform>/              # Built artifacts per platform
│       │   └── ...
├── lib/
│   └── rulepack/                    # Library modules
│       ├── common.rb                # Constants, Config, basic IO, shared validation
│       ├── cli_parser.rb            # Unified CLI argument parsing
│       ├── logging.rb               # Centralized logging
│       ├── cache.rb                 # HTTP/Git caching
│       ├── backup.rb                # Backup/rollback support
│       ├── version.rb               # Version comparison (pacman vercmp)
│       ├── source.rb                # Source fetching (local, url, git)
│       ├── translate.rb             # Translator loading/dispatch
│       ├── transform.rb             # Transformer loading/dispatch
│       ├── schema_engine.rb         # Centralized Dynamic Schema Engine
│       ├── build_pipeline.rb        # 4-stage build pipeline orchestrator
│       ├── validation.rb            # PKGBUILD schema validation
│       ├── platform.rb              # Platform registry + path resolution
│       ├── install.rb               # Install dispatch
│       ├── installer.rb             # Installation engine (symlink/copy/inject/append)
│       ├── uninstall.rb             # Uninstall dispatch
│       ├── uninstaller.rb           # Uninstallation engine
│       ├── build.rb                 # Build orchestrator
│       ├── aggregate.rb             # Vendor skill aggregation
│       ├── query.rb                 # Package database queries
│       ├── verify.rb                # Installation verification
│       ├── fix.rb                   # Drift repair
│       ├── audit.rb                 # PKGBUILD descriptor auditing
│       ├── generate-catalog.rb     # Catalog JSON generation
│       └── lib/                     # Sub-modules
│           ├── transaction.rb       # Atomic transaction logs & rollback
│           ├── install_handlers.rb  # Low-level copy/symlink/inject routines
│           ├── skill_bundle.rb      # Skill-bundle resolution
│           └── tui_selector.rb      # Interactive terminal selection
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
| Oh My Pi | directory | `~/.omp/agent/` | Symlinked rule files |
| Crush | skill | `~/.config/crush/` | Single skill file |
| Goose | skill | `~/.local/share/goose/` | Single skill file (guardrails.md) |
| Droid | skill | `~/.factory/` | Single skill file (AGENTS.md) |
| Gemini CLI | import | `~/.config/gemini/` | `@import` lines in `cli_config.yaml` |
| Qwen Code | import | `~/.config/qwen/` | `@import` lines in `config.yaml` |
| Antigravity | directory | `~/.gemini/antigravity/` | Skill-bundle directory |
| Agents | directory | `~/.agents/` | Symlinked rule files |

### Project-Level Platforms

Configuration stored in the project repository, version-controlled alongside code.

| Platform | Type | Base Path (relative) | Format |
|----------|------|---------------------|--------|
| Cursor | directory | `.` → `.cursor/rules/` | Symlinked rule files |
| Windsurf | directory | `.` → `.windsurf/rules/` | Symlinked rule files |
| GitHub Copilot | import | `.` → `.github/` | Separate instruction file |
| Claude Code | directory | `.` → `.claude/rules/` | Symlinked rule files |
| Codex CLI | skill | `.` → `AGENTS.md` | Single skill file |

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
│   4-stage pipeline: │
│   1. Fetch sources  │  • Read local/URL/git (SHA256 verify)
│   2. Translate      │  • Platform-specific format conversion
│   3. Schema Engine  │  • Centralized formatting (frontmatter, emoji, bullets)
│   4. Transform      │  • Structural changes (copy/strip-frontmatter/custom)
│   - Write artifacts │  • Output → build/<platform>/
│   - Update index    │  • Write build/index.yaml + catalog.json
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
│   - Create dirs     │  • Compute install paths (rules, skills, agents)
│   - Symlink/copy    │  • Perform install (symlink/copy/inject/append)
│   - Update index    │  • Write installed records to data/index.yaml
│   - Vendor copy     │  • For skill agents: copy vendor file to agent location
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Query / Verify    │  bin/rulepack query, bin/rulepack verify <platform>
│   - List packages   │  • Inspect data/index.yaml
│   - Show details    │  • Verify installed checksums
│   - Search          │  • Validate sync state
│   - Check           │
└─────────────────────┘
```

---

## Data Flow

**Build** (`lib/rulepack/build.rb`):
1. Load all `PKGBUILD` files from `data/packages/*/`
2. For each source entry: read local file or fetch URL/git (with SHA256 verification)
3. 4-stage pipeline per target:
   - **Fetch**: read/cached source
   - **Translate**: platform-specific format conversion (e.g., rule → skill, agent → platform format)
   - **Schema Engine**: centralized formatting (frontmatter strip/inject, emoji policy, heading style, bullet style)
   - **Transform**: structural changes (copy, strip-frontmatter, custom Ruby)
4. Write built artifact to `build/<platform>/<output>`
5. Record checksums in `build/index.yaml`
6. Generate `catalog.json`

**Aggregate** (`lib/rulepack/aggregate.rb`):
1. Load `build/index.yaml` to find packages with `format: skill` targets
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
   - Resolve install path (directory: `rules_dir`/`skills_dir`/`agents_dir`, import: `config_file`, skill: `skill_file`)
   - `--rules-to <file>` can redirect rules to a single file (e.g., `AGENTS.md`) instead of `rules_dir`
   - Perform install:
     - `symlink`: create relative symlink (replace if stale)
     - `copy`: copy if checksum differs (agents always use copy)
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
- Commands: `list-packages`, `list-platforms`, `installed <platform>`, `show <pkg>`, `search <tag>`, `check`
- Sources data from `data/index.yaml` and `build/index.yaml`

---

## Index Database

`data/index.yaml` (master package database):

```yaml
version: 3.0
generated: '2026-05-14T...'
packages:
  memory:
    pkgver: 1.0.0
    pkgrel: 1
    epoch: 0
    pkgdesc: Workstation Memory Constraints rule
    order: 0
    pkg_type: rule
    status: stable
    installed:
      - platform: opencode
        output: 00-memory.md
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
    targets:
      - platform: opencode
        format: directory
        output: 00-memory.md
      - platform: cursor
        format: directory
        output: workstation-memory.md
```

Key fields:
- `installed[]` — one record per platform+output combination
- `checksums.built[<platform>]` — artifact checksum after transformation
- `available_targets` — list of platforms this package can deploy to
- `targets[]` — raw target definitions from PKGBUILD
- `pkg_type` — package type: `rule`, `skill`, `agent`, or `hybrid`

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
pkg_type: rule
order: 0

source:
  - type: local
    path: src/my-rule.md

targets:
  - platform: opencode
    format: directory
    output: 00-my-rule.md
    install:
      type: symlink
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

The **translate step** runs *before* the transform step. It converts content from one format family to another — e.g., flat rule → skill, agent → platform-specific format.

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

**Agent translators** convert agent definitions to platform-specific formats:

| Translator | Target Platform | Transformation |
|---|---|---|
| `agent_to_opencode.rb` | OpenCode | Wraps prompt in YAML frontmatter (name, model, tools) |
| `agent_to_cursor.rb` | Cursor | Passes markdown through; generates `agent.json` manifest from `agent_config` |
| `agent_to_claude_code.rb` | Claude Code | Adds `## Metadata`, `## System Prompt`, `## Capabilities` sections |

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
