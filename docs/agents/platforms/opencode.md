# OpenCode

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.config/opencode/`
- **Rules dir**: `rules/`
- **Skills dir**: `skills/`
- **Install method**: symlink for rules, copy for skills
- **Config**: `~/.config/opencode/opencode.jsonc`
- **Provider**: StepFun (step_plan)
- **MCP servers**: zai-mcp-server, web-search-prime, web-reader, zread, context7
- **Skills**: ast-grep, line-repetition-control
- **Modes**: `plan` (temp 0.5), `build` (temp 1.1)
- **Compaction**: auto + prune, 10000 tokens reserved
- **Rules loading**: `AGENTS.md` global context + all `rules/*.md` symlinks injected at session start

## Update

```bash
opencode upgrade  # self-updater (supports curl, npm, pnpm, bun, brew)
```

## Rulepack Integration

```bash
bin/rulepack install opencode   # → ~/.config/opencode/rules/*.md (symlinks)
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install <pkg> -t opencode

# Uninstall a single package
bin/rulepack uninstall <pkg> -t opencode
```


### Appending without overwriting

To append rules to `AGENTS.md` without replacing existing content, use `--rules-to rules_file`:

```bash
bin/rulepack install <pkg> -t opencode --rules-to rules_file
```

Rulepack wraps each package in marker-boundary blocks (`<!-- rulepack:<pkg> start -->` / `<!-- rulepack:<pkg> end -->`), so your existing content is preserved.

## Notes

OpenCode is the primary coding agent on this workstation. It uses directory format with per-section rule files. Memory isolation rules and shell strategy are critical for stability.

## See Also

- [Platforms](PLATFORMS.md#opencode)
- [Usage](USAGE.md)
