# Usage Guide

How to use the Rulepack system: installation, workflows, commands, and common tasks.

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
bin/rulepack build

# 2. Install to a platform
bin/rulepack install opencode              # user-level
bin/rulepack install cursor --project .    # project-level (from project root)

# 3. Verify
bin/rulepack check opencode
```

---

## Installation

### User-Level Platforms

Global installation to home directory or system paths. No `--project` flag needed.

```bash
# OpenCode (rules as symlinks)
bin/rulepack install opencode

# Oh My Pi
bin/rulepack install oh-my-pi

# Skill agents (vendor skill file)
bin/rulepack install crush
bin/rulepack install goose
bin/rulepack install droid

# Import agents (inject @import lines)
bin/rulepack install gemini-cli
bin/rulepack install qwen-code

# Community agents
bin/rulepack install agents
```

### Project-Level Platforms

Per-project installation. Run from project root or use `--project PATH`:

```bash
cd /path/to/your/project

# Install to current project (--project optional when run from project root)
bin/rulepack install cursor
bin/rulepack install windsurf
bin/rulepack install github-copilot
bin/rulepack install claude-code
bin/rulepack install codex
bin/rulepack install antigravity

# Or specify explicit project path
bin/rulepack install cursor --project /path/to/project
```

**Important**: Uninstall for project-level platforms also requires `--project` to locate files.

---

## Workflows

### Full Cycle (Clean Rebuild)

```bash
# Clean build artifacts, rebuild everything, reinstall
rm -rf build/
bin/rulepack build
bin/rulepack install opencode
```

### Development Cycle

```bash
# 1. Edit package source
vim data/packages/memory/src/00-memory.md

# 2. Rebuild (only changed packages)
bin/rulepack build

# 3. Reinstall affected platforms
bin/rulepack install opencode
bin/rulepack install cursor --project .

# 4. Verify
bin/rulepack show memory
bin/rulepack check opencode
```

### Multi-Platform Install

```bash
# Install to all user-level platforms
for p in opencode oh-my-pi crush goose droid gemini-cli qwen-code agents; do
  bin/rulepack install $p
done

# Install to project from multiple terminals or script
bin/rulepack install cursor --project /my/project &
bin/rulepack install claude-code --project /my/project &
wait
```

### Dry-Run Preview

Always preview changes before installing:

```bash
bin/rulepack install opencode --dry-run
bin/rulepack uninstall cursor --project . --dry-run
```

---

## Commands

### build

Build all packages from source.

```bash
bin/rulepack build              # Build all
bin/rulepack build && bin/rulepack install opencode  # Build and install
```

**Output**: `build/<platform>/` artifacts, `build/index.yaml`, `data/index.json`

### aggregate

Generate vendor skill files for skill-based agents.

```bash
bin/rulepack aggregate          # All skill agents
# or: ruby lib/rulepack/aggregate.rb
```

**Output**: `build/<agent>/skills/vendor/<agent>.md`

### install

Install packages to a target platform.

```bash
bin/rulepack install <platform> [options]

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
bin/rulepack install opencode

# Install to project-level platform
bin/rulepack install cursor --project .

# Preview changes
bin/rulepack install opencode --dry-run

# Install only specific sub-skills from a skill-bundle
bin/rulepack install golang-security --select auth,sql

# Force downgrade
bin/rulepack install opencode --force
```

**Examples**:
```bash
bin/rulepack install opencode --dry-run
bin/rulepack install cursor --project /my/app
bin/rulepack check opencode
```

**Platform Prerequisites**:
Before install, Rulepack checks platform prerequisites (system tools) and warns if missing. This is informational only — install continues regardless. See [Platforms](PLATFORMS.md) for required tools per platform.

**Upgrades & Downgrades**:
- Re-installing automatically upgrades if the candidate version is newer (higher epoch → pkgver → pkgrel).
- Downgrades are blocked by default to prevent accidental rollbacks.
- Use `--force` to allow a downgrade (e.g., to roll back to an older package version).

```bash
bin/rulepack install opencode --force   # Force even if candidate is older
```

### uninstall

Remove packages from a platform.

```bash
bin/rulepack uninstall <platform> [options]

Options:
  --dry-run        Show what would be removed (no changes)
  --project PATH   Project root for project-level platforms
```

**Examples**:
```bash
bin/rulepack uninstall opencode --dry-run
bin/rulepack uninstall cursor --project /my/app
```

### query / list / show / search

Inspect the package database.

```bash
# List all packages
bin/rulepack list

# Show package details
bin/rulepack show memory
bin/rulepack show vibe-security

# Search by tag
bin/rulepack search constraints
bin/rulepack search security

# List installed packages on a platform
bin/rulepack installed --platform opencode

# List available platforms
bin/rulepack platforms
```

---

## Uninstall

Uninstall removes packages from a platform and cleans up:

```bash
# User-level
bin/rulepack uninstall opencode
bin/rulepack uninstall goose

# Project-level (must specify project)
cd /my/project
bin/rulepack uninstall cursor --project .
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
bin/rulepack check opencode
bin/rulepack check cursor --project /my/app
```

Exit code: `0` = all valid, non-zero = mismatches found.

**What it checks:**
- All expected files exist at computed paths
- File checksums match index records
- For skill agents: vendor skill file present

### Verify Mode

Comprehensive index-disk reconciliation:

```bash
bin/rulepack verify opencode
```

Detects drift between index and actual disk state, reports orphans and mismatches.

### Fix Mode

Automated repair of drift:

```bash
bin/rulepack fix opencode
```

Clears broken records, reinstalls missing packages, removes orphans.

---

## Adding a New Package

### 1. Create Package Directory

```bash
mkdir -p data/packages/my-rule/src
```

### 2. Write Source File

`data/packages/my-rule/src/00-my-rule.md`:
```markdown
# My Rule

Some content here.
```

### 3. Write PKGBUILD

`data/packages/my-rule/PKGBUILD`:
```yaml
---
pkgname: my-rule
pkgver: '1.0.0'
pkgdesc: My custom rule
arch: any
order: 0

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

checksums:
  source: null
  built: {}
```

### 4. Build

```bash
bin/rulepack build
```

### 5. Install

```bash
bin/rulepack install opencode
```

### 6. Verify

```bash
bin/rulepack show my-rule
bin/rulepack check opencode
```

### Adding a New Platform

1. Add to `data/registry/platforms.yaml` (see [Platforms](PLATFORMS.md) for schema)
2. Create platform-specific PKGBUILD packages if needed (wrapper/meta-packages)
3. Update any platform-specific logic in `lib/rulepack/install.rb`/`lib/rulepack/uninstaller.rb` if non-standard paths
4. Test install/uninstall/check cycle

---

## Troubleshooting

### "No build index found"

```bash
# Build packages first
bin/rulepack build
```

### "Platform not found"

```bash
# List available platforms
bin/rulepack platforms
```

Ensure the platform ID matches exactly (e.g., `opencode`, not `OpenCode`).

### "PKGBUILD not found"

Check that `data/packages/<name>/PKGBUILD` exists. Run `bin/rulepack build` from repo root.

### "Path traversal not allowed"

Custom transformer or source paths must resolve within the repository root. Ensure paths don't contain `..` or absolute paths outside the repo.

### "Checksum mismatch"

Source or built artifact has changed since last build. Run `bin/rulepack build` to rebuild.

### "No target for platform, skipping"

The package has no target defined for the requested platform. Check the PKGBUILD `targets:` section.

### Custom transformer errors

Ensure `data/transformers/<name>.rb` exists and defines a `Transform` class with a `#transform` method.

---

## Logs

All operations log to:

- **Build log**: `build/build.log`
- **Install log**: `build/install.log`
- **Uninstall log**: `build/uninstall.log`

Check logs for detailed error messages.
