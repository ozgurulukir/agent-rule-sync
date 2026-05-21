# Agent Guides

Detailed reference for each supported agent platform.

## User-Level Agents

| Agent | Type | Config | Guide |
|-------|------|--------|-------|
| [OpenCode](opencode.md) | directory | `~/.config/opencode/rules/` | Primary coding agent |
| [Oh My Pi](oh-my-pi.md) | directory | `~/.config/oh-my-pi/rules/` | TypeScript/Rust monorepo agent |
| [Crush](crush.md) | skill | `/usr/local/share/crush/crush.md` | Go-based, LSP-enhanced |
| [Goose](goose.md) | skill | `~/.local/share/goose/goose.md` | Anthropic-compatible, per-turn guardrails |
| [Droid](droid.md) | skill | `~/.factory/AGENTS.md` | Factory AI coding agent |
| [Gemini CLI](gemini-cli.md) | import | `~/.config/gemini/GEMINI.md` | Google's Gemini CLI with MCP |
| [Qwen Code](qwen-code.md) | import | `~/.config/qwen/QWEN.md` | Qwen coding agent with permissions |

## Project-Level Agents

| Agent | Type | Config | Guide |
|-------|------|--------|-------|
| [Cursor](cursor.md) | directory | `.cursor/rules/` | AI-first IDE (VS Code fork) |
| [Windsurf](windsurf.md) | directory | `.windsurf/rules/` | Codeium's agentic IDE |
| [GitHub Copilot](github-copilot.md) | import | `.github/copilot-instructions.md` | VS Code extension |
| [Claude Code](claude-code.md) | directory | `.claude/rules/` | Anthropic's terminal agent |
| [Codex CLI](codex.md) | skill | `AGENTS.md` | OpenAI's Codex CLI |

## Common Topics

- **[Architecture](ARCHITECTURE.md)** — System design and pipeline
- **[Platforms](PLATFORMS.md)** — Platform registry and configuration
- **[Usage](USAGE.md)** — Installation and workflows
- **[Reference](REFERENCE.md)** — PKGBUILD format, index schema
- **[Transforms](TRANSFORMS.md)** — Transformer system
- **[Upstream](UPSTREAM.md)** — Source tracking
