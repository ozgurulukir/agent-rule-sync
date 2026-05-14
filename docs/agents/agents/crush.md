# Crush

- **Type**: skill
- **Scope**: user
- **Base path**: `/usr/local/share/crush/`
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

## SSoT Integration

```bash
ruby ssot/install.rb crush
# Copies build/crush/skills/vendor/crush.md → /usr/local/share/crush/crush.md
```

## Notes

Crush is a Go-based coding agent from Charmbracelet (23k+ GitHub stars). Installed via apt from Charm's Debian repository. Skill file contains all rules concatenated.

## See Also

- [Platforms](PLATFORMS.md#crush)
- [Usage](USAGE.md)
