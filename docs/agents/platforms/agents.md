# Agents

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.agents/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Install method**: symlink for rules, copy for skills
- **Provider**: Community-driven agent skills repository

## Rulepack Integration

```bash
bin/rulepack install --target agents
# Symlinks/copies to ~/.agents/rules/ and ~/.agents/skills/
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install <pkg> -t agents

# Uninstall a single package
bin/rulepack uninstall <pkg> -t agents
```

## Notes

The Agents platform is a community-driven collection of rules and skills from various coding agents. It provides a unified interface for accessing shared agent behavior definitions.

## See Also

- [Platforms](PLATFORMS.md#agents)
- [Usage](USAGE.md)
