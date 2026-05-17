# Agent Platforms Reference

Complete reference for all supported agent platforms, their configuration locations, formats, and Rulepack integration details.

## Platform Index

| Platform | Scope | Type | Config Location | Install Command |
|----------|-------|------|-----------------|-----------------|
| [OpenCode](#opencode) | user | directory | `~/.config/opencode/rules/` | `bin/rulepack install opencode` |
| [Oh My Pi](#oh-my-pi) | user | directory | `~/.config/oh-my-pi/rules/` | `bin/rulepack install oh-my-pi` |
| [Crush](#crush) | user | skill | `/usr/local/share/crush/crush.md` | `bin/rulepack install crush` |
| [Goose](#goose) | user | skill | `~/.local/share/goose/goose.md` | `bin/rulepack install goose` |
| [Droid](#droid) | user | skill | `~/.factory/AGENTS.md` | `bin/rulepack install droid` |
| [Gemini CLI](#gemini-cli) | user | import | `~/.config/gemini/cli_config.yaml` | `bin/rulepack install gemini-cli` |
| [Qwen Code](#qwen-code) | user | import | `~/.config/qwen/config.yaml` | `bin/rulepack install qwen-code` |
| [Cursor](#cursor) | project | directory | `.cursor/rules/` | `bin/rulepack install cursor --project .` |
| [Windsurf](#windsurf) | project | directory | `.windsurf/rules/` | `bin/rulepack install windsurf --project .` |
| [GitHub Copilot](#github-copilot) | project | import | `.github/copilot-instructions.md` | `bin/rulepack install github-copilot --project .` |
| [Claude Code](#claude-code) | project | directory | `.claude/rules/` + `CLAUDE.md` | `bin/rulepack install claude-code --project .` |
| [Codex CLI](#codex-cli) | project | skill | `AGENTS.md` | `bin/rulepack install codex --project .` |
| [Antigravity](#antigravity) | project | directory | `.agent/skills/` | `bin/rulepack install antigravity --project .` |
| [Agents](#agents) | user | directory | `~/.config/agents/rules/` | `bin/rulepack install agents` |

**Scope**: `user` = global (home directory), `project` = per-project (requires `--project` flag)

---

## Platform Details

### OpenCode

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.config/opencode/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Install method**: symlink for rules, copy for skills
- **Config file**: `~/.config/opencode/opencode.jsonc`
- **Rules loading**: All `rules/*.md` files injected at session start via `AGENTS.md`
- **Update**: `opencode upgrade` (self-updater, multiple backends)

**Rulepack integration**: `bin/rulepack install opencode` → symlinks to `~/.config/opencode/rules/`

---

### Oh My Pi (omp)

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.config/oh-my-pi/`
- **Rules dir**: `rules/`
- **Install method**: symlink
- **Config file**: `~/.omp/agent/config.yml`
- **Skills**: Built-in coderlm, line-repetition-control
- **Features**: Hash-anchored edits, TTSR rules (zero context until triggered), IPython kernel
- **Update**: `omp update` (bun-installed self-updater)

**Rulepack integration**: `bin/rulepack install oh-my-pi` → symlinks to `~/.config/oh-my-pi/rules/`

---

### Crush

- **Type**: skill
- **Scope**: user
- **Base path**: `/usr/local/share/crush/`
- **Skill file**: `crush.md`
- **Install method**: copy (single vendor skill file)
- **Provider**: ZAI (api.z.ai)
- **MCP**: zai-mcp-server (stdio), web-search-prime, web-reader
- **Features**: Session-based, LSP-enhanced, mid-session model switching
- **Update**: `sudo apt update && sudo apt install crush` (Debian repo)

**Rulepack integration**: `bin/rulepack install crush` → copies `build/crush/skills/vendor/crush.md` to `/usr/local/share/crush/crush.md`

---

### Goose

- **Type**: skill
- **Scope**: user
- **Base path**: `~/.local/share/goose/`
- **Skill file**: `goose.md` (guardrails)
- **Install method**: copy (vendor skill file)
- **Provider**: custom z.ai coding plan (Anthropic-compatible)
- **Model**: glm-5.1 (128K context)
- **Persistent instructions**: `GOOSE_MOIM_MESSAGE_FILE` env var → `~/.config/goose/guardrails.md` (re-read every turn, 64KB limit)
- **Update**: `goose update` (npm)

**Rulepack integration**: `bin/rulepack install goose` → copies `build/goose/skills/vendor/goose.md` to `~/.local/share/goose/goose.md`

---

### Droid

- **Type**: skill
- **Scope**: user
- **Base path**: `~/.config/droid/`
- **Skill file**: `droid.md`
- **Install method**: copy
- **Config**: No persistent file; uses `--settings` flag at runtime
- **Rules loading**: `AGENTS.md` hierarchy (project → parents → `~/.factory/AGENTS.md`)
- **Update**: `droid update` (if available)

**Rulepack integration**: `bin/rulepack install droid` → copies `build/droid/skills/vendor/droid.md` to `~/.factory/AGENTS.md`

---

### Gemini CLI

- **Type**: import
- **Scope**: user
- **Base path**: `~/.config/gemini/`
- **Config file**: `cli_config.yaml`
- **Install method**: inject `@import` lines
- **Auth**: OAuth personal
- **Extensions**: `gemini extensions install` (stored in `~/.gemini/extensions/`)
- **Update**: `gemini extensions update --all` (CLI via npm; extensions separate)

**Rulepack integration**: `bin/rulepack install gemini-cli` → injects `@import` lines into `~/.config/gemini/cli_config.yaml`

---

### Qwen Code

- **Type**: import
- **Scope**: user
- **Base path**: `~/.config/qwen/`
- **Config file**: `config.yaml`
- **Install method**: inject `@import` lines
- **Auth**: Qwen OAuth
- **MCP**: context7
- **Skills**: ast-grep
- **Permissions**: fine-grained allow/ask/deny per tool pattern
- **Features**: auto-update, git co-author, chat compression at 70% threshold

**Rulepack integration**: `bin/rulepack install qwen-code` → injects `@import` lines into `~/.config/qwen/config.yaml`

---

### Cursor

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Rules dir**: `.cursor/rules/`
- **Skills dir**: `.cursor/skills/`
- **Install method**: symlink
- **Config**: Project-level rules, version-controlled
- **MCP**: `~/.cursor/mcp.json` (global) and `.cursor/mcp.json` (project)
- **Features**: AI-first IDE (VS Code fork), team rules via dashboard, `.mdc` frontmatter support
- **Update**: Built-in updater (menu → Help → Check for Updates)

**Rulepack integration**: `bin/rulepack install cursor --project /path/to/project` → symlinks to `.cursor/rules/`

---

### Windsurf

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Rules dir**: `.windsurf/rules/`
- **Rules file (root)**: `.windsurfrules` (optional)
- **Install method**: symlink
- **Features**: Codeium's agentic IDE (Cascade), GUI rule editor with always-active / context-specific rules, `.mdc` frontmatter support
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
- **Install method**: symlink
- **Config**: `CLAUDE.md` in project root (loaded automatically), plus per-directory rules in `.claude/rules/`
- **Provider**: Anthropic Claude 4 (Sonnet 4, Opus 4)
- **Update**: `claude update` (if installed via npm)

**Rulepack integration**: `bin/rulepack install claude-code --project .` → symlinks to `.claude/rules/`

---

### Codex CLI

- **Type**: skill
- **Scope**: project
- **Base path**: project root (`.`)
- **Skill file**: `AGENTS.md`
- **Install method**: copy (vendor skill aggregation)
- **Provider**: OpenAI (Codex models)
- **Rules loading**: Searches up directory tree for `AGENTS.md`; supports `AGENTS.override.md` and `project_doc_fallback_filenames` config; truncates at 32 KiB by default
- **Features**: Terminal agent, project-aware, supports subagents (general, Explore, code-reviewer)
- **Update**: `codex update` (npm)

**Rulepack integration**: `bin/rulepack install codex --project .` → generates vendor skill and writes to `AGENTS.md`

---

### Antigravity

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Skills dir**: `.agent/skills/`
- **Install method**: copy (skill-bundle)
- **Skills**: antigravity-skills (306 sub-skills from `github.com/rmyndharis/antigravity-skills`)

**Rulepack integration**: `bin/rulepack install antigravity --project .` → copies skill-bundle to `.agent/skills/antigravity-skills/`

---

### Agents

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.config/agents/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Install method**: symlink for rules, copy for skills

**Rulepack integration**: `bin/rulepack install agents` → symlinks/copies to `~/.config/agents/rules/` and `~/.config/agents/skills/`

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
  rule_install:
    type: symlink|copy              # Required (type=directory)
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
```

**Validation**:
- `type` must be one of: `directory`, `import`, `skill`
- `scope` must be one of: `user`, `project`
- Required fields per type:
  - `directory`: `rules_dir`, `rule_install.type`
  - `import`: `config_file`, `rule_install.type`
  - `skill`: `skill_file`, `skill_install.type`
- `base_path` must be tilde-expandable absolute path (user-level) or `.` (project-level)

---

## Installation Scope

### User-Level Platforms

Install to fixed locations in home directory or system paths:

```bash
bin/rulepack install opencode    # → ~/.config/opencode/rules/
bin/rulepack install crush       # → /usr/local/share/crush/crush.md
bin/rulepack install goose       # → ~/.local/share/goose/goose.md
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
bin/rulepack install antigravity

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

- Used by: Crush, Goose, Droid, GitHub Copilot, Antigravity (skill-bundle)
- Preserves existing files if unchanged

### Inject (`inject`)

Prepends an `@import` directive line to the platform's config file. Deduplicates on re-install.

- Used by: Gemini CLI, Qwen Code
- Appends to top of file (after frontmatter if present)

### Append (`append`)

Appends content to the target file. Used for vendor skill aggregation.

- Used by: Codex CLI (vendor skill file)
- Concatenates with `---\n\n` separator

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

- Examples: Antigravity (306 sub-skills)
- Output: entire directory copied to target

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
