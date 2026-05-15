# Usage Guide

How to use the SSoT system: installation, workflows, commands, and common tasks.

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
  - [User-Level Platforms](#user-level-platforms)
  - [Project-Level Platforms](#project-level-platforms)
- [Workflows](#workflows)
- [Commands](#commands)
- [Uninstall](#uninstall)
- [Verification](#verification)
- [Adding a New Package](#adding-a-new-package)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

```bash
# 1. Build all packages (fetch + transform)
bin/ssot build

# 2. Install to a platform
bin/ssot install opencode              # user-level
bin/ssot install cursor --project .    # project-level (from project root)

# 3. Verify
bin/ssot check opencode
```

---

## Installation

### User-Level Platforms

Global installation to home directory or system paths. No `--project` flag needed.

```bash
# OpenCode (rules as symlinks)
bin/ssot install opencode

# Oh My Pi
bin/ssot install oh-my-pi

# Skill agents (vendor skill file)
bin/ssot install crush
bin/ssot install goose
bin/ssot install droid

# Import agents (inject @import lines)
bin/ssot install gemini-cli
bin/ssot install qwen-code

# Community agents
bin/ssot install agents
```

### Project-Level Platforms

Per-project installation. Run from project root or use `--project PATH`:

```bash
cd /path/to/your/project

# Install to current project (--project optional when run from project root)
bin/ssot install cursor
bin/ssot install windsurf
bin/ssot install github-copilot
bin/ssot install claude-code
bin/ssot install codex
bin/ssot install antigravity

# Or specify explicit project path
bin/ssot install cursor --project /path/to/project
```

**Important**: Uninstall for project-level platforms also requires `--project` to locate files.

---

## Workflows

### Full Cycle (Clean Rebuild)

```bash
# Clean build artifacts, rebuild everything, reinstall
rm -rf ssot/build/
bin/ssot build
bin/ssot install opencode
```

### Development Cycle

```bash
# 1. Edit package source
vim ssot/packages/memory/src/00-memory.md

# 2. Rebuild (only changed packages)
bin/ssot build

# 3. Reinstall affected platforms
bin/ssot install opencode
bin/ssot install cursor --project .

# 4. Verify
bin/ssot show memory
bin/ssot check opencode
```

### Multi-Platform Install

```bash
# Install to all user-level platforms
for p in opencode oh-my-pi crush goose droid gemini-cli qwen-code agents; do
  bin/ssot install $p
done

# Install to project from multiple terminals or script
bin/ssot install cursor --project /my/project &
bin/ssot install claude-code --project /my/project &
wait
```

### Dry-Run Preview

Always preview changes before installing:

```bash
bin/ssot install opencode --dry-run
bin/ssot uninstall cursor --project . --dry-run
```

---

## Commands

### build

Build all packages from source.

```bash
bin/ssot build              # Build all
bin/ssot build && bin/ssot install opencode  # Build and install
```

**Output**: `ssot/build/<platform>/` artifacts, `ssot/build/index.yaml`, `ssot/index.json`

### aggregate

Generate vendor skill files for skill-based agents.

```bash
bin/ssot aggregate          # All skill agents
# or: ruby ssot/aggregate-skills.rb
```

**Output**: `ssot/build/<agent>/skills/vendor/<agent>.md`

### install

Install packages to a target platform.

```bash
bin/ssot install <platform> [options]

Options:
  --dry-run        Show what would be installed (no changes)
  --check          Verify installed state matches index (exit 0 if OK)
  --project PATH   Project root for project-level platforms (default: current dir)
  --force          Allow downgrades (overrides version check)
  --select SKILLS  Comma-separated sub-skill names for skill-bundle (e.g. --select auth,sql)
```

**Examples**:
```bash
# Install all packages to user-level platform
bin/ssot install opencode

# Install to project-level platform
bin/ssot install cursor --project .

# Preview changes
bin/ssot install opencode --dry-run

# Install only specific sub-skills from a skill-bundle
bin/ssot install golang-security --select auth,sql

# Force downgrade
bin/ssot install opencode --force
```

**Examples**:
```bash
bin/ssot install opencode --dry-run
bin/ssot install cursor --project /my/app
bin/ssot check opencode
```

**Platform Prerequisites**:
Before install, SSoT checks platform prerequisites (system tools) and warns if missing. This is informational only — install continues regardless. See [Platforms](PLATFORMS.md) for required tools per platform.

**Upgrades & Downgrades**:
- Re-installing automatically upgrades if the candidate version is newer (higher epoch → pkgver → pkgrel).
- Downgrades are blocked by default to prevent accidental rollbacks.
- Use `--force` to allow a downgrade (e.g., to roll back to an older package version).

```bash
bin/ssot install opencode --force   # Force even if candidate is older
```

### uninstall

Remove packages from a platform.

```bash
bin/ssot uninstall <platform> [options]

Options:
  --dry-run        Show what would be removed (no changes)
  --project PATH   Project root for project-level platforms
```

**Examples**:
```bash
bin/ssot uninstall opencode --dry-run
bin/ssot uninstall cursor --project /my/app
```

### query / list / show / search

Inspect the package database.

```bash
# List all packages
bin/ssot list

# Show package details
bin/ssot show memory
bin/ssot show vibe-security

# Search by tag
bin/ssot search constraints
bin/ssot search security

# List installed packages on a platform
bin/ssot installed --platform opencode

# List available platforms
bin/ssot platforms
```

---

## Uninstall

Uninstall removes packages from a platform and cleans up:

```bash
# User-level
bin/ssot uninstall opencode
bin/ssot uninstall goose

# Project-level (must specify project)
cd /my/project
bin/ssot uninstall cursor --project .
```

**What gets removed:**
- **directory**: symlinks/files from `rules_dir`/`skills_dir`
- **import**: `@import` lines are NOT automatically removed (manual edit required — future enhancement)
- **skill**: vendor skill file deleted; index cleaned

**Skill agent special handling**: For skill-based agents (crush, goose, droid, codex), uninstall re-aggregates the vendor skill file to exclude the removed package's contributions.

**Idempotent**: Safe to run multiple times; missing artifacts are ignored.

---

## Verification

### Check Mode

Verify that installed state matches index:

```bash
bin/ssot check opencode
bin/ssot check cursor --project /my/app
```

Exit code: `0` = all valid, non-zero = mismatches found.

**What it checks:**
- All expected files exist at computed paths
- File checksums match index records
- For skill agents: vendor skill file present

### Query Installed

See what's installed on a platform:

```bash
bin/ssot installed --platform opencode
```

### Dry-Run

Preview changes without touching filesystem:

```bash
bin/ssot install opencode --dry-run
bin/ssot uninstall cursor --project . --dry-run
```

---

## Adding a New Package

### 1. Create Package Structure

```bash
mkdir -p ssot/packages/my-rule/src
```

### 2. Write Source File

`ssot/packages/my-rule/src/00-my-rule.md`:
```markdown
# My Rule

This is my custom rule for the agent.

## Constraints

- Always do X
- Never do Y
```

### 3. Write PKGBUILD

`ssot/packages/my-rule/PKGBUILD`:
```yaml
---
pkgname: my-rule
pkgver: '1.0.0'
pkgrel: 1
epoch: 0
pkgdesc: My custom rule
arch: any
order: 10

source:
  - type: local
    path: src/00-my-rule.md

targets:
  - platform: opencode
    format: directory
    output: 00-my-rule.md
    transformer: copy
    install:
      type: symlink

  - platform: cursor
    format: directory
    output: my-rule.md
    transformer: copy
    install:
      type: symlink

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

### 4. Build & Install

```bash
bin/ssot build
bin/ssot install opencode
bin/ssot install cursor --project /my/project
```

### 5. Verify

```bash
bin/ssot show my-rule
bin/ssot check opencode
```

---

## Adding a New Platform

1. Add to `ssot/registry/platforms.yaml` (see [Platforms](PLATFORMS.md) for schema)
2. Create platform-specific PKGBUILD packages if needed (wrapper/meta-packages)
3. Update any platform-specific logic in `install.rb`/`uninstall.rb` if non-standard paths
4. Test install/uninstall/check cycle

---

## Troubleshooting

### "No target for <platform>" warnings

Package has no `targets` entry for that platform. Add target to PKGBUILD or ignore if intentional.

### "Built artifact missing" errors

Run `bin/ssot build` first. Build artifacts are required before install.

### "Unknown platform" error

Platform not in `ssot/registry/platforms.yaml`. Add it or check spelling.

### "Path traversal not allowed"

`output` field contains `..` or absolute path. Output must be filename-only (no directories). Use `rules_dir`/`skills_dir` from platform config for subdirectories.

### Skill agent vendor file empty

Check that rule packages have `format: skill` targets for that agent. Run `aggregate-skills.rb` manually to see errors.

### Project-level install can't find platform

Ensure you're running from project root or use `--project /path/to/project`. Platform `base_path` must be `.` in registry.

### Checksum mismatch after install

File was modified after install (manual edit) or build changed. Re-run `build.rb` then `install.rb`.

### Transformer not found

Custom transformer path is relative to repo root. Ensure `ssot/transformers/<name>.rb` exists and defines `Transform` class.

---

## Logs

All operations log to:
- **Build log**: `ssot/build/build.log`
- **Install log**: `ssot/build/install.log`
- **Uninstall log**: `ssot/build/uninstall.log`

Check logs for detailed error messages.

---

## See Also

- [Architecture](ARCHITECTURE.md) — System design
- [Platforms](PLATFORMS.md) — Platform reference
- [Reference](REFERENCE.md) — PKGBUILD format, transformer API, index schema
- [Transforms](TRANSFORMS.md) — Transformer documentation
