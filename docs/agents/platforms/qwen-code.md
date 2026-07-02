# Qwen Code

- **Type**: import
- **Scope**: user
- **Base path**: `~/.config/qwen/`
- **Config file**: `config.yaml`
- **Rules file**: `~/.config/qwen/config.yaml`
- **Install method**: inject `@import` lines into `config.yaml`
- **Provider**: Alibaba Cloud (Qwen)
- **Auth**: Qwen OAuth
- **MCP**: context7 (`npx -y @upstash/context7-mcp`)
- **Skills**: ast-grep
- **Extensions**: superpowers (in `~/.qwen/extensions/`)
- **Permissions**: fine-grained allow/ask/deny per tool pattern:
-   Allowed: `gh *`, `git *`, `ast-grep *`, `npm run *`, `cargo *`, `Read`
-   Ask: `sudo *`, `rm *`, `Edit`, `WebFetch`
-   Denied: `rm -rf *`, `.env*`, `secrets/**`
- **Features**: auto-update, git co-author, chat compression at 70% threshold, built-in multi-language query pipeline (translate to English, generate 2–5 queries, search both languages in parallel)
- **Subagent system**: Supports general-purpose, Explore, and code-reviewer subagents. Rule: never chain sequentially (failure compounds). Prefer inline execution for sequential work.

## Update

```bash
qwen auth   # re-auth if needed
# CLI updates via npm globally
```

## Rulepack Integration

```bash
bin/rulepack install qwen-code
# Injects @import lines into ~/.config/qwen/config.yaml
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install <pkg> -t qwen-code

# Uninstall a single package
bin/rulepack uninstall <pkg> -t qwen-code
```


## Notes

Qwen Code has sophisticated query pipeline that automatically translates non-English input and searches in both languages. The permission system is granular; ensure Rulepack rules don't trigger "ask" for common operations.

## See Also

- [Platforms](PLATFORMS.md#qwen-code)
- [Usage](USAGE.md)
