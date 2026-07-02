# Crush

- **Type**: skill
- **Scope**: user
- **Base path**: `~/.config/crush/`
- **Skill file**: `crush.md`
- **Install method**: copy (vendor skill file)
- **Provider**: ZAI (OpenAI-compatible API at `api.z.ai`)
- **MCP servers**: zai-mcp-server (stdio), web-search-prime (http), web-reader (http)
- **Features**: Session-based (multiple work sessions per project), LSP-enhanced, mid-session model switching while preserving context
- **Skills**: `.agents/skills/` (builtin-skills, shell-builtins)
- **Rules loading**: Reads `AGENTS.md` in standard hierarchy (project → parents → user)

## Update

```bash
sudo apt update && sudo apt install crush  # Debian repo from repo.charm.sh
```

## Rulepack Integration

```bash
bin/rulepack install --target crush
# Copies build/crush/skills/vendor/crush.md → ~/.config/crush/crush.md
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install <pkg> -t crush

# Uninstall a single package
bin/rulepack uninstall <pkg> -t crush
```


## Notes

Crush is a Go-based coding agent from Charmbracelet (23k+ GitHub stars). Installed via apt from Charm's Debian repository. Skill file contains all rules concatenated.

## See Also

- [Platforms](PLATFORMS.md#crush)
- [Usage](USAGE.md)
