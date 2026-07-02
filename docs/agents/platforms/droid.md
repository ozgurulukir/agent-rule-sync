# Droid

- **Type**: skill
- **Scope**: user
- **Base path**: `~/.factory/`
- **Skill file**: `droid.md` (actually AGENTS.md)
- **Install method**: copy (vendor skill file)
- **Config**: No persistent config file; uses `--settings` flag at runtime
- **Provider**: Factory's AI coding agent (formerly "Factory Droid")
- **Rules loading**: Reads `AGENTS.md` files in standard hierarchy: `./AGENTS.md` → parent dirs → `~/.factory/AGENTS.md`. User-level override at `~/.factory/AGENTS.md` applies to all projects unless overridden by a closer file.
- **Features**: Can create custom droids (subagents) via configuration; supports `--append-system-prompt` and `--append-system-prompt-file` for custom instructions injection

## Update

```bash
droid update  # if available
```

## Rulepack Integration

```bash
bin/rulepack install droid
# Copies build/droid/skills/vendor/droid.md → ~/.factory/AGENTS.md
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install <pkg> -t droid

# Uninstall a single package
bin/rulepack uninstall <pkg> -t droid
```

## Notes

Droid is the Factory AI coding agent. The binary is `droid` (not `factory-droid`). Uses `--append-system-prompt-file` for custom rules injection, making it compatible with Rulepack-generated AGENTS.md.

## See Also

- [Platforms](PLATFORMS.md#droid)
- [Usage](USAGE.md)
