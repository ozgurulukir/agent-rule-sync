# Claude Code

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Rules dir**: `.claude/rules/`
- **Config file**: `CLAUDE.md` (project root)
- **Install method**: symlink
- **Provider**: Anthropic Claude 4 (Sonnet 4, Opus 4)
- **Features**: Terminal-based agent, deep reasoning, long context, safe/interpretable code changes
- **Rules loading**: Loads `CLAUDE.md` from current or parent directory; also reads `.claude/rules/` subdirectory for modular rules

## Update

```bash
claude update  # if installed via npm
```

## SSoT Integration

```bash
cd /path/to/project
ruby ssot/install.rb claude-code --project .
# Creates symlinks: .claude/rules/*.md → ssot/build/claude-code/
```

## Notes

Claude Code does not have a global config file; it uses per-project `CLAUDE.md`. The SSoT system installs individual rule files into `.claude/rules/` for modular organization.

## See Also

- [Platforms](PLATFORMS.md#claude-code)
- [Usage](USAGE.md)
