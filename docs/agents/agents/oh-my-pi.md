# Oh My Pi (omp)

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.config/oh-my-pi/`
- **Rules dir**: `rules/`
- **Install method**: symlink
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
- **Rules loading**: Reads `AGENTS.md` and `.omp/rules/*.md` per project

## Update

```bash
omp update  # bun-installed self-updater
```

## SSoT Integration

```bash
ruby ssot/install.rb oh-my-pi   # → ~/.config/oh-my-pi/rules/*.md (symlinks)
```

## Notes

Oh My Pi is a TypeScript/Rust monorepo coding agent by can1357 (fork of badlogic/pi-mono). Supports multiple model roles and has built-in IPython integration.

## See Also

- [Platforms](PLATFORMS.md#oh-my-pi)
- [Usage](USAGE.md)
