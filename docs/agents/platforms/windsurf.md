# Windsurf

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Rules dir**: `.windsurf/rules/`
- **Root rules file**: `.windsurfrules` (optional)
- **Install method**: symlink
- **Provider**: Codeium
- **Config**: Project-level rules (version-controlled)
- **Features**: Codeium's agentic IDE (Cascade), GUI rule editor, always-active and context-specific rules, `.mdc` frontmatter support with `description`, `globs`, `alwaysApply` fields
- **Rules loading**: Reads `.windsurf/rules/*.md` and root `.windsurfrules`

## Update

Built-in updater (Windsurf IDE menu)

## Rulepack Integration

```bash
cd /path/to/project
bin/rulepack install --target windsurf --project .
# Creates symlinks: .windsurf/rules/*.md → build/windsurf/
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the project:

```bash
# Install a single package
bin/rulepack install <pkg> -t windsurf --project .

# Uninstall a single package
bin/rulepack uninstall <pkg> -t windsurf --project .
```

## Notes

Windsurf rules can include frontmatter for fine-grained control. Use `alwaysApply: true` for workstation rules that should always be active.

## See Also

- [Platforms](PLATFORMS.md#windsurf)
- [Usage](USAGE.md)
