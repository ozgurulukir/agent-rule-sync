# Gemini CLI

- **Type**: import
- **Scope**: user
- **Base path**: `~/.config/gemini/`
- **Config file**: `cli_config.yaml`
- **Rules file**: `~/.config/gemini/cli_config.yaml`
- **Install method**: inject `@import` lines into `cli_config.yaml`
- **Provider**: Google (Gemini)
- **Auth**: OAuth personal
- **MCP**: Configured via `gemini mcp` CLI
- **Extensions**: Installed via `gemini extensions install` (stored in `~/.gemini/extensions/`); currently installed: brooks-lint
- **Hooks**: `~/.gemini/hooks/` for custom CLI behavior
- **Skills**: `~/.gemini/skills/`
- **Rules loading**: `~/.config/gemini/cli_config.yaml` loaded at session start; extensions can contribute additional context via `contextFileName` in `gemini-extension.json`

## Update

```bash
gemini extensions update --all  # extensions only; CLI updates via npm
```

## Rulepack Integration

```bash
bin/rulepack install gemini-cli
# Injects @import lines into ~/.config/gemini/cli_config.yaml
```

## Notes

Gemini CLI uses `@import` syntax to include external rule files. The Rulepack system injects import lines pointing to built artifacts in `build/gemini-cli/`. Extension system is powerful; extensions can provide MCP servers, custom commands, hooks, skills, and agents.

## See Also

- [Platforms](PLATFORMS.md#gemini-cli)
- [Usage](USAGE.md)
