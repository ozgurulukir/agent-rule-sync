# Oh My Pi (omp)

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.omp/agent/`
- **Rules dir**: `rules/`
- **Install method**: symlink
- **Provider**: can1357 (fork of badlogic/pi-mono)
- **Config**: `~/.omp/agent/config.yml`, models in `~/.omp/agent/models.yml`
- **Providers**: stepfun-plan, zhipu, zhipu-coding
- **Skills**: coderlm, line-repetition-control
- **Memory**: local backend with persistent memories
- **Compaction**: enabled
- **Task system**: eager subagents, max concurrency 2
- **Edit mode**: hashline (hash-anchored edits, not diff-based)
- **LSP**: diagnostics on edit enabled
- **Python tool**: IPython kernel with rich helpers
- **TTSR rules**: time-traveling streamed rules (zero context cost until triggered)
- **Browser tool**: Puppeteer-based
- **Rules loading**: Reads `~/.omp/agent/rules/*.md` (native, priority 100) and `.omp/rules/*.md` (project) via TTSR. Also discovers from `.cursor/`, `.claude/`, `.windsurf/`, `.gemini/`, `.codex/`, `.github/copilot/`.

## Update

```bash
omp update  # bun-installed self-updater
```

## Rulepack Integration

```bash
bin/rulepack install oh-my-pi   # → ~/.omp/agent/rules/*.md (symlinks)
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install <pkg> -t oh-my-pi

# Uninstall a single package
bin/rulepack uninstall <pkg> -t oh-my-pi
```

## Notes

Oh My Pi is a TypeScript/Rust monorepo coding agent. Supports multiple model roles and has built-in IPython integration.

## See Also

- [Platforms](PLATFORMS.md#oh-my-pi)
- [Usage](USAGE.md)
