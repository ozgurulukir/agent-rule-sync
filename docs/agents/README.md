# Agent Rule Sync — Documentation

This is the PKGBUILD-based Single Source of Truth (SSoT) system for managing AI agent rules, skills, and documentation across multiple platforms.

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
| Oh My Pi | directory | user | `~/.config/oh-my-pi/rules/` | [Oh My Pi](agents/oh-my-pi.md) |
| Crush | skill | user | `/usr/local/share/crush/crush.md` | [Crush](agents/crush.md) |
| Goose | skill | user | `~/.local/share/goose/goose.md` | [Goose](agents/goose.md) |
| Droid | skill | user | `~/.config/droid/droid.md` | [Droid](agents/droid.md) |
| Gemini CLI | import | user | `~/.config/gemini/GEMINI.md` | [Gemini CLI](agents/gemini-cli.md) |
| Qwen Code | import | user | `~/.config/qwen/QWEN.md` | [Qwen Code](agents/qwen-code.md) |
| Cursor | directory | project | `.cursor/rules/` | [Cursor](agents/cursor.md) |
| Windsurf | directory | project | `.windsurf/rules/` | [Windsurf](agents/windsurf.md) |
| GitHub Copilot | import | project | `.github/copilot-instructions.md` | [GitHub Copilot](agents/github-copilot.md) |
| Claude Code | directory | project | `.claude/rules/` | [Claude Code](agents/claude-code.md) |
| Codex CLI | skill | project | `AGENTS.md` | [Codex CLI](agents/codex.md) |

## Overview

This repository maintains a **single source of truth** for agent behavior definitions. Each rule or skill is a self-contained package with a PKGBUILD descriptor. The system:

- **Builds** packages from source (local files or upstream URLs)
- **Transforms** content per-platform via transformers (copy, strip-frontmatter, custom)
- **Aggregates** skill-based agents' vendor files from rule fragments
- **Installs** to multiple agent platforms (user-level and project-level)
- **Tracks** installed state via `ssot/index.yaml` + `ssot/index.json`

**Core scripts**: `build.rb` → `aggregate-skills.rb` → `install.rb` / `uninstall.rb` / `query.rb`

See [Architecture](ARCHITECTURE.md) for the full design.
