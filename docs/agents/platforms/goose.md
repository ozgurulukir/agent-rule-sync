# Goose

- **Type**: skill
- **Scope**: user
- **Base path**: `~/.local/share/goose/`
- **Skill file**: `goose.md` (actually guardrails)
- **Install method**: copy (vendor skill file)
- **Provider**: custom z.ai coding plan (Anthropic-compatible API at `api.z.ai`)
- **Model**: glm-5.1 (128K context)
- **Extensions**: code_execution, skills, summon, extension manager, chatrecall (disabled), tom (Top Of Mind), summarize (disabled), developer, apps, todo, orchestrator (disabled), analyze, zread
- **Permissions**: smart_approve mode — asks before edit, shell, write
- **Persistent instructions**: `GOOSE_MOIM_MESSAGE_FILE` env var points to `~/.config/goose/guardrails.md`, which is re-read and injected **every turn** (cannot be forgotten as conversation grows). 64 KB size limit → keep rules concise.
- **MCP**: context7, zread

## Update

```bash
goose update  # if available (npm)
```

## Rulepack Integration

```bash
bin/rulepack install --target goose
# Copies build/goose/skills/vendor/goose.md → ~/.local/share/goose/goose.md
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install <pkg> -t goose

# Uninstall a single package
bin/rulepack uninstall <pkg> -t goose
```


## Notes

Goose's persistent instructions are per-turn, not per-session. This is more reliable for guardrails but costs more tokens. The 64 KB limit means rules must be concise. The Rulepack vendor skill should be referenced from guardrails file.

## See Also

- [Platforms](PLATFORMS.md#goose)
- [Usage](USAGE.md)
