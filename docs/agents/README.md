# Agent Rule Sync — Documentation

This is the PKGBUILD-based system for managing AI agent rules, skills, and documentation across multiple platforms.

## Quick Links

- **[Architecture](ARCHITECTURE.md)** — System design, pipeline, data flow
- **[Platforms](PLATFORMS.md)** — All supported agents and their configuration
- **[Usage](USAGE.md)** — Commands, workflows, installation guide
- **[Reference](REFERENCE.md)** — PKGBUILD format, transformer API, index schema
- **[Transforms](TRANSFORMS.md)** — Transformer system (built-in + custom)
- **[Upstream](UPSTREAM.md)** — Upstream source tracking

## Agent-Specific Guides

| Agent | Type | Scope | Config | Guide |
|-------|------|-------|--------|-------|
| OpenCode | directory | user | `~/.config/opencode/rules/` | [OpenCode](agents/opencode.md) |
| Oh My Pi | directory | user | `~/.omp/agent/rules/` | [Oh My Pi](agents/oh-my-pi.md) |
| Crush | skill | user | `~/.config/crush/crush.md` | [Crush](agents/crush.md) |
| Goose | skill | user | `~/.local/share/goose/goose.md` | [Goose](agents/goose.md) |
| Droid | skill | user | `~/.factory/AGENTS.md` | [Droid](agents/droid.md) |
| Gemini CLI | import | user | `~/.config/gemini/cli_config.yaml` | [Gemini CLI](agents/gemini-cli.md) |
| Qwen Code | import | user | `~/.config/qwen/config.yaml` | [Qwen Code](agents/qwen-code.md) |
| Cursor | directory | project | `.cursor/rules/` | [Cursor](agents/cursor.md) |
| Windsurf | directory | project | `.windsurf/rules/` | [Windsurf](agents/windsurf.md) |
| GitHub Copilot | import | project | `.github/copilot-instructions.md` | [GitHub Copilot](agents/github-copilot.md) |
| Claude Code | directory | project | `.claude/rules/` | [Claude Code](agents/claude-code.md) |
| Codex CLI | skill | project | `AGENTS.md` | [Codex CLI](agents/codex.md) |
| Antigravity | directory | user | `~/.gemini/antigravity/.agent/skills/` | [Antigravity](agents/antigravity.md) |
| Agents | directory | user | `~/.agents/rules/` | [Agents](agents/agents.md) |

## Overview

This repository maintains a **single source of truth** for agent behavior definitions. Each rule or skill is a self-contained package with a PKGBUILD descriptor. The system:

- **Builds** packages from source (local files or upstream URLs)
- **Transforms** content per-platform via transformers (copy, strip-frontmatter, custom)
- **Aggregates** skill-based agents' vendor files from rule fragments
- **Installs** to multiple agent platforms (user-level and project-level)
- **Tracks** installed state via `data/index.yaml`

**Additional features**:
- **Agent packages** (`pkg_type: agent`) with platform-specific format translators
- **`--rules-to`** flag to redirect rule installation to a single file (e.g., `AGENTS.md`)
- **Pacman-style shortcuts**: `-S` (install), `-R` (uninstall), `-Qk` (verify), `-F` (fix), `-Q` (query)

**Core scripts**: `lib/rulepack/build.rb` → `lib/rulepack/aggregate.rb` → `lib/rulepack/install.rb` / `lib/rulepack/uninstaller.rb` / `lib/rulepack/query.rb`

See [Architecture](ARCHITECTURE.md) for the full design.
