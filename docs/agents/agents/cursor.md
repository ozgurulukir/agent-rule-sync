# Cursor

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Rules dir**: `.cursor/rules/`
- **Skills dir**: `.cursor/skills/`
- **Install method**: symlink
- **Config**: Project-level rules (version-controlled), global MCP at `~/.cursor/mcp.json`
- **Features**: AI-first IDE (VS Code fork), supports multiple LLM backends (GPT-4, Claude, Unders), inline commands (`//fix`, `//explain`), `.mdc` frontmatter support
- **MCP**: Project-level `.cursor/mcp.json`, global `~/.cursor/mcp.json`
- **Team rules**: Dashboard-managed
- **Rules loading**: All `.cursor/rules/*.md` files loaded as context; can use `.mdc` frontmatter for globs and alwaysApply

## Update

Built-in updater: Menu → Help → Check for Updates

## SSoT Integration

```bash
cd /path/to/project
ruby ssot/install.rb cursor --project .
# Creates symlinks: .cursor/rules/workstation-*.md → ssot/build/cursor/
```

## Notes

Cursor stores global rules in cloud/DB; project rules are version-controlled in repo. Use project-level rules for SSoT sync. Supports both markdown (`.md`) and mdc (`.mdc`) formats with frontmatter.

## See Also

- [Platforms](PLATFORMS.md#cursor)
- [Usage](USAGE.md)
