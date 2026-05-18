# Rulepack — Developer Guide

> **For users**: See [README.md](README.md) for quick start, commands, platform reference, and environment variables.

---

## 📖 Project Overview

This repository implements a **Single Source of Truth (SSOT)** management system for agent rules, skills, and documentation using a **declarative, package-based architecture** inspired by Arch Linux's `pacman` and `makepkg` package ecosystem. 

Each rule or skill exists as a package with a declarative descriptor (`PKGBUILD`). The system downloads, validates, translates, transforms, and installs files into target agent platforms using a robust transaction, drift-verification, and repair pipeline.

**Core Purpose**: Maintain a single, canonical repository of agent instructions. Automatically propagate updates, convert formats on the fly, protect files against collision, and continuously reconcile the installed state on all local coding agents.

---

## 🗺️ Quick Links — Developer Docs

- **[Architecture](docs/agents/ARCHITECTURE.md)** — Core design patterns, pipeline flow, and data storage.
- **[Platforms](docs/agents/PLATFORMS.md)** — Registry of all 14 supported coding agents and platform constraints.
- **[Reference](docs/agents/REFERENCE.md)** — YAML PKGBUILD grammar, custom transformer API, and index schemas.
- **[Transforms](docs/agents/TRANSFORMS.md)** — Mechanics of built-in translation layers and custom translators.
- **[Upstream](docs/agents/UPSTREAM.md)** — Management of third-party git/url dependencies and version bumps.
- **[Usage](docs/agents/USAGE.md)** — Command-line interface references, arguments, and return codes.

---

## 📐 Architecture & Pipeline Flow

```mermaid
graph TD
    subgraph PKG [Declarative Packages: data/packages/]
        M[memory/PKGBUILD]
        S[shell/PKGBUILD]
        V[vibe-security/PKGBUILD]
    end

    subgraph BLD [Build Pipeline: BuildPipeline.run]
        F[Fetch Sources & Verify SHA256] --> C[Build Cache]
        C --> SE[Centralized Dynamic Schema Engine: SchemaEngine.apply]
        SE --> W[Write Target-Specific Artifacts]
    end

    subgraph AGG [Skill Aggregator: Aggregate.run]
        SA[Collect rules & skills] --> CA[Concatenate into single skill file per platform using build/index.yaml]
    end

    subgraph INST [Package Manager: Install/Installer]
        CMS[Collision Management System CMS] --> INS[Install: symlink, copy, inject, append]
        INS --> IDX[Update Master Installed Index: data/index.yaml]
    end

    PKG --> BLD
    BLD -->|Intermediate Build Artifacts| AGG
    AGG -->|Combined Agent Skills| INST
```

### Key Lifecycle Phases (Fully Modularized)

1. **Build (`Rulepack::Build` & `Rulepack::BuildPipeline`)**: Loads YAML descriptors from `data/packages/`. Downloads and caches remote assets (URL/git) inside a content-addressed directory, verifying integrity via SHA256. Executes a 4-stage sequential build pipeline (Fetch → Auto-derive Translator → Dynamic Schema Engine → Transformer), writing target-specific outputs under `build/`, and saving target metadata to the build index (`build/index.yaml`). Formatting concerns are centrally derived and executed by the Dynamic Schema Engine.
2. **Aggregate (`Rulepack::Aggregate`)**: Merges multiple rule fragments and common skills into single-file "skills" for platforms like Crush, Goose, Codex, and Droid, reading platform-specific target configurations from `build/index.yaml` and storing results under `build/<agent>/skills/vendor/`.
3. **Install (`Rulepack::Installer`)**: Installs rules to active platform directories using symlinks, direct copies, config injections, or marker-based boundaries. Supports transaction safety via automatic backup generation and strict collision strategies. Updates the local installed database (`data/index.yaml`).
4. **Uninstall (`Rulepack::Uninstaller`)**: Performs surgical, marker-aware uninstallation to restore files to their pre-installation state, gracefully removing lines or files and updating the database state.
5. **Verify & Fix (`Rulepack::Verify` & `Rulepack::Fix`)**: Runs live reconciliation of the filesystem against the master database, flagging modified, deleted, or missing package assets, and providing automatic drift repair.

---

## 🧱 Modular Architecture & Code Quality

To maintain optimal code health and prevent god-object clutter, the installer and E2E scripts are partitioned into highly specialized modules under [lib/rulepack/](file:///home/aristo/Projects/agent-rule-sync/lib/rulepack/):

### God Object Decomposition
*   **[transaction.rb](file:///home/aristo/Projects/agent-rule-sync/lib/rulepack/lib/transaction.rb)**: Manages atomic transaction logs, backups, and safe directory rollbacks.
*   **[install_handlers.rb](file:///home/aristo/Projects/agent-rule-sync/lib/rulepack/lib/install_handlers.rb)**: Coordinates low-level copy, symlink, and injection/append routines (marker-aware splicing).
*   **[skill_bundle.rb](file:///home/aristo/Projects/agent-rule-sync/lib/rulepack/lib/skill_bundle.rb)**: Resolves complex directory skill-bundles, selectively caching sub-skills and parsing manifests.
*   **[tui_selector.rb](file:///home/aristo/Projects/agent-rule-sync/lib/rulepack/lib/tui_selector.rb)**: Handles terminal keyboard inputs, formatted menu draws, and multi-selection prompts.
*   **[build_pipeline.rb](file:///home/aristo/Projects/agent-rule-sync/lib/rulepack/build_pipeline.rb)**: Orchestrates sequential build stage progression (:fetch → :translate → :schema_engine → :transform) and stage-transition validations.
*   **[schema_engine.rb](file:///home/aristo/Projects/agent-rule-sync/lib/rulepack/schema_engine.rb)**: Centralized Dynamic Schema Engine that normalizes document structure (YAML frontmatter, emoji policies, ATX heading style, dash bullets) using platform mappings.

### Programmatic Modules (Call-Aware)
All procedural pipeline components (`build.rb`, `verify.rb`, `fix.rb`, `aggregate.rb`) are wrapped inside namespaces (e.g. `Rulepack::Build`). They use caller-aware runner hooks at their bottom margins, allowing them to run programmatically when required, or as standalone executables from the CLI without side effects.

### Command Line Parsing Unification
*   **[cli_parser.rb](file:///home/aristo/Projects/agent-rule-sync/lib/rulepack/cli_parser.rb)**: Implements `Rulepack::CliParser`, unifying `ARGV` parsing, pacman flag conversions (`-S`, `-R`, `-Qk`, `-F`), selective configurations, and project scopes under a single robust interface.

---

## 🛠️ Pacman & makepkg Mimicry: Assessment of Success

Our core architectural blueprint is to **mimic the declarative simplicity and extreme robustness of Arch Linux's packaging ecosystem (`pacman` and `makepkg`)**. 

Below is an objective assessment of our mimicry model, highlighting exact parallels, successes, and future opportunities:

| Arch Linux Model | Rulepack Parallel | Assessment & Success Rate | Mechanics |
| :--- | :--- | :--- | :--- |
| **PKGBUILD (Bash Script)** | **`PKGBUILD` (YAML Descriptor)** | **9/10 (High)** | Arch uses shell scripts, which are flexible but insecure. We successfully adapted this into a safe, parser-friendly YAML schema while retaining exact metadata conventions (`pkgname`, `pkgver`, `pkgrel`, `epoch`, `order`, `arch`). |
| **`makepkg` (Build Tool)** | **`Rulepack::Build` (Build Engine)** | **9.5/10 (Extremely High)** | It fetches source archives (type `git`, `url`, `local`), validates SHA256 check-sums, uses a local content-addressed source cache, compiles files into target formats via the 4-stage build pipeline, and records an intermediate compilation manifest (`build/index.yaml`). |
| **`pacman -S` (Install)** | **`Rulepack::Installer` (Package Manager)** | **10/10 (Perfect)** | Injects rule files to paths, creates symlinks, and maintains an atomic master database (`data/index.yaml`). Enforces zero-assumptions target resolution, exact package matching, and supports pacman `-S` flag. |
| **`pacman -R` (Uninstall)** | **`Rulepack::Uninstaller` (Surgical Removal)** | **10/10 (Perfect)** | Recursively uninstalls platform rules, handles dependencies (virtual `provides`), performs marker-aware clean file-splicing, enforces Tam Eşleşme (Exact Match), and supports pacman `-R` flag. |
| **`pacman -Qk` (Verify)** | **`Rulepack::Verify` (Drift CMS)** | **10/10 (Perfect)** | Performs full SHA256 integrity audits on installed rule/skill files. Enforces strict parameters, exact package names, and supports pacman `-Qk` flag. |
| **`pacman -F` (Fix)** | **`Rulepack::Fix` (Self-Healing)** | **10/10 (Perfect)** | Automatically identifies deleted, altered, or corrupted assets on disk, offering a self-healing `fix` command to repair the installation using exact targets and pacman `-F` flag. |
| **`libalpm` Versioning** | **`vercmp` algorithm (Ruby)** | **10/10 (Perfect)** | Fully implements Arch Linux's strict `epoch:pkgver-pkgrel` vercmp specifications, handling alphanumeric release suffixes, decimal segment comparisons, and epoch priority overrides. |

### Major Strengths of Our Mimicry
* **No External Dependencies**: Built strictly using Ruby's core standard library. Run it on any environment without gem bloat.
* **Surgical State Integrity**: Traditional package managers replace whole files. We adapted the concept to handle *live text files*, meaning we can surgically install rules into a shared `cli_config.yaml` or `.bashrc` using marker comments (`# Rulepack Start`, `# Rulepack End`) and roll them back flawlessly.
* **Self-Healing Architecture**: We don't just hope the packages remain in place. Running `bin/rulepack verify --target <platform>` detects if the user accidentally edited or deleted a symlinked/copied rule, and `bin/rulepack fix --target <platform>` automatically restores it from compilation cache.

---

## 🛠️ CLI Command Reference

Rulepack commands are wrapped inside `bin/rulepack` for convenience. Under the hood, they map to highly optimized Ruby libraries. Enforces **Zero Assumptions**—all platforms and required configurations must be explicitly defined, with no magic guessing.

```bash
# Compilation & Packaging
bin/rulepack build                                  # Compiles all packages to build/
bin/rulepack build --timing                         # Compiles with execution step timing

# Platform Deployment (Install / pacman -S)
bin/rulepack install [pkg] --target <plat|all>     # Installs package(s) to target platform(s)
bin/rulepack install [pkg] -t <plat|all> --select   # Prompts interactive TUI sub-skill selection menu
bin/rulepack install [pkg] -t <plat|all> --dry-run  # Previews file and symlink actions
bin/rulepack install [pkg] -t <plat|all> --force    # Overrides collision and install checks
bin/rulepack -S [pkg] -t <plat|all>                 # pacman -S flag shortcut equivalent

# Collision Management (Install option)
bin/rulepack install -t <plat> --on-collision stop       # (Default) Halts and reports collision
bin/rulepack install -t <plat> --on-collision ignore     # Skips conflicting files and continues
bin/rulepack install -t <plat> --on-collision overwrite  # Replaces files, generating a surgical backup
bin/rulepack install -t <plat> --on-collision append     # Appends rules using marker boundary blocks

# Maintenance & Reconciliation (verify / pacman -Qk & fix / pacman -F)
bin/rulepack verify [pkg] --target <plat|all>       # Performs live disk integrity and drift audit
bin/rulepack -Qk [pkg] -t <plat|all>                # pacman -Qk flag shortcut equivalent

bin/rulepack fix [pkg] --target <plat|all> [--auto] # Automatically repairs and reinstalls drifted files
bin/rulepack -F [pkg] -t <plat|all> [--auto]        # pacman -F flag shortcut equivalent

bin/rulepack audit [--strict] [--target PLAT]       # Audits declarative package descriptors & validation schemas

# De-registration (Uninstall / pacman -R)
bin/rulepack uninstall [pkg] --target <plat|all>    # Surgically removes rule fragments and restores state
bin/rulepack -R [pkg] -t <plat|all>                 # pacman -R flag shortcut equivalent

# Metadata Querying (query / pacman -Q)
bin/rulepack query <search_term>                    # Search package descriptors and variables
bin/rulepack -Q <search_term>                       # pacman -Q flag shortcut equivalent

```

---

## 📁 Package Scope & Path Resolution Rules

Installation paths resolve dynamically based on **Scope** (defined in `data/registry/platforms.yaml`):

### 1. User-Scoped Platforms (Global)
* **Scope**: `user`
* **Behavior**: Installed globally in the user's home folder.
* **Resolution**: Uses the home folder base path (e.g. `~/.config/gemini/`).
* **Defaults**: Running `bin/rulepack install --target all` (or `-S -t all`) will **automatically detect and install to all supported, globally installed user-scoped platforms** on the current system, giving you an instantaneous, zero-configuration sync.

### 2. Project-Scoped Platforms (Local)
* **Scope**: `project`
* **Behavior**: Installed inside the active project directory.
* **Resolution**: Enforces `--project <path>` (or `-p <path>`) parameter explicitly. No default guess work.
* **Fallback**: If a project-scoped platform is run without `--project`, Rulepack immediately raises a StandardError and aborts execution, completely preventing home folder leakage or repository pollution.

---

## 📦 Writing a PKGBUILD Descriptor

Create `data/packages/<pkgname>/PKGBUILD` (YAML). Below is the complete, canonical schema.

> [!IMPORTANT]
> **🤖 LLM / AI AGENT INSTRUCTION**: When asked to create a PKGBUILD:
> 1. You **MUST** include targets for **ALL** 14 supported platforms (`opencode`, `cursor`, `windsurf`, `claude-code`, `antigravity`, `oh-my-pi`, `crush`, `goose`, `droid`, `gemini-cli`, `qwen-code`, `codex`, `github-copilot`, `agents`).
> 2. **SCHEMA-DRIVEN ENGINE**: The build engine dynamically applies schema constraints (e.g. `frontmatter: strip`, `emoji_policy: strip`) based on `data/platforms/<agent>.yaml`. Therefore, you do **NOT** need to manually specify `transformer: strip-frontmatter` if the platform schema already declares it.
> 3. **DYNAMIC TRANSLATORS**: Before adding a new platform or complex format conversion, actively read the `data/platforms/<agent>.yaml` schema. If a complex structural change is required that the SchemaEngine does not support out-of-the-box, you **MUST** write a custom Ruby script under `data/translators/` and map it via `translate: custom:data/translators/your_script.rb`.

```yaml
---
pkgname: memory-management
pkgver: '1.2.0'
pkgrel: 1
epoch: 0
pkgdesc: Authoritative system rule governing coding agent memory retention and updates
arch: any
order: 10

source:
  - type: local
    path: src/memory.md
  # Alternatively, fetch remote source:
  # - type: url
  #   url: https://raw.githubusercontent.com/owner/repo/main/memory.md
  #   sha256: "d68c92a628a8d6e9f1a238bc321c89f5..."

targets:
  - platform: opencode
    format: directory
    output: 00-memory.md
    install:
      type: symlink
  - platform: cursor
    format: directory
    output: 00-memory.md
    install:
      type: symlink
  - platform: gemini-cli
    format: import
    output: memory-rule.md
    install:
      type: inject
  - platform: crush
    format: skill
    output: memory.md
    install:
      type: copy
  # ... (include all other targets here)

tags:
  - rules
  - memory
maintainer: Antigravity AI
license: MIT
```

---

## 🧪 Testing & Code Conventions

All contributions must pass the absolute quality threshold before integration:

* **Strict Subprocess Elimination**: We do not spawn subshells. All internal scripts are executed using direct, memory-isolated Ruby `load()` processes, maintaining environment integrity.
* **Immutable Strings**: Every file must declare `# frozen_string_literal: true` at the top.
* **Pathname API**: Use the object-oriented `Pathname` class for all file operations—avoid flat string concatenation for directories.
* **Run Tests**:
  ```bash
  rake test
  ```
  Ensure all unit, integration, cache, installation, and end-to-end (E2E) verification assertions pass cleanly (0 errors, 0 failures).
