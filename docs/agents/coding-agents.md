# Coding Agents

All AI coding agents installed on this workstation, their configuration, update commands, and known quirks.

## Overview

| Agent | Version | Binary | Purpose | Rules Format |
|-------|---------|--------|---------|--------------|
| **opencode** | 1.14.33 | `~/.opencode/bin/opencode` | Primary coding agent / editor | directory (symlinks) |
| **oh-my-pi** | 14.6.6 | `~/.bun/bin/omp` | Pi coding agent (this harness) | directory (symlinks) |
| **crush** | 0.65.2 | `/usr/bin/crush` | Charmbracelet coding agent (Go) | skill (concatenated) |
| **gemini-cli** | 0.40.1 | `~/.local/bin/gemini` | Google Gemini CLI | import (`@` syntax) |
| **qwen-code** | 0.15.6 | `~/.local/bin/qwen` | Alibaba Qwen Code CLI | import (`@` syntax) |
| **goose** | latest | `~/.local/bin/goose` | Block's open source agent | skill (concatenated) |
| **droid** | 0.109.1 | `~/.local/bin/droid` | Factory's AI coding agent | skill (concatenated) |
| **cicada** | pip | `~/.local/bin/cicada` | Codebase search/exploration (MCP server) | N/A (not a coding agent) |
| **jan** | 0.7.9 | `~/.local/bin/jan` | Local model runner (LlamaCPP/MLX) | N/A (not a coding agent) |

> **SSoT Source**: All agent rules are generated from `~/Projects/your-project/ssot/`. See [docs/agents/ssot-architecture.md](docs/agents/ssot-architecture.md).

## Installation Locations

All agents are installed under `~/.local/` via npm or pip, except:
- **opencode**: self-installed at `~/.opencode/bin/` (has its own update mechanism)
- **crush**: installed via apt from Charm repo (`/usr/bin/crush`)
- **oh-my-pi**: installed via bun (`~/.bun/bin/omp`)
- **jan**: npm global (`~/.local/bin/jan`)

## Update Commands

See `docs/cli-tool-updates.md` for the full reference. Quick summary:

```bash
opencode upgrade          # self-updater
omp update                # Oh My Pi (bun-installed)
gemini extensions update --all  # extensions only (CLI updates via npm)
qwen auth                 # re-auth if needed (CLI updates via npm)
goose update              # if available (CLI updates via npm)
jan update                # self-updater

# npm global batch update:
npm update -g             # updates gemini-cli, qwen-code
```

## Configuration Details

### opencode

**Config**: `~/.config/opencode/opencode.jsonc`

- Provider: StepFun (step_plan)
- MCP servers: zai-mcp-server, web-search-prime, web-reader, zread, context7
- Skills: ast-grep, line-repetition-control
- Rules: loaded from `~/.config/opencode/rules/*.md` (symlinks to SSoT)
- Compaction: auto + prune, reserved 10000 tokens
- Agent modes: `plan` (temp 0.5) and `build` (temp 1.1)

**How rules load**: `AGENTS.md` is the global context file. `instructions` field loads all `rules/*.md` symlinks. Both injected at session start.

**SSoT integration**: Directory format — `make sync` creates symlinks in `~/.config/opencode/rules/` pointing to `~/Projects/your-project/ssot/rules/`.

### crush

**Config**: `~/.config/crush/crush.json`

- Charmbracelet's Go-based coding agent (23k+ GitHub stars)
- Installed via apt (`/usr/bin/crush`) from Charm's Debian repo
- Provider: ZAI (OpenAI-compatible API at `api.z.ai`)
- MCP servers: zai-mcp-server (stdio), web-search-prime (http), web-reader (http), zread (http)
- Session-based: maintains multiple work sessions per project
- LSP-enhanced: uses LSP for additional context
- Switch models mid-session while preserving context
- Skills: `.agents/skills/` (builtin-skills, shell-builtins)

**How rules load**: Reads `AGENTS.md` in standard hierarchy. Supports hooks, custom tools, and templates.

**Update**: `sudo apt update && sudo apt install crush` (Debian repo at `repo.charm.sh`).

**SSoT integration**: Skill format — `make sync` copies `ssot/skills/vendor/crush.md` → `~/.config/agents/skills/workstation-rules/SKILL.md`.

### oh-my-pi (omp)

**Config**: `~/.omp/agent/config.yml`

- TypeScript/Rust monorepo coding agent by can1357 (fork of badlogic/pi-mono)
- Installed via bun: `~/.bun/bin/omp`
- Model roles: default (zai/glm-5-turbo), smol (gemini-3-flash), slow (zai/glm-5.1), commit (gemini-3.1-flash-lite)
- Providers: stepfun-plan, zhipu, zhipu-coding (in `~/.omp/agent/models.yml`)
- Skills: coderlm, line-repetition-control (in `~/.omp/agent/skills/`)
- Memory: local backend with persistent memories
- Compaction: enabled
- Task system: eager subagents, max concurrency 2
- Edit mode: hashline (hash-anchored edits, not diff-based)
- LSP: diagnostics on edit enabled
- Python tool: IPython kernel with rich helpers
- TTSR rules: time-traveling streamed rules (zero context cost until triggered)
- Browser tool: Puppeteer-based

**How rules load**: Reads `AGENTS.md` and `.omp/rules/*.md` per project. User-level config in `~/.omp/agent/config.yml`.

**Update**: `omp update` (bun-installed, self-updater).

**SSoT integration**: Directory format — `make sync` creates symlinks in `~/.omp/agent/rules/`.

### gemini-cli

**Config**: `~/.gemini/settings.json` (minimal — auth only)

- Auth: OAuth personal
- MCP servers: configured via `gemini mcp` CLI
- Extensions: installed via `gemini extensions install` (stored in `~/.gemini/extensions/`)
  - Currently installed: brooks-lint
- Hooks: `~/.gemini/hooks/` for custom CLI behavior
- Skills: `~/.gemini/skills/` for specialized workflows

**How rules load**: `~/.gemini/GEMINI.md` is loaded at session start. Extensions can contribute additional context via `contextFileName` in `gemini-extension.json`.

**Extension system**: Each extension is a directory under `~/.gemini/extensions/` with a `gemini-extension.json` manifest. Extensions can provide MCP servers, custom commands (`commands/*.toml`), hooks (`hooks/hooks.json`), agent skills (`skills/`), sub-agents (`agents/`), themes, and policy rules (`policies/*.toml`). Install from GitHub URL or local path: `gemini extensions install <source>`.

**SSoT integration**: Import format — `make sync` writes `@/abs/path/to/ssot/rules/*.md` import lines into `GEMINI.md`, preserving the header from schema.

### qwen-code

**Config**: `~/.qwen/settings.json`

- Auth: Qwen OAuth
- MCP servers: context7 (`npx -y @upstash/context7-mcp`)
- Skills: ast-grep
- Extensions: superpowers (in `~/.qwen/extensions/`)
- Permissions: fine-grained allow/ask/deny per tool pattern
  - Allowed: `gh *`, `git *`, `ast-grep *`, `npm run *`, `cargo *`, `Read`
  - Ask: `sudo *`, `rm *`, `Edit`, `WebFetch`
  - Denied: `rm -rf *`, `.env*`, `secrets/**`
- Features: auto-update, git co-author, chat compression at 70% threshold

**How rules load**: `~/.qwen/QWEN.md` is loaded at session start. Has a built-in multi-language query pipeline (translate to English, generate 2–5 queries, search both languages in parallel). Supports project-level `QWEN.md` overrides.

**Subagent system**: Supports general-purpose, Explore, and code-reviewer subagents. Rule: never chain sequentially (failure compounds). Prefer inline execution for sequential work.

**SSoT integration**: Import format — `make sync` writes `@/abs/path/to/ssot/rules/*.md` import lines into `QWEN.md`, preserving header from schema.

### goose

**Config**: `~/.config/goose/config.yaml`

- Provider: custom z.ai coding plan (Anthropic-compatible API at `api.z.ai`)
- Model: glm-5.1 (128K context)
- Extensions: code_execution (disabled), skills, summon, extension manager, chatrecall (disabled), tom (Top Of Mind), summarize (disabled), developer, apps, todo, orchestrator (disabled), analyze, zread
- Permissions: smart_approve mode — asks before edit, shell, write

**How rules load**: Unlike other agents, goose uses **persistent instructions** via MOIM (Model-Observed Internal Memory). The `GOOSE_MOIM_MESSAGE_FILE` env var in `config.yaml` points to `~/.config/goose/guardrails.md`, which is re-read and injected **every turn**. This means rules cannot be "forgotten" as the conversation grows — critical for memory isolation rules.

**Key difference**: goose's persistent instructions are per-turn, not per-session. This is more reliable for guardrails but costs more tokens. The 64 KB size limit means rules must be concise.

**Custom provider**: `~/.config/goose/custom_providers/custom_z.ai_coding_plan.json` — Anthropic-compatible engine with glm-5.1 and glm-4.7 models.

**SSoT integration**: Skill format — `make sync` copies `ssot/skills/vendor/goose.md` → `~/.config/goose/guardrails.md`.

### droid

**Config**: No persistent config file found. Uses `--settings` flag for runtime config.

- Factory's AI coding agent (formerly "Factory Droid")
- Reads `AGENTS.md` files in standard hierarchy: `./AGENTS.md` → parent dirs → `~/.factory/AGENTS.md`
- Supports `--append-system-prompt` and `--append-system-prompt-file` for custom instructions
- Can create custom droids (subagents) via configuration

**How rules load**: Standard AGENTS.md discovery hierarchy. User-level override at `~/.factory/AGENTS.md` applies to all projects unless overridden by a closer AGENTS.md.

**SSoT integration**: Skill format — `make sync` copies `ssot/skills/vendor/droid.md` → `~/.factory/AGENTS.md`.

### cicada

**Config**: No global config. Project-level only.

- Codebase search and exploration tool (NOT a coding agent)
- Installed via pip/uv: `~/.local/bin/cicada` → `~/.local/share/uv/tools/cicada-mcp/bin/cicada`
- Python package (`cicada-mcp`), runs as MCP server
- Project config: `~/.cicada/projects/<id>/`
- **No global user-level rules file** — this is a known limitation
- Cannot inject workstation-level memory rules globally

### jan

**Config**: N/A — local model runner, not a coding agent.

- Runs local AI models (LlamaCPP / MLX)
- Exposes OpenAI-compatible API
- Used to host models locally for privacy
- Models managed in Jan desktop app
- Other agents (Claude Code, etc.) can connect to Jan's API

## Rules & Memory Isolation

All coding agents are configured with workstation memory rules. See [docs/agent-rules.md](docs/agent-rules.md) for the configuration summary and [docs/oomd-terminal-isolation.md](docs/oomd-terminal-isolation.md) for the technical rationale.

**Core rule**: Any command that may consume >1 GB RAM MUST be wrapped in:

```bash
systemd-run --user --scope -p MemoryMax=<limit> <command>
```

| Task | Limit |
|------|-------|
| Node.js test runners (vitest, jest) | 3G |
| cargo build | 2G |
| npm/pnpm install | 3G |
| bun | 2G |

## MCP Server Usage

Multiple agents share the same MCP servers:

| Server | Used By | Purpose |
|--------|---------|---------|
| context7 | opencode, qwen, goose | Version-accurate library docs |
| zread | opencode, goose | Open source repo Q&A |
| web-search-prime | opencode | Web search |
| web-reader | opencode | URL content extraction |
| zai-mcp-server | opencode, crush | Z.AI coding tools |

## Known Quirks

- **gemini-cli extensions**: `gemini extensions install` requires folder trust confirmation (interactive). Use `--consent` to skip.
- **qwen-code**: Has a built-in English translation pipeline — all non-English input is translated before acting. Searches both English and original language in parallel.
- **goose MOIM**: 64 KB content limit on persistent instructions. Keep rules concise.
- **cicada**: No global config. Must manually wrap heavy commands.
- **opencode upgrade**: Supports multiple methods (`curl`, `npm`, `pnpm`, `bun`, `brew`). Use `opencode upgrade` without args for latest.
- **crush**: Installed via apt (not npm). Config at `~/.config/crush/crush.json`. Supports mid-session model switching.
- **oh-my-pi**: Hash-anchored edits (not diff-based). TTSR rules cost zero context until triggered. Built-in IPython kernel.
- **droid**: Binary is `droid`, not `factory-droid`. Uses `--append-system-prompt-file` for custom rules injection.

## Risk

`stable`. These are configuration files, not system changes. Rules can be removed by deleting the respective config files.

## Revert

```bash
# Remove all agent rule files (preserves configs)
rm ~/.gemini/GEMINI.md
# Revert qwen QWEN.md changes manually (remove Workstation Constraints section)
rm ~/.config/goose/guardrails.md
# Remove GOOSE_MOIM_MESSAGE_FILE from ~/.config/goose/config.yaml
rm ~/.factory/AGENTS.md
rm ~/.config/agents/workstation-memory.md
```

**Do NOT remove** `~/.config/opencode/AGENTS.md` — it contains extensive project guidelines beyond memory rules.

## See Also

- [docs/agent-rules.md](docs/agent-rules.md) — SSoT v2 rules overview and workflow
- [docs/agents/ssot-architecture.md](docs/agents/ssot-architecture.md) — Full SSoT architecture
- [docs/upstream-sources.md](docs/upstream-sources.md) — Upstream source tracking
