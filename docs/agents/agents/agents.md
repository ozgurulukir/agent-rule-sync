# Agents

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.config/agents/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Install method**: symlink for rules, copy for skills
- **Provider**: Community-driven agent skills repository

## Rulepack Integration

```bash
bin/rulepack install agents
# Symlinks/copies to ~/.config/agents/rules/ and ~/.config/agents/skills/
```

## Notes

The Agents platform is a community-driven collection of rules and skills from various coding agents. It provides a unified interface for accessing shared agent behavior definitions.

## See Also

- [Platforms](PLATFORMS.md#agents)
- [Usage](USAGE.md)
