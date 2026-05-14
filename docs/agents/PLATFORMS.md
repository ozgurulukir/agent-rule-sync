# Agent Platforms Reference

Complete reference for all supported agent platforms, their configuration locations, formats, and SSoT integration details.

## Platform Index

| Platform | Scope | Type | Config Location | Install Command |
|----------|-------|------|-----------------|-----------------|
| [OpenCode](#opencode) | user | directory | `~/.config/opencode/rules/` | `ruby ssot/install.rb opencode` |
| [Oh My Pi](#oh-my-pi) | user | directory | `~/.config/oh-my-pi/rules/` | `ruby ssot/install.rb oh-my-pi` |
| [Crush](#crush) | user | skill | `/usr/local/share/crush/crush.md` | `ruby ssot/install.rb crush` |
| [Goose](#goose) | user | skill | `~/.local/share/goose/goose.md` | `ruby ssot/install.rb goose` |
| [Droid](#droid) | user | skill | `~/.config/droid/droid.md` | `ruby ssot/install.rb droid` |
| [Gemini CLI](#gemini-cli) | user | import | `~/.config/gemini/GEMINI.md` | `ruby ssot/install.rb gemini-cli` |
| [Qwen Code](#qwen-code) | user | import | `~/.config/qwen/QWEN.md` | `ruby ssot/install.rb qwen-code` |
| [Cursor](#cursor) | project | directory | `.cursor/rules/` | `ruby ssot/install.rb cursor --project .` |
| [Windsurf](#windsurf) | project | directory | `.windsurf/rules/` | `ruby ssot/install.rb windsurf --project .` |
| [GitHub Copilot](#github-copilot) | project | import | `.github/copilot-instructions.md` | `ruby ssot/install.rb github-copilot --project .` |
| [Claude Code](#claude-code) | project | directory | `.claude/rules/` + `CLAUDE.md` | `ruby ssot/install.rb claude-code --project .` |
| [Codex CLI](#codex-cli) | project | skill | `AGENTS.md` | `ruby ssot/install.rb codex --project .` |

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

**SSoT integration**: `ssot/install.rb opencode` → symlinks to `~/.config/opencode/rules/`

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

**SSoT integration**: `ssot/install.rb oh-my-pi` → symlinks to `~/.config/oh-my-pi/rules/`

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

**SSoT integration**: `ssot/install.rb crush` → copies `build/crush/skills/vendor/crush.md` to `/usr/local/share/crush/crush.md`

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

**SSoT integration**: `ssot/install.rb goose` → copies `build/goose/skills/vendor/goose.md` to `~/.local/share/goose/goose.md`

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

**SSoT integration**: `ssot/install.rb droid` → copies `build/droid/skills/vendor/droid.md` to `~/.factory/AGENTS.md`

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

**SSoT integration**: `ssot/install.rb gemini-cli` → injects `@import` lines into `~/.config/gemini/GEMINI.md`

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

**SSoT integration**: `ssot/install.rb qwen-code` → injects `@import` lines into `~/.config/qwen/QWEN.md`

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

**SSoT integration**: `ruby ssot/install.rb cursor --project /path/to/project` → symlinks to `.cursor/rules/`

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

**SSoT integration**: `ruby ssot/install.rb windsurf --project .` → symlinks to `.windsurf/rules/`

---

### GitHub Copilot

- **Type**: import
- **Scope**: project
- **Base path**: `.github/`
- **Config file**: `copilot-instructions.md`
- **Install method**: copy (separate instruction file)
- **Features**: VS Code extension (also GitHub web, CLI), supports `.github/instructions/*.md` additional files
- **Update**: VS Code extension update

**SSoT integration**: `ruby ssot/install.rb github-copilot --project .` → copies instruction files to `.github/`

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

**SSoT integration**: `ruby ssot/install.rb claude-code --project .` → symlinks to `.claude/rules/`

---

### Codex CLI

- **Type**: skill
- **Scope**: project
- **Base path**: project root (`.`)
- **Skill file**: `AGENTS.md`
- **Install method**: copy (vendor skill aggregation)
- **Provider**: OpenAI (Codex models)
- **Rules loading**: Searches up directory tree for `AGENTS.md`; supports `AGENTS.override.md` and `project_doc_fallback_filenames`
- **Update**: `codex update` (npm)

**SSoT integration**: `ruby ssot/install.rb codex --project .` → generates vendor skill and writes to `AGENTS.md`

---

## Platform Registry Schema

Platforms are defined in `ssot/registry/platforms.yaml`:

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
ruby ssot/install.rb opencode    # → ~/.config/opencode/rules/
ruby ssot/install.rb crush       # → /usr/local/share/crush/crush.md
ruby ssot/install.rb goose       # → ~/.local/share/goose/goose.md
```

No `--project` flag needed. `base_path` is absolute (tilde-expanded).

### Project-Level Platforms

Install to current project repository:

```bash
cd /path/to/project
ruby ssot/install.rb cursor --project .
# or (default to current dir if --project omitted)
ruby ssot/install.rb cursor
```

`base_path` is `.` (current directory), resolved relative to `--project` path. All installed files are version-controlled alongside project code.

**Important**: For project-level platforms, always run from project root or specify `--project` explicitly. Uninstall requires the same `--project` flag to locate files.

---

## Format Types

### directory

Files are placed in a directory (`rules/` or `skills/`) as individual markdown files. Most agents support this format.

- **Rules**: go to `rules_dir` (e.g., `rules/00-memory.md`)
- **Skills**: go to `skills_dir` (e.g., `skills/vibe-security.md`)
- **Install**: typically `symlink` for rules (space-efficient, auto-update), `copy` for skills

**Agents**: OpenCode, Oh My Pi, Cursor, Windsurf, Claude Code

### import

Content is injected into a configuration file as `@import` directives, or copied as separate instruction files.

- **Inject**: prepend `@import "filename.md"` to `config_file` (deduplicated on re-install)
- **Copy**: write separate instruction file to `base_path` (used by GitHub Copilot)

**Agents**: Gemini CLI, Qwen Code (inject); GitHub Copilot (copy)

### skill

All rules and skills are concatenated into a single skill file (vendor skill). Skill agents read this one file for all instructions.

- **Aggregation**: `aggregate-skills.rb` combines rule fragments + common/agent-specific skills
- **Install**: copy the aggregated vendor file to agent's `skill_file` location
- **Order**: Rules sorted by `order` field in PKGBUILD; header/footer from agent-specific skills

**Agents**: Crush, Goose, Droid, Codex CLI

---

## Uninstall Behavior

| Platform Type | What Uninstall Does |
|---------------|---------------------|
| `directory` | Removes symlinks/files from `rules_dir`/`skills_dir` |
| `import` | Removes `@import` lines from `config_file` (future: automatic removal) |
| `skill` | Removes vendor skill file; re-aggregates to exclude uninstalled packages |

For skill platforms, uninstall triggers re-aggregation to regenerate the vendor file without the removed package's contributions.

---

## See Also

- [Architecture](ARCHITECTURE.md) — System design and data flow
- [Usage](USAGE.md) — Installation workflows and commands
- [Reference](REFERENCE.md) — PKGBUILD format, transformer API, index schema
- [Transforms](TRANSFORMS.md) — Transformer system documentation
- [Upstream](UPSTREAM.md) — Upstream source management
