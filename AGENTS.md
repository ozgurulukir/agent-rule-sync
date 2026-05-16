# Rulepack — Developer Guide

> **For users**: See [README.md](README.md) for quick start, commands, platform reference, and environment variables.

## Project Overview

This repository implements a **Single Source of Truth** management system for agent rules, skills, and documentation using a **package-based architecture** (PKGBUILD format). Each rule or skill is a package with a declarative build descriptor. The system fetches, transforms, builds, and distributes content to multiple agent platforms through a streamlined pipeline.

**Core Purpose**: Maintain one authoritative source for agent behavior definitions (rules, skills, docs) as individual packages, automatically propagate updates to multiple target platforms with change detection, custom transformers, and per-platform format conversion.

---

## Quick Links — Developer Docs

- **[Architecture](docs/agents/ARCHITECTURE.md)** — System design, pipeline, data flow
- **[Platforms](docs/agents/PLATFORMS.md)** — All supported agents and configuration
- **[Reference](docs/agents/REFERENCE.md)** — PKGBUILD format, transformer API, index schema
- **[Transforms](docs/agents/TRANSFORMS.md)** — Transformer system (built-in + custom translators)
- **[Upstream](docs/agents/UPSTREAM.md)** — Upstream source management
- **[Usage](docs/agents/USAGE.md)** — Detailed command reference

---

## Architecture & Data Flow

```
PKGBUILD Packages (data/packages/)
  memory/PKGBUILD, shell/PKGBUILD, vibe-security/PKGBUILD
  │
  ▼ build (build.rb)
Build Artifacts (build/<platform>/)
  opencode/00-memory.md, crush/skills/vendor/crush.md
  │
  ▼ aggregate (aggregate.rb)
Vendor Skills (build/<platform>/skills/vendor/)
  Combined per agent: crush.md, goose.md, droid.md
  │
  ▼ install (install.rb)
Target Agent Platforms
  OpenCode (directory)  |  Crush (skill)  |  Gemini CLI (import)
```

**Note**: PKGBUILD/pacman is used as **architectural inspiration**. Rulepack does not track Arch Linux packages or use pacman as a dependency.

### Key Pipeline Steps

1. **Build** (`build.rb`) — Load all PKGBUILDs from `data/packages/`, fetch sources (local/URL with SHA256), apply translators (content format conversion), apply transformers (copy/strip-frontmatter/custom), write platform-specific artifacts to `build/<platform>/`, update `data/index.yaml` with build metadata.

2. **Aggregate** (`aggregate.rb`) — For skill-based agents (Crush, Goose, Droid, Codex), collect rule fragments and common/agent-specific skills, concatenate into a single vendored skill file per agent under `build/<agent>/skills/vendor/`.

3. **Install** (`install.rb <platform>`) — Read `data/index.yaml`, for each package built for target platform, install via symlink/copy/inject/append. Supports `--all`, `--select`, `--check`, `--dry-run`, `--force`. Interactive sub-skill menu for bundles with 2-50 sub-skills in a TTY.

4. **Query** (`query.rb`) — Inspect package database: list, show, search, check, orphans, depends, provides.

---

## Creating a New Package

### 1. Create the package directory

```bash
mkdir -p data/packages/<pkgname>/src/
```

### 2. Add the source file

Place your rule or skill content in `data/packages/<pkgname>/src/` as a Markdown file. This is your canonical content — all platform-specific transformations start from this file.

### 3. Write the PKGBUILD descriptor

Create `data/packages/<pkgname>/PKGBUILD` (YAML). See [PKGBUILD Format](#pkgbuild-format) below for all fields.

### 4. Choose target platforms

Each `targets[]` entry maps one platform to a format+output. See [Supported Platforms](README.md#supported-platforms-14-agents) in README.md.

| Format | Mechanism | Example Agents |
|--------|-----------|----------------|
| `directory` | Symlink/copy file into platform's rules/skills dir | OpenCode, Cursor |
| `skill` | Copy into vendored skill file | Crush, Goose, Droid |
| `import` | `@import` line injected into config file | Gemini CLI, Qwen Code |
| `skill-bundle` | Copy entire directory tree of skills | OpenCode, Cursor, Windsurf, Claude Code |

### 5. Build and install

```bash
bin/rulepack build
bin/rulepack install opencode
bin/rulepack check opencode
```

### Quick reference

| Step | Action | File/Directory |
|------|--------|---------------|
| 1 | Create package dir | `data/packages/<pkgname>/` |
| 2 | Add source file | `data/packages/<pkgname>/src/<file>.md` |
| 3 | Write descriptor | `data/packages/<pkgname>/PKGBUILD` |
| 4 | Set targets | `targets:` array in PKGBUILD |
| 5 | Build | `bin/rulepack build` |
| 6 | Install | `bin/rulepack install <platform>` |

---

## PKGBUILD Format

Each package is defined in `data/packages/<pkgname>/PKGBUILD` (YAML). Full reference: [docs/agents/REFERENCE.md](docs/agents/REFERENCE.md).

Minimum example:

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
    path: src/my-rule.md

targets:
  - platform: opencode
    format: directory
    output: 00-my-rule.md
    transformer: copy
    install:
      type: symlink

checksums:
  source: null
  built: {}

tags:
  - <tag1>
  - <tag2>
maintainer: null
license: MIT
```

### Available Fields

| Field | Required | Description |
|-------|----------|-------------|
| `pkgname` | ✅ | Lowercase alphanumeric with `-`/`_`, min 2 chars |
| `pkgver` | ✅ | Version string (non-empty) |
| `pkgrel` | ✅ | Package release integer (default 1) |
| `epoch` | ✅ | Versioning override integer (default 0) |
| `pkgdesc` | ✅ | Short description |
| `arch` | ✅ | Must be `any` |
| `order` | ✅ | Integer for vendor skill sorting (lower first) |
| `source` | ✅ | Array of source entries |
| `targets` | ✅ | Array of deployment targets |
| `pkgver_func` | ❌ | Shell command to auto-detect version |
| `tags` | ❌ | Array of searchable tags |
| `provides` | ❌ | Array of virtual capabilities |
| `dependencies` | ❌ | Array of package dependencies (documentation only) |
| `conflicts` | ❌ | Array of conflicting packages (documentation only) |
| `maintainer` | ❌ | Maintainer name |
| `license` | ❌ | License string (default: MIT) |

### Source Types

```yaml
# Local file
source:
  - type: local
    path: src/my-rule.md

# URL with SHA256 verification
source:
  - type: url
    url: https://example.com/rules.md
    sha256: "abc123def456..."

# Git repository
source:
  - type: git
    url: https://github.com/owner/repo.git
    ref: main                # branch, tag, or commit
    path: skills/            # subdirectory within repo
    depth: 1                 # shallow clone (recommended)
```

### Target Formats

See [REFERENCE.md](docs/agents/REFERENCE.md) for full details on skill-bundle format, sub-skill selection, meta-packages, and interactive menu.

---

## Translate + Transform Pipeline

The build pipeline runs two sequential content-processing steps per target:

```
Source → TRANSLATE → TRANSFORM → Build Artifact
```

**Translate** changes format family (rule → skill, markdown → import). Runs **before** transform. Built-in translators:

| Translator | Purpose |
|------------|---------|
| `copy` | Identity (no change) |
| `custom:translators/rule_to_skill.rb` | Converts flat rules to skill format |
| `custom:translators/rule_to_import.rb` | Converts markdown to import format |
| `custom:translators/normalize_markdown.rb` | Normalizes heading structure |

**Transform** changes structure/presentation. Runs after translate.

| Transformer | Purpose |
|-------------|---------|
| `copy` | Identity (no change) |
| `strip-frontmatter` | Remove YAML frontmatter (`---` blocks) |
| `custom:<path>` | Custom Ruby transformer script |

Custom transformers define `Transform` class with `.transform(content, pkgname:)` method. See [data/transformers/](data/transformers/) for examples.

Platform format profiles at `data/platforms/<agent>.yaml` describe heading style, bullet style, frontmatter policy, etc. **Informational for LLM reference — not enforced by the build system.**

---

## Code Conventions

- **Ruby ≥ 2.7**, standard library only (no gems)
- **RuboCop** with progressive thresholds: `.rubocop.yml` (23 domain-complexity offenses tolerated)
- **Frozen string literals** throughout
- **Pathname API** for all path operations (`Pathname#join`, `#expand_path`, `#realpath`)
- **YAML-first** configuration (PKGBUILD, registry)
- **Error handling**: `log_error`/`log_warn` for non-fatal, `raise` for fatal
- **Security**: Path traversal validation on all user-supplied paths, transformer path realpath checks
- **Idempotency**: `--dry-run` makes zero filesystem changes; installs/uninstalls are idempotent
- **Subprocess elimination**: All Ruby commands loaded via `load()` — no `system('ruby', ...)` calls
- **Config**: `Rulepack::Config` module with 5 environment variable overrides

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
rake test_query        # Query tests (8 tests)
rake test_translate    # Translate tests (4 tests)
rake test_aggregate    # Aggregate tests (4 tests)
rake test_e2e          # End-to-end pipeline tests (14 tests)
```

**Test coverage** (202 tests, 663 assertions, 0 failures):

| File | Tests | Covers |
|------|-------|--------|
| `test/test_common.rb` | 48 | version comparison, vercmp, format_version, path validation, frontmatter stripping |
| `test/test_integration.rb` | 29 | build index, skill-bundle manifest, version comparison, schema migration, rollback, cache |
| `test/test_cache.rb` | 24 | cache key, cache dir, source_cached?, cache_source, fetch errors |
| `test/test_pkgbuild_validation.rb` | 31 | load/validate PKGBUILD (valid + all invalid field types) |
| `test/test_platform.rb` | 33 | registry loading, path resolution, prerequisites |
| `test/test_uninstall.rb` | 7 | index mutation, dry-run, dedup, disk write verification |
| `test/test_query.rb` | 8 | list, show, search, installed, check, orphans, depends, provides |
| `test/test_translate.rb` | 4 | translator loading, apply_translator |
| `test/test_aggregate.rb` | 4 | skill agent detection, vendor file creation |
| `test/test_end_to_end.rb` | 14 | build → install → check → uninstall across all platform types |

### Manual Validation

```bash
bin/rulepack install opencode --dry-run        # preview changes
bin/rulepack check opencode                     # verify installation
bin/rulepack verify opencode                    # detect drift
bin/rulepack fix opencode                       # repair drift
```

---

## Important Files

| Path | Purpose |
|------|---------|
| `data/packages/` | Package source tree (PKGBUILD + src/) |
| `data/registry/platforms.yaml` | Platform definitions (14 agents) |
| `data/platforms/` | Format profiles (informational) |
| `data/translators/` | Custom translator scripts (3) |
| `data/transformers/` | Custom transformer scripts (3) |
| `data/index.yaml` | Master package database |
| `build/index.yaml` | Build metadata (intermediate) |
| `build/catalog.json` | Package catalog (auto-generated) |
| `lib/rulepack/common.rb` | Constants, Config, basic IO, cache |
| `lib/rulepack/installer.rb` | Installer library |
| `lib/rulepack/build.rb` | Build orchestrator |
| `lib/rulepack/query.rb` | Package database queries |
| `lib/rulepack/verify.rb` | Index-disk reconciliation |
| `lib/rulepack/fix.rb` | Automated drift repair |
| `lib/rulepack/aggregate.rb` | Vendor skill aggregation |
| `lib/rulepack/uninstall.rb` | CLI wrapper for uninstall |
| `lib/rulepack/install.rb` | CLI wrapper for install |
| `.rubocop.yml` | RuboCop configuration |

---

## Project Status

### Completed (P0-P11)

| Layer | Notes |
|-------|-------|
| PKGBUILD descriptor | YAML, 10+ fields, validated on load |
| Source model | local, URL (SHA256), git (commit hash) |
| Build pipeline | Fetch → translate → transform → write, 9 packages |
| Platform support | 14 agents (directory/import/skill/skill-bundle) |
| Install/Uninstall | Per-platform, upgrade/downgrade, `--select`, atomic index |
| Build cache | Content-addressed (SHA256/commit hash) |
| Vendor aggregation | Crush, Goose, Droid, Codex |
| Version management | pacman-style epoch:pkgver-pkgrel |
| Query tool | list, show, search, installed, check, orphans |
| Test suite | 202 tests, 663 assertions, 0 failures |
| RuboCop compliance | 124→23 offenses, final thresholds |
| Subprocess elimination | 12 `system()` calls replaced with `load()` |
| Skill-bundle optimization | Manifest generated once per package (not per platform) |

### In Progress

| Item | Status |
|------|--------|
| **Manually-installed skills packaged** | 🟡 9 packages tracked |

### Deferred

| Item | Reason |
|------|--------|
| Dependency resolution | Skills are independent text files |
| Package signing (GPG) | Low priority |
| Cache cleanup | Content-addressed cache never expires |

---

## License

MIT — same as the upstream TCI project and vibe-security skill.
