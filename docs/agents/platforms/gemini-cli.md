# Gemini CLI

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.gemini/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Rules file**: `GEMINI.md`
- **Install method**: append for rules (marker-boundary blocks), copy for skills
- **Provider**: Google (Gemini)
- **Auth**: OAuth personal
- **MCP**: Configured via `gemini mcp` CLI
- **Extensions**: Installed via `gemini extensions install` (stored in `~/.gemini/extensions/`)
- **Hooks**: `~/.gemini/hooks/` for custom CLI behavior
- **Skills**: `~/.gemini/skills/`
- **Rules loading**: `~/.gemini/GEMINI.md` loaded at session start; rules appended via marker-boundary blocks (`<!-- rulepack:<pkg> start -->` / `<!-- rulepack:<pkg> end -->`)

## Update

```bash
gemini extensions update --all  # extensions only; CLI updates via npm
```

## Rulepack Integration

```bash
bin/rulepack install gemini-cli
# Appends rules to ~/.gemini/GEMINI.md using marker-boundary blocks
# Copies skills to ~/.gemini/sills/
```

## Notes

Gemini CLI uses a directory-based rule structure under `~/.gemini/`. Rules are appended to `GEMINI.md` using marker-boundary blocks for idempotent re-installation. Skills are copied to `skills/`. Extension system is powerful; extensions can provide MCP servers, custom commands, hooks, skills, and agents.

## See Also

- [Platforms](PLATFORMS.md#gemini-cli)
- [Usage](USAGE.md)
