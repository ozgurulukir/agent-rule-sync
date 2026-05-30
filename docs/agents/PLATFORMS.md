# Agent Platforms Reference

Complete reference for all supported agent platforms, their configuration locations, formats, and Rulepack integration details.

## Platform Index

| Platform | Scope | Type | Config Location | Install Command |
|----------|-------|------|-----------------|-----------------|
| [OpenCode](#opencode) | user | directory | `~/.config/opencode/rules/` | `bin/rulepack install opencode` |
| [Oh My Pi](#oh-my-pi) | user | directory | `~/.omp/agent/rules/` | `bin/rulepack install oh-my-pi` |
| [Crush](#crush) | user | skill | `~/.config/crush/crush.md` | `bin/rulepack install crush` |
| [Goose](#goose) | user | skill | `~/.local/share/goose/goose.md` | `bin/rulepack install goose` |
| [Droid](#droid) | user | skill | `~/.factory/AGENTS.md` | `bin/rulepack install droid` |
| [Gemini CLI](#gemini-cli) | user | directory | `~/.gemini/GEMINI.md` | `bin/rulepack install gemini-cli` |
| [Qwen Code](#qwen-code) | user | import | `~/.config/qwen/config.yaml` | `bin/rulepack install qwen-code` |
| [Cursor](#cursor) | project | directory | `.cursor/rules/` | `bin/rulepack install cursor --project .` |
| [Windsurf](#windsurf) | project | directory | `.windsurf/rules/` | `bin/rulepack install windsurf --project .` |
| [GitHub Copilot](#github-copilot) | project | import | `.github/copilot-instructions.md` | `bin/rulepack install github-copilot --project .` |
| [Claude Code](#claude-code) | project | directory | `.claude/rules/` | `bin/rulepack install claude-code --project .` |
| [Codex CLI](#codex-cli) | project | skill | `AGENTS.md` | `bin/rulepack install codex --project .` |
| [Antigravity](#antigravity) | user | directory | `~/.gemini/antigravity/.agent/skills/` | `bin/rulepack install antigravity` |
| [Agents](#agents) | user | directory | `~/.agents/rules/` | `bin/rulepack install agents` |

**Scope**: `user` = global (home directory), `project` = per-project (requires `--project` flag)

---

## Platform Details

### OpenCode

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.config/opencode/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Agents dir**: `agents/`
- **Install method**: symlink for rules, copy for skills/agents
- **Rules file**: `AGENTS.md` (rules can be appended via `--rules-to AGENTS.md`)
- **Config file**: `~/.config/opencode/opencode.jsonc`
- **Rules loading**: All `rules/*.md` files injected at session start via `AGENTS.md`
- **Update**: `opencode upgrade` (self-updater, multiple backends)

**Rulepack integration**: `bin/rulepack install opencode` → symlinks to `~/.config/opencode/rules/`

---

### Oh My Pi (omp)

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.omp/agent/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Agents dir**: `agents/`
- **Rules file**: `AGENTS.md` (rules can be appended via `--rules-to AGENTS.md`)
- **Install method**: symlink for rules, copy for skills/agents
- **Config file**: `~/.omp/agent/config.yml`
- **Features**: Hash-anchored edits, TTSR rules (zero context until triggered), IPython kernel
- **Update**: `omp update` (bun-installed self-updater)

**Rulepack integration**: `bin/rulepack install oh-my-pi` → symlinks to `~/.omp/agent/rules/`

---

### Crush

- **Type**: skill
- **Scope**: user
- **Base path**: `~/.config/crush/`
- **Skill file**: `crush.md`
- **Install method**: copy (single vendor skill file)
- **Provider**: ZAI (api.z.ai)
- **Features**: Session-based, LSP-enhanced, mid-session model switching
- **Update**: `sudo apt update && sudo apt install crush` (Debian repo)

**Rulepack integration**: `bin/rulepack install crush` → copies `build/crush/skills/vendor/crush.md` to `~/.config/crush/crush.md`

---

### Goose

- **Type**: skill
- **Scope**: user
- **Base path**: `~/.local/share/goose/`
- **Skill file**: `goose.md` (guardrails)
- **Recipes dir**: `.goose/recipes/` (YAML recipe-based agent configuration, supported as of late 2025)
- **Install method**: copy (vendor skill file)
- **Persistent instructions**: `GOOSE_MOIM_MESSAGE_FILE` env var → `~/.config/goose/guardrails.md` (re-read every turn, 64KB limit)
- **Update**: `goose update` (npm)

**Rulepack integration**: `bin/rulepack install goose` → copies `build/goose/skills/vendor/goose.md` to `~/.local/share/goose/goose.md`

---

### Droid

- **Type**: skill
- **Scope**: user
- **Base path**: `~/.factory/`
- **Skill file**: `droid.md` (installed as `AGENTS.md`)
- **Install method**: copy
- **Rules loading**: `AGENTS.md` hierarchy (project → parents → `~/.factory/AGENTS.md`)
- **Update**: `droid update` (if available)

**Rulepack integration**: `bin/rulepack install droid` → copies `build/droid/skills/vendor/droid.md` to `~/.factory/AGENTS.md`

---

### Gemini CLI

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.gemini/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Rules file**: `GEMINI.md` (rules can be appended via `--rules-to GEMINI.md`)
- **Install method**: append for rules, copy for skills
- **Auth**: OAuth personal
- **Update**: `gemini extensions update --all` (CLI via npm; extensions separate)

**Rulepack integration**: `bin/rulepack install gemini-cli` → appends rules to `~/.gemini/GEMINI.md` using marker-boundary blocks

---

### Qwen Code

- **Type**: import
- **Scope**: user
- **Base path**: `~/.config/qwen/`
- **Config file**: `config.yaml`
- **Install method**: inject `@import` lines
- **Auth**: Qwen OAuth
- **Features**: auto-update, git co-author, chat compression at 70% threshold

**Rulepack integration**: `bin/rulepack install qwen-code` → injects `@import` lines into `~/.config/qwen/config.yaml`

---

### Cursor

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Rules dir**: `.cursor/rules/`
- **Skills dir**: `.cursor/skills/`
- **Agents dir**: `.cursor/agents/`
- **Install method**: symlink for rules, copy for skills/agents
- **Features**: AI-first IDE (VS Code fork), team rules via dashboard, `.mdc` frontmatter support
- **Update**: Built-in updater (menu → Help → Check for Updates)

**Rulepack integration**: `bin/rulepack install cursor --project /path/to/project` → symlinks to `.cursor/rules/`

---

### Windsurf

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Rules dir**: `.windsurf/rules/`
- **Agents dir**: `.windsurf/agents/`
- **Rules file (root)**: `.windsurfrules` (optional)
- **Install method**: symlink
- **Features**: Codeium's agentic IDE (Cascade), GUI rule editor, `.mdc` frontmatter support
- **Update**: Built-in updater

**Rulepack integration**: `bin/rulepack install windsurf --project .` → symlinks to `.windsurf/rules/`

---

### GitHub Copilot

- **Type**: import
- **Scope**: project
- **Base path**: `.github/`
- **Config file**: `copilot-instructions.md`
- **Install method**: copy (separate instruction file)
- **Features**: VS Code extension (also GitHub web, CLI), supports `.github/instructions/*.md` additional files
- **Update**: VS Code extension update

**Rulepack integration**: `bin/rulepack install github-copilot --project .` → copies instruction files to `.github/`

---

### Claude Code

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Rules dir**: `.claude/rules/`
- **Skills dir**: `.claude/skills/`
- **Agents dir**: `.claude/agents/`
- **Install method**: symlink for rules, copy for skills/agents
- **Config**: `CLAUDE.md` in project root (loaded automatically), plus per-directory rules in `.claude/rules/`
- **Update**: `claude update` (if installed via npm)

**Rulepack integration**: `bin/rulepack install claude-code --project .` → symlinks to `.claude/rules/`

---

### Codex CLI

- **Type**: skill
- **Scope**: project
- **Base path**: project root (`.`)
- **Skill file**: `AGENTS.md`
- **Install method**: copy (vendor skill aggregation)
- **Rules loading**: Searches up directory tree for `AGENTS.md`; supports `AGENTS.override.md`
- **Features**: Terminal agent, project-aware, supports subagents
- **Update**: `codex update` (npm)

**⚠️ Important**: Codex uses `AGENTS.md` as a **project-level instruction file** (layered guidance discovered by walking up the directory tree). This is completely different from `format: agent`. Codex has no `agents_dir` — do NOT write `format: agent` targets for codex; they will be silently skipped. The `skill_file: AGENTS.md` field means vendor rules are aggregated into a single `AGENTS.md` file at the project root.

**Rulepack integration**: `bin/rulepack install codex --project .` → generates vendor skill and writes to `AGENTS.md`

---

### Antigravity

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.gemini/antigravity/`
- **Skills dir**: `.agent/skills/`
- **Rules file**: `GEMINI.md`
- **Install method**: copy (skill-bundle), append (rules)
- **Skills**: antigravity-skills (300+ sub-skills from upstream)

**Rulepack integration**: `bin/rulepack install antigravity` → copies skill-bundle to `~/.gemini/antigravity/.agent/skills/`

---

### Agents

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.agents/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Install method**: symlink for rules, copy for skills

**Rulepack integration**: `bin/rulepack install agents` → symlinks/copies to `~/.agents/rules/` and `~/.agents/skills/`

---

## Platform Registry Schema

Platforms are defined in `data/registry/platforms.yaml`:

```yaml
<platform_id>:
  type: directory|import|skill      # Required
  scope: user|project               # Required: installation scope
  display_name: <string>            # Required: human-readable name
  base_path: <path>                 # Required: base directory (user: ~/.config/..., project: .)

  # For directory platforms:
  rules_dir: <relative-path>        # Required (type=directory)
  skills_dir: <relative-path>       # Optional (type=directory)
  docs_dir: <relative-path>         # Optional (type=directory)
  agents_dir: <relative-path>       # Optional: agent installation directory
  rules_file: <filename>            # Optional: single file for rule append (--rules-to)
  rule_install:
    type: symlink|copy|append       # Required (type=directory)
  skill_install:
    type: copy|append               # Optional (type=directory)

  # For import platforms:
  config_file: <filename>           # Required (type=import)
  rule_install:
    type: inject|copy               # Required (type=import)
    directive: '@import'            # Optional (for inject)
  skill_install:
    type: inject|copy               # Optional (type=import)

  # For skill platforms:
  skill_file: <filename>            # Required (type=skill)
  rule_install: null                # Not used for skill platforms
  skill_install:
    type: copy|append               # Required (type=skill)

  # Optional:
  prerequisites:                    # Informational tool requirements
    tools: [<tool-name>, ...]
```

**Validation**:
- `type` must be one of: `directory`, `import`, `skill`
- `scope` must be one of: `user`, `project`
- Required fields per type:
  - `directory`: `rules_dir`, `rule_install.type`
  - `import`: `config_file`, `rule_install.type`
  - `skill`: `skill_file`, `skill_install.type`
- `base_path` must be tilde-expandable absolute path (user-level) or `.` (project-level)
- `agents_dir` enables `format: agent` target support (currently: opencode, oh-my-pi, cursor, windsurf, claude-code)

---

## Installation Scope

### User-Level Platforms

Install to fixed locations in home directory or system paths:

```bash
bin/rulepack install opencode    # → ~/.config/opencode/rules/
bin/rulepack install oh-my-pi    # → ~/.omp/agent/rules/
bin/rulepack install crush       # → ~/.config/crush/crush.md
bin/rulepack install goose       # → ~/.local/share/goose/goose.md
bin/rulepack install antigravity # → ~/.gemini/antigravity/.agent/skills/
```

No `--project` flag needed. `base_path` is absolute (tilde-expanded).

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

## Install Types

### Symlink (`symlink`)

Creates a relative symbolic link from the platform's rules directory to the built artifact in `build/<platform>/`.

- Used by: OpenCode, Oh My Pi, Cursor, Windsurf, Claude Code
- Idempotent: replaces stale symlinks automatically

### Copy (`copy`)

Copies the built artifact to the target location. Only copies if checksum differs.

- Used by: Crush, Goose, Droid, GitHub Copilot, Antigravity (skill-bundle), agents
- Preserves existing files if unchanged

### Inject (`inject`)

Prepends an `@import` directive line to the platform's config file. Deduplicates on re-install.

- Used by: Gemini CLI, Qwen Code
- Appends to top of file (after frontmatter if present)

### Append (`append`)

Appends content to the target file using marker-boundary blocks. Used for vendor skill aggregation, rules-file injection into single-file platforms, or multi-rule platforms that consolidate into one file.

- Used by: Antigravity (`GEMINI.md`), platforms using `--rules-to rules_file` (e.g., OpenCode, Oh My Pi, Claude Code injecting into `AGENTS.md`)
- Supports marker-aware replace: re-install updates the block between `<!-- rulepack:<pkg> start -->` / `<!-- rulepack:<pkg> end -->` instead of duplicating
- Concatenates with `---\n\n` separator when no prior marker exists

---

## Format Types

### `directory`

Multiple rule files in a directory structure. Files are symlinked or copied into the platform's `rules_dir`.

- Examples: OpenCode, Cursor, Claude Code
- Output: individual `.md` files per rule

### `skill`

Single skill file consumed by the agent. Content is typically aggregated from multiple rule fragments.

- Examples: Crush, Goose, Droid, Codex CLI
- Output: single `*.md` skill file

### `import`

Config file with `@import` directives. The SSoT system injects import lines pointing to built artifacts.

- Examples: Gemini CLI, Qwen Code
- Output: `@import` lines added to config

### `skill-bundle`

Entire directory tree of skills copied as-is. Used for large skill collections with sub-skill selection.

- Examples: Antigravity (300+ sub-skills)
- Output: entire directory copied to target

### `agent`

Custom agent definition installed to the platform's `agents_dir`. Always uses copy (not symlink).

- Examples: `ruby-update-signatures` (pkg_type: agent)
- Output: directory copied to `agents_dir`
- Requires: `agents_dir` defined in platform registry
- Platforms without `agents_dir` skip `format: agent` targets

---

## Troubleshooting

### "Platform not found"

```bash
# List available platforms
bin/rulepack platforms
```

Ensure the platform ID matches exactly (e.g., `opencode`, not `OpenCode`).

### "Path traversal not allowed"

Custom transformer or source paths must resolve within the repository root. Check that paths don't contain `..` or absolute paths outside the repo.

### "Checksum mismatch"

Source or built artifact has changed since last build. Run `bin/rulepack build` to rebuild.

### "No target for platform, skipping"

The package has no target defined for the requested platform. Check the PKGBUILD `targets:` section.

---

## See Also

- [Platforms Registry](REFERENCE.md#platform-registry-schema) — YAML schema
- [Usage](USAGE.md) — Install workflows and commands
- [Architecture](ARCHITECTURE.md) — System design
