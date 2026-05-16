# Rulepack — PKGBUILD-based Agent Rule Manager

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

## Supported Platforms (14 agents)

| Agent | Type | Scope | Config Location | Install Command |
|-------|------|-------|-----------------|-----------------|
| [OpenCode](docs/agents/agents/opencode.md) | directory | user | `~/.config/opencode/rules/` | `bin/rulepack install opencode` |
| [Oh My Pi](docs/agents/agents/oh-my-pi.md) | directory | user | `~/.config/oh-my-pi/rules/` | `bin/rulepack install oh-my-pi` |
| [Crush](docs/agents/agents/crush.md) | skill | user | `/usr/local/share/crush/crush.md` | `bin/rulepack install crush` |
| [Goose](docs/agents/agents/goose.md) | skill | user | `~/.local/share/goose/goose.md` | `bin/rulepack install goose` |
| [Droid](docs/agents/agents/droid.md) | skill | user | `~/.config/droid/droid.md` | `bin/rulepack install droid` |
| [Gemini CLI](docs/agents/agents/gemini-cli.md) | import | user | `~/.config/gemini/GEMINI.md` | `bin/rulepack install gemini-cli` |
| [Qwen Code](docs/agents/agents/qwen-code.md) | import | user | `~/.config/qwen/QWEN.md` | `bin/rulepack install qwen-code` |
| [Cursor](docs/agents/agents/cursor.md) | directory | project | `.cursor/rules/` | `bin/rulepack install cursor --project .` |
| [Windsurf](docs/agents/agents/windsurf.md) | directory | project | `.windsurf/rules/` | `bin/rulepack install windsurf --project .` |
| [GitHub Copilot](docs/agents/agents/github-copilot.md) | import | project | `.github/copilot-instructions.md` | `bin/rulepack install github-copilot --project .` |
| [Claude Code](docs/agents/agents/claude-code.md) | directory | project | `.claude/rules/` | `bin/rulepack install claude-code --project .` |
| [Codex CLI](docs/agents/agents/codex.md) | skill | project | `AGENTS.md` | `bin/rulepack install codex --project .` |
| [Antigravity](docs/agents/agents/antigravity.md) | directory | project | `.agent/skills/` | `bin/rulepack install antigravity --project .` |
| [Agents](docs/agents/agents/agents.md) | directory | user | `~/.config/agents/rules/` | `bin/rulepack install agents` |

**Scope**: `user` = global (home directory), `project` = per-project (requires `--project` flag)

See [Platforms](docs/agents/PLATFORMS.md) for full details.

---

## Architecture & Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                     PKGBUILD Packages (data/packages/)             │
│  Each package: pkgname, source, targets[platform], transformer  │
│  memory/PKGBUILD, shell/PKGBUILD, vibe-security/PKGBUILD        │
└────────────────────────────┬─────────────────────────────────────┘
                             │ build (build.rb)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Build Artifacts (build/<platform>/)          │
│  Platform-specific outputs: rules, skills, imports              │
│  opencode/00-memory.md, crush/skills/vendor/crush.md            │
└────────────────────────────┬─────────────────────────────────────┘
                             │ aggregate (aggregate.rb)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                   Vendor Skills (build/<platform>/skills/vendor/)      │
│  Combined skill bundles per agent: crush.md, goose.md, droid.md │
└────────────────────────────┬─────────────────────────────────────┘
                             │ install (install.rb)
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

**Single Entry Point**: `bin/rulepack` wraps all pipeline commands: `build`, `install`, `uninstall`, `list`, `show`, `search`, `status`, `check`, `platforms`, `help`.

**Key Pipeline Steps**:

1. **Build** (`build.rb`) — Load all PKGBUILDs from `data/packages/`, fetch sources (local/URL with SHA256), apply translators (content format conversion, runs first), apply transformers (copy/strip-frontmatter/custom), write platform-specific artifacts to `build/<platform>/`, update `build/index.yaml` and `data/index.yaml` with build metadata.

2. **Aggregate** (`aggregate.rb`) — For skill-based agents (Crush, Goose, Droid), collect rule fragments and common/agent-specific skills, concatenate into a single vendored skill file per agent under `build/<agent>/skills/vendor/`.

3. **Install** (`install.rb <platform> [--dry-run]`) — Read `data/index.yaml`, for each package built for target platform, install via symlink/copy/inject/append depending on format and platform registry. Update `data/index.yaml` with installed state. Supports `--all` (all platforms), `--targets <pkg>` (show targets), `--check` (verify), `--dry-run`, `--force`, `--select`. For skill-bundles >1 sub-skill, shows interactive numbered menu in a TTY.

4. **Query** (`query.rb`) — Inspect package database: list packages, show details, search, check installed status.

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

## Creating a New Package

To add a new rule or skill as a Rulepack package, follow these steps:

### 1. Create the package directory

```bash
mkdir -p data/packages/<pkgname>/src/
```

### 2. Add the source file

Place your rule or skill content in `data/packages/<pkgname>/src/` as a Markdown file:

```bash
touch data/packages/<pkgname>/src/<filename>.md
```

The source file is your canonical content — all platform-specific transformations start from this file.

### 3. Write the PKGBUILD descriptor

Create `data/packages/<pkgname>/PKGBUILD` (YAML). At minimum:

```yaml
---
pkgname: my-rule
pkgver: '1.0.0'
pkgrel: 1
epoch: 0
pkgdesc: What this rule/skill does
arch: any
order: 0

source:
  - type: local
    path: src/<filename>.md

targets:
  - platform: opencode          # first target platform
    format: directory
    output: <filename>.md
    transformer: copy
    install:
      type: symlink

checksums:
  source: null
  built: {}

dependencies: []
conflicts: []
provides: []
tags:
  - <tag1>
  - <tag2>
maintainer: null
license: MIT
```

See [PKGBUILD Format](#pkgbuild-format) above for all available fields, source types (`local`/`url`/`git`), target formats (`directory`/`import`/`skill`/`skill-bundle`), and transformers (`copy`/`strip-frontmatter`/`custom:path`).

### 4. Choose target platforms

Refer to the [Supported Platforms](#supported-platforms-14-agents) table to pick platforms. Each target entry in PKGBUILD maps to one platform:

| Platform type | format | output | install.type |
|--------------|--------|--------|-------------|
| `directory` agents (OpenCode, Cursor, etc.) | `directory` | `filename.md` | `symlink` or `copy` |
| `skill` agents (Crush, Goose, Droid) | `skill` | `filename.md` | inherits from registry (`copy`) |
| `import` agents (Gemini CLI, Qwen Code) | `import` | `filename.md` | `copy` or `inject` |
| Multi-skill bundles | `skill-bundle` | `.` | `copy` with `target_dir` |

### 5. Build and install

```bash
# Build all packages (your new package included)
bin/rulepack build

# Install to a specific platform
bin/rulepack install opencode

# Verify it's installed
bin/rulepack check opencode
```

### Quick reference table

| Step | Action | File/Directory |
|------|--------|---------------|
| 1 | Create package dir | `data/packages/<pkgname>/` |
| 2 | Add source file | `data/packages/<pkgname>/src/<file>.md` |
| 3 | Write descriptor | `data/packages/<pkgname>/PKGBUILD` |
| 4 | Set targets | `targets:` array in PKGBUILD |
| 5 | Build | `bin/rulepack build` |
| 6 | Install | `bin/rulepack install <platform>` |

---

## Uninstall

**Uninstall** (`uninstall.rb <platform> [--dry-run]`) — Remove packages from a target platform.

- Removes symlinks/files (respects `target_dir` overrides)
- Cleans installed records from `data/index.yaml`
- Re-aggregates vendor skills for skill-based agents (to remove package contributions)
- Idempotent: safe to run multiple times

```bash
# Preview what would be removed
bin/rulepack uninstall opencode --dry-run

# Actually uninstall
bin/rulepack uninstall opencode

# After uninstall, verify
bin/rulepack check opencode
```

**Note**: For skill-based platforms (Crush, Goose, Droid), uninstall removes the package's contribution from the vendored skill file and regenerates it. For directory platforms, symlinks/files are removed. For import platforms, `@import` lines are not automatically removed (manual config edit required — future enhancement).

---

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `data/` | Single Source of Truth root |
| `data/packages/` | **Package definitions** — each subdir contains PKGBUILD and source files |
| `data/packages/<pkg>/PKGBUILD` | Package build descriptor (pkgname, source, targets, transformer) |
| `data/packages/<pkg>/src/` | Raw source files for that package (rules, skill content) |
| `data/skills/` | **User skill/repo workspace** — local skill content, upstream repos, vendor output |
| `data/skills/common/` | Shared skill definitions (referenced by vendor aggregation) |
| `data/skills/agent-specific/` | Per-agent skill overrides (referenced by vendor aggregation) |
| `data/registry/platforms.yaml` | **Platform registry** — defines platform types, paths, install methods |

**Note**: Old system files (`scripts/`, `data/schema.yaml`, `data/rules/`, `data/docs/`, `data/vendor/`) are no longer used by the new PKGBUILD system.

---

**Development Commands**

**Single Entry Point** (preferred):

```bash
bin/rulepack build              # Build all packages + aggregate vendor skills
bin/rulepack install opencode   # Install to platform
bin/rulepack uninstall opencode # Uninstall from platform
bin/rulepack list               # List all packages
bin/rulepack status             # Show system status
bin/rulepack show memory        # Show package details
bin/rulepack search security    # Search packages
bin/rulepack platforms           # List platforms
bin/rulepack check opencode     # Verify installed state
bin/rulepack verify opencode    # Comprehensive index vs disk check
bin/rulepack fix opencode       # Repair drift automatically
bin/rulepack help               # Show help
```

**Pipeline Execution** (run from repo root):

```bash
# Build all packages: fetch, transform, write artifacts, update index
ruby lib/rulepack/build.rb

# Aggregate vendor skill files for skill-based agents (Crush, Goose, Droid)
ruby lib/rulepack/aggregate.rb

# Install packages to a target platform
ruby lib/rulepack/install.rb <platform> [--dry-run]

# Query package database
ruby lib/rulepack/query.rb <command> [options]
```

**Common Commands**:
```bash
# Full workflow: build → aggregate → install
ruby lib/rulepack/build.rb && ruby lib/rulepack/aggregate.rb && ruby lib/rulepack/install.rb opencode

# Preview without changes
ruby lib/rulepack/install.rb opencode --dry-run

# Install to all platforms
ruby lib/rulepack/install.rb --all --dry-run

# Show which platforms a package targets
ruby lib/rulepack/install.rb --targets memory

# Verify installed state
ruby lib/rulepack/check opencode

# Uninstall from a platform
ruby lib/rulepack/uninstall.rb opencode
ruby lib/rulepack/uninstall.rb opencode --dry-run

# Query installed packages
ruby lib/rulepack/query.rb installed --platform opencode

# List all packages
ruby lib/rulepack/query.rb list-packages

# Show package details
ruby lib/rulepack/query.rb show <pkgname>

# Search packages by tag
ruby lib/rulepack/query.rb search <tag>

# Force downgrade (if needed)
ruby lib/rulepack/install.rb opencode --force
```

---

## PKGBUILD Format

Each package is defined in `data/packages/<pkgname>/PKGBUILD` (YAML):

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

**Sub-skill Selection** (`--select`):
Use `--select` to install only specific sub-skills from a bundle, or skip the flag for an interactive menu:

```bash
# Install only the "auth" sub-skill
bin/rulepack install golang-security --select auth

# Install multiple sub-skills
bin/rulepack install golang-security --select auth,sql,xss

# Install all sub-skills (default, no --select)
bin/rulepack install golang-security
```

When running in a real terminal without `--select`, Rulepack shows a pacman-style numbered menu:

```
📦 antigravity-skills contains 306 sub-skills.
Select sub-skills to install:
  1) accessibility-compliance-accessibility-audit
  2) agent-orchestration-improve-agent
  ...
  306) workflow-patterns

Enter numbers (e.g. 1,2,3, 5-10, or 'all'):
```

- Numbers and ranges: `1,2,3` or `5-10` or `1-5,10,50-55`
- `all` or empty → install all sub-skills
- Only activates in a real TTY; pipes/CI skip the menu and install all

Sub-skill names are the top-level directory names within the bundle (e.g., `auth/`, `sql-injection/`).

**Manifest Format**:
Build generates `manifest.json` with per-sub-skill checksums:

```json
{
  "pkgname": "golang-security-bundle",
  "platform": "cursor",
  "generated_at": "2026-05-14T16:01:56Z",
  "sub_skills": [
    {
      "path": "golang-security",
      "name": "golang-security",
      "sha256": "a38396e7...",
      "files": {
        "golang-security/SKILL.md": "df1f23e9..."
      }
    }
  ]
}
```

**Behavior**:
- Build: Entire source directory is copied recursively to `build/<platform>/<pkgname>/`; manifest lists each top-level subdirectory as a sub-skill with per-file SHA256 checksums
- Install: With `--select`, only the specified sub-skill directories are copied; without `--select`, all sub-skills are installed
- Uninstall: Target directory tree is removed
- Index: `output` recorded as `.`; no single-file checksum (directory checksum future work)

**Meta-packages** (documentation-only):
The `depends` field is metadata stored in the index for human/LLM reference. It groups related packages or sub-skills under a virtual name. **Dependency resolution is not implemented** (deferred — see P2.2). Users install sub-packages individually.

```yaml
pkgname: golang-security-all
pkgdesc: All Go security skills (meta-package)
depends:
  - golang-security/auth
  - golang-security/sql-injection
  - golang-security/xss
```

To install all sub-skills of a meta-package:
```bash
bin/rulepack install golang-security --select auth,sql,xss
```

---


## Platform Registry

Platforms are defined in `data/registry/platforms.yaml`:

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

`data/index.yaml` is the master package database (YAML). Structure:

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

## Translate + Transform Pipeline

The build pipeline runs **two** sequential content-processing steps per target:

```
Source (fetched) → TRANSLATE → TRANSFORM → Build Artifact
```

### Translate (Content Format Conversion)

Platform-specific content conversion — changes the format family of the content. Runs **before** transform.

| Field | Values | Default |
|-------|--------|---------|
| `translate` | `copy`, `custom:<path>` | `nil` (no-op) |

```yaml
targets:
  - platform: crush
    format: skill
    output: SKILL.md
    translate: custom:translators/rule_to_skill.rb   # ← runs first
    transformer: strip-frontmatter                    # ← runs second
```

**When to use**: Converting between format families (flat rules → skill, markdown → import, raw → normalized).

**When NOT to use**: Just stripping frontmatter → use `strip-frontmatter` transformer. Just copying → omit both `translate` and `transformer`.

### Transform (Structural Changes)

Structure/format changes applied after translation.

| Built-in | Custom |
|----------|--------|
| `copy` | `custom:transformers/example.rb` |
| `strip-frontmatter` | |

### Translator API

Translators live in `data/translators/`. Class name: `Translator`. Method: `.translate(content, args: {pkgname:})`.

```ruby
# data/translators/normalize.rb
class Translator
  def self.translate(content, args: {})
    content.gsub(/^## /, '# ')   # normalize headings
  end
end
```

### Platform Format Profiles

Each platform has a format profile at `data/platforms/<agent>.yaml`. These describe heading style, bullet style, frontmatter policy, emoji handling, etc. **Informational for LLM reference — not enforced by the build system.**

Profiles exist for all 14 platform profiles: opencode, crush, goose, droid, gemini-cli, qwen-code, oh-my-pi, cursor, windsurf, github-copilot, claude-code, codex, antigravity, agents.

### Transformer Pattern

Built-in transformers:
- `copy` — identity (no change)
- `strip-frontmatter` — remove YAML frontmatter (`---` blocks)

Custom transformers: Ruby script defining `Transform` class with `.transform(content, pkgname: nil)` method. Reference in PKGBUILD as `transformer: custom:path/to/transformer.rb`. Paths are resolved relative to repo root (`rulepack/`), validated with `realpath` to prevent symlink attacks.

**Example Custom Transformers** (in `data/transformers/`):
- `add-header.rb` — prepend title/header from frontmatter
- `strip-comments.rb` -- remove HTML comments and normalize whitespace
- `format-code.rb` — auto-detect and tag code blocks (Ruby/Python)

See `data/transformers/` for implementations.

---

## Important Files

| `data/packages/` | Package source tree (PKGBUILD + src/) |
| `data/registry/platforms.yaml` | Platform definitions |
| `data/platforms/` | Platform format profiles (informational — heading style, bullet style, content expectations) |
| `data/translators/` | Custom translator scripts (translate step — content format conversion) |
| `data/transformers/` | Custom transformer scripts (transform step — structural changes) |
| `lib/rulepack/` | Library modules — `common.rb` (constants/Config/IO), `installer.rb`, plus `logging.rb`, `cache.rb`, `backup.rb`, `version.rb`, `source.rb`, `transform.rb`, `validation.rb`, `platform.rb`, `uninstaller.rb` |
| `lib/rulepack/build.rb` | Build orchestrator (translate → transform → write) |
| `lib/rulepack/translate.rb` | Standalone translator runner (CLI) |
| `lib/rulepack/aggregate.rb` | Vendor skill aggregation |
| `lib/rulepack/install.rb` | Platform installer (CLI entry point — delegates to `lib/rulepack/installer.rb`) |
| `lib/rulepack/uninstall.rb` | Platform uninstaller |
| `lib/rulepack/query.rb` | Package database query tool |
| `lib/rulepack/verify.rb` | Index-disk reconciliation (detect drift) |
| `lib/rulepack/fix.rb` | Automated drift repair |
| `lib/rulepack/generate-catalog.rb` | Package catalog generator (JSON) |
| `data/index.yaml` | Master package database |
| `data/index.json` | Machine-readable index |
| `build/index.yaml` | Build metadata (intermediate) |

---

## Testing & QA

### Automated Test Suite

Run the full test suite with `rake test` (Minitest):

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

**Test coverage** (202 tests, 663 assertions, 0 failures, 0 errors):

| File | Tests | Coverage |
|------|-------|----------|
| `test/test_common.rb` | 48 | `compare_versions`, `vercmp`, `format_version`, `validate_output_filename`, `validate_target_dir`, `expand_user_path`, `strip_frontmatter` |
| `test/test_integration.rb` | 29 | Build index, skill-bundle manifest generation (6 tests), version comparison, schema migration (idempotent), transaction rollback, cache integration |
| `test/test_cache.rb` | 24 | Cache key (url/git/local), cache dir, source_cached?, cache_source (content/file), get_cached_source, cached_fetch_url errors |
| `test/test_pkgbuild_validation.rb` | 31 | `load_pkgbuild` (valid, missing file/fields, invalid formats), `validate_pkgbuild` (valid, all invalid fields, nil guards, skill-bundle constraints) |
| `test/test_platform.rb` | 33 | Platform registry loading/validation, `platform_config` lookup, `resolve_install_path` (all types), `safe_relative`, `build_dir_for_platform`, `check_prerequisites` |
| `test/test_uninstall.rb` | 7 | Index mutation (in-place removal, dry-run safety, dedup), disk write verification, skip-not-installed |
| `test/test_query.rb` | 16 | list, show, search, installed, check, orphans, depends, provides |
| `test/test_translate.rb` | 4 | Translator loading, apply_translator |
| `test/test_aggregate.rb` | 4 | Skill agent detection, vendor file creation |
| `test/test_end_to_end.rb` | 14 | Build → install → check → uninstall across all platform types |

### Manual Validation

```bash
# Dry-run install to preview changes
bin/rulepack install opencode --dry-run

# Dry-run uninstall to preview removal
bin/rulepack uninstall opencode --dry-run

# Check that installed state matches index (returns non-zero if mismatch)
bin/rulepack check opencode

# Query installed packages
bin/rulepack list
bin/rulepack search security

# Verify index vs disk (detect drift)
bin/rulepack verify opencode

# Repair drift automatically
bin/rulepack fix opencode

# Full rebuild + reinstall
rm -rf build/ && bin/rulepack build && bin/rulepack install opencode

# Full cycle: install → verify → uninstall → verify
bin/rulepack install opencode && bin/rulepack check opencode && bin/rulepack uninstall opencode && bin/rulepack check opencode

# Verify-fix-verify cycle
bin/rulepack verify opencode && bin/rulepack fix opencode && bin/rulepack verify opencode
```

---

## Migration from Old System

**Old system** (`scripts/` directory, `schema.yaml`-driven) is **deprecated**. New system uses PKGBUILD packages.

To migrate:
1. Move rule/skill content to `data/packages/<pkg>/src/`
2. Write PKGBUILD descriptor for each package
3. Add platform targets with appropriate `format` and `transformer`
4. Run `ruby lib/rulepack/build.rb && ruby lib/rulepack/aggregate.rb`
5. Install: `ruby lib/rulepack/install.rb <platform>`
6. Update `data/registry/platforms.yaml` if new platforms added

**Old scripts** (`scripts/fetch-upstream.rb`, `scripts/transform.rb`, etc.) are preserved for backward compatibility but **should not be used**. New canonical scripts live in `lib/rulepack/` root.

---

## Project Status

### Goals

- **Single Source of Truth**: One authoritative source for all agent rules and skills, no scattered config files.
- **Package-based distribution**: Each rule/skill is a package with a declarative PKGBUILD descriptor — inspired by Arch's ABS.
- **Multi-platform deployment**: One PKGBUILD → multiple target platforms (14 agents), each with its own format/install method.
- **Per-platform content adaptation**: Content must be translated (format conversion) and transformed (structural changes) per target platform's expectations.
- **Full pipeline tooling**: Build → Aggregate → Install → Uninstall → Query, all scripted and testable.

### What We Built (Completed)

| Layer | Status | Notes |
|-------|--------|-------|
| **PKGBUILD descriptor** | ✅ | YAML, all required fields, validated on load |
| **Source model** | ✅ | `local` (src/), `git` (clone + commit hash), `url` (SHA256) |
| **Build pipeline** (`build.rb`) | ✅ | Fetch → translate → transform → write, 106 artifacts from 10 packages across 6 platforms |
| **Translate layer** | ✅ | `apply_translator` in `transform.rb`, 3 translators (`rule_to_skill.rb`, `rule_to_import.rb`, `normalize_markdown.rb`), `translate.rb` CLI. Wired into memory/shell PKGBUILDs for crush/goose/droid/codex targets |
| **Transform layer** | ✅ | Built-in (`copy`, `strip-frontmatter`) + custom (`custom:<path>`) |
| **Platform registry** | ✅ | 14 platforms in `platforms.yaml` |
| **Platform format profiles** | ✅ | 14 YAML profiles (informational for LLM reference) |
| **Install** (`install.rb`) | ✅ | Per-platform install, upgrade/downgrade logic, `--dry-run`, `--force`, `--select`; modular `installer.rb`; interactive sub-skill menu on TTY |
| **Uninstall** (`install.rb`) | ✅ | Idempotent, re-aggregates vendor skills, dry-run |
| **Transaction atomicity** | ✅ | Backup/restore/cleanup on install failure |
| **Build cache** | ✅ | Content-addressed (URL by SHA256, git by commit hash) |
| **Vendor skill aggregation** | ✅ | Crush, Goose, Droid, Codex — concatenates rule fragments + skills |
| **Skill-bundle** | ✅ | Directory-level deployment, manifest v2 (per-file checksums), `--select` |
| **Version management** | ✅ | pacman-style epoch:pkgver-pkgrel, compare/upgrade/downgrade |
| **Query tool** | ✅ | list, show, search, installed, check, orphans, depends, provides |
| **Index** | ✅ | YAML + JSON, atomic writes, legacy migration |
| **Package catalog** | ✅ | `build/catalog.json` — auto-generated after build, portatif JSON format (id, version, tags, source, platforms) |
| **Test suite** | ✅ | 202 tests, 663 assertions, 0 failures (test_common, test_integration, test_cache, test_pkgbuild, test_platform, test_uninstall, test_query, test_translate, test_aggregate, test_end_to_end) |
| **Standalone scripts** | ✅ | `build.rb`, `install.rb`, `uninstall.rb`, `query.rb`, `aggregate.rb`, `translate.rb` |
| **Modular installer** | ✅ | Library layer (`lib/rulepack/installer.rb`, `lib/rulepack/common.rb`), `--all`, `--targets <pkg>`, `--check <platform>` |
| **Unified logging** | ✅ | `Rulepack::Common.log*` shared across build.rb, install.rb, uninstall.rb — level filtering via `Rulepack::Common.log_level` |
| **Config module** | ✅ | `Rulepack::Config` — 5 env vars (`RULEPACK_MAX_REDIRECTS`, `RULEPACK_READ_TIMEOUT`, `RULEPACK_CACHE_DIR`, `RULEPACK_GIT_DEPTH`, `RULEPACK_LOG_LEVEL`) |
| **Platform registry cache** | ✅ | `load_platform_registry` memoized with `@_platform_registry` — ~3× fewer YAML reads |
| **Performance timing** | ✅ | `Rulepack::Common.time` helper + `--timing` flag — per-package build timing |
| **Error messages** | ✅ | All 11+ key error messages include actionable guidance ("what + how to fix") |
| **DRY project_root_for** | ✅ | Extracted to `Rulepack::Common`, both install.rb and uninstall.rb delegate |
| **Ruby syntax warnings** | ✅ | All Ruby files pass `ruby -wc` with zero warnings |

### In Progress

| Item | Status | What's Needed |
|------|--------|--------------|
| **Manually-installed skills packaged** | 🟡 6 packages created, some still unmanaged | `ast-grep`, `line-repetition-control`, `workstation-rules`, `goose`, `windsurf-rules`, `vibe-security` (agents target) — installed and tracked |

### Deferred (Not Needed / Low Priority)

| Item | Reason |
|------|--------|
| **Remote repository system** | Not a user priority; all packages are local |
| **Dependency resolution** | Skills/rules are independent text files; no topological sort needed |
| **Package signing (GPG/signify)** | Deferred |
| **makepkg advanced features** | `prepare()`/`build()`/`package()` functions, patches, subpackages — not needed for text files |
| **pacman layer completeness** | `-Qi/-Qs/-Qo/-Ql` parity improvements — can be done later |

### Architecture Decision: Translate vs Transform

```
Source (fetched)
    ↓
TRANSLATE  ← format family conversion (rule → skill, markdown → import)
            ← regex/awk/sed/text processing per target platform expectations
            ← Translator API: custom:translators/NAME.rb
            ← Runs FIRST
    ↓
TRANSFORM  ← structural/format changes (copy, strip-frontmatter, add-header)
            ← Transformer API: custom:transformers/NAME.rb
            ← Runs SECOND
    ↓
Build artifact → Install → Target platform
```

**Translate** changes the *format family* of the content (what kind of document it is).
**Transform** changes the *structure or presentation* of the content (how it looks).

Example: `memory` package's `crush` target uses `rule_to_skill.rb` translator (translate) then `copy` transformer. 8 targets across memory/shell packages now use the translate layer.

---

## License

MIT — same as the upstream TCI project and vibe-security skill.
