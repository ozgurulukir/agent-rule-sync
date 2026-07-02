# Usage Guide

How to use the Rulepack system: installation, workflows, commands, and common tasks.

---

## Quick Start

```bash
# 1. Build all packages (fetch + translate + schema engine + transform)
bin/rulepack build

# 2. Install to a platform
bin/rulepack install opencode              # user-level
bin/rulepack install cursor --project .    # project-level (from project root)

# 3. Verify
bin/rulepack verify opencode
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

# Antigravity (skill-bundle)
bin/rulepack install antigravity

# Agents
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
bin/rulepack verify opencode
```

### Multi-Platform Install

```bash
# Install to all user-level platforms
for p in opencode oh-my-pi crush goose droid gemini-cli qwen-code antigravity agents; do
  bin/rulepack install $p
done
```

### Dry-Run Preview

Always preview changes before installing:

```bash
bin/rulepack install opencode --dry-run
bin/rulepack uninstall cursor --project . --dry-run
```

### Install with --rules-to

Redirect rules to a single file instead of the `rules_dir`:

```bash
# Append rules to AGENTS.md instead of creating individual symlinks
bin/rulepack install oh-my-pi --rules-to AGENTS.md
```

### Install with --select

For skill-bundle packages, select specific sub-skills:

```bash
# Interactive selection (TUI)
bin/rulepack install opencode --select

# Non-interactive: specify sub-skills by name
bin/rulepack install opencode --select auth,sql
```

### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install memory -t opencode
bin/rulepack install memory -t cursor --project .

# Uninstall a single package
bin/rulepack uninstall memory -t opencode
bin/rulepack uninstall memory -t cursor --project .
```

### Install with --on-collision

Control what happens when a file already exists:

```bash
# Default: stop and report
bin/rulepack install opencode --on-collision stop

# Skip conflicting files and continue
bin/rulepack install opencode --on-collision ignore

# Replace files, generating a surgical backup
bin/rulepack install opencode --on-collision overwrite

# Append rules using marker boundary blocks
bin/rulepack install opencode --on-collision append
```

---

## Commands

### build

Build all packages from source.

```bash
bin/rulepack build              # Build all
bin/rulepack build --timing     # Build with timing output
```

**Output**: `build/<platform>/` artifacts, `build/index.yaml`, `build/catalog.json`

### install

Install packages to a target platform.

```bash
bin/rulepack install <platform> [options]

Options:
  --dry-run                Show what would be installed (no changes)
  --check                  Verify installed state matches index (exit 0 if OK)
  --project PATH           Project root for project-level platforms
  --force                  Allow downgrades (overrides version check)
  --needed                 Skip already-installed packages
  --select <names>         Comma-separated sub-skill names for skill-bundle
  --on-collision <mode>    Collision handling: stop|ignore|overwrite|append
  --rules-to <path>        Redirect rules to single file (e.g., AGENTS.md)
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
bin/rulepack install opencode --select auth,sql

# Force downgrade
bin/rulepack install opencode --force
```

**Upgrades & Downgrades**:
- Re-installing automatically upgrades if the candidate version is newer (higher epoch → pkgver → pkgrel).
- Downgrades are blocked by default to prevent accidental rollbacks.
- Use `--force` to allow a downgrade.

### uninstall

Remove packages from a platform.

```bash
bin/rulepack uninstall <platform> [options]

Options:
  --dry-run        Show what would be removed (no changes)
  --project PATH   Project root for project-level platforms
```

### Pacman-Style Shortcuts

```bash
bin/rulepack -S opencode            # Install (same as: install)
bin/rulepack -R opencode            # Uninstall (same as: uninstall)
bin/rulepack -Qk opencode           # Verify (same as: verify)
bin/rulepack -F opencode            # Fix (same as: fix)
bin/rulepack -Q ls                  # Query (same as: query ls)
```

### query / list / show / search

Inspect the package database.

```bash
# List all packages
bin/rulepack list
bin/rulepack -Q ls

# Show package details
bin/rulepack show memory

# Search by tag
bin/rulepack search security

# List installed packages on a platform
bin/rulepack -Q installed opencode

# List available platforms
bin/rulepack platforms
```

### verify

Comprehensive index-disk reconciliation:

```bash
bin/rulepack verify opencode
bin/rulepack -Qk opencode
```

Detects drift between index and actual disk state, reports orphans and mismatches.

### fix

Automated repair of drift:

```bash
bin/rulepack fix opencode
bin/rulepack -F opencode
bin/rulepack fix opencode --auto    # Non-interactive
```

Clears broken records, reinstalls missing packages, removes orphans.

### audit

Audit PKGBUILD descriptors for schema compliance:

```bash
bin/rulepack audit               # Basic audit
bin/rulepack audit --strict       # Strict mode
bin/rulepack audit --format json  # Machine-readable output
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
- **agent**: agent directory removed; index cleaned

**Idempotent**: Safe to run multiple times; missing artifacts are ignored.

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
pkg_type: rule
order: 0

source:
  - type: local
    path: src/00-my-rule.md

targets:
  - platform: opencode
    format: directory
    output: 00-my-rule.md
    install:
      type: symlink
```

> **Note**: Include targets for all 14 supported platforms. See [Reference](REFERENCE.md) for the full target schema.

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
bin/rulepack verify opencode
```

---

## Troubleshooting

### "No build index found"

```bash
bin/rulepack build
```

### "Platform not found"

```bash
bin/rulepack platforms
```

Ensure the platform ID matches exactly (e.g., `opencode`, not `OpenCode`).

### "PKGBUILD not found"

Check that `data/packages/<name>/PKGBUILD` exists. Run `bin/rulepack build` from repo root.

### "Path traversal not allowed"

Custom transformer or source paths must resolve within the repository root.

### "Checksum mismatch"

Run `bin/rulepack build` to rebuild.

### "No target for platform, skipping"

The package has no target defined for the requested platform. Check the PKGBUILD `targets:` section.

---

## Logs

All operations log to `build/build.log`. Check logs for detailed error messages.

---

## See Also

- [Architecture](ARCHITECTURE.md) — System design
- [Platforms](PLATFORMS.md) — Platform reference
- [Reference](REFERENCE.md) — PKGBUILD schema, index format
- [Transforms](TRANSFORMS.md) — Transformer/translator docs
