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

## Rulepack Integration

```bash
cd /path/to/project
bin/rulepack install claude-code --project .
# Creates symlinks: .claude/rules/*.md → build/claude-code/
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the project:

```bash
# Install a single package
bin/rulepack install <pkg> -t claude-code --project .

# Uninstall a single package
bin/rulepack uninstall <pkg> -t claude-code --project .
```

## Notes

Claude Code does not have a global config file; it uses per-project `CLAUDE.md`. The Rulepack system installs individual rule files into `.claude/rules/` for modular organization.

## See Also

- [Platforms](PLATFORMS.md#claude-code)
- [Usage](USAGE.md)
