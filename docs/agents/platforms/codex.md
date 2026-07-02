# Codex CLI

- **Type**: skill
- **Scope**: project
- **Base path**: project root (`.`)
- **Skill file**: `AGENTS.md`
- **Install method**: copy (vendor skill aggregation)
- **Provider**: OpenAI (Codex models)
- **Rules loading**: Searches up directory tree for `AGENTS.md`; supports `AGENTS.override.md` and `project_doc_fallback_filenames` config; truncates at 32 KiB by default
- **Features**: Terminal agent, project-aware, supports subagents (general, Explore, code-reviewer)

## Update

```bash
codex update  # npm
```

## Rulepack Integration

```bash
cd /path/to/project
bin/rulepack install --target codex --project .
# Generates vendor skill (build/codex/skills/vendor/codex.md) and copies to AGENTS.md
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the project:

```bash
# Install a single package
bin/rulepack install <pkg> -t codex --project .

# Uninstall a single package
bin/rulepack uninstall <pkg> -t codex --project .
```


### Appending without overwriting

To append rules to `AGENTS.md` without replacing existing content, use `--rules-to rules_file`:

```bash
bin/rulepack install <pkg> -t codex --rules-to rules_file --project .
```

Rulepack wraps each package in marker-boundary blocks (`<!-- rulepack:<pkg> start -->` / `<!-- rulepack:<pkg> end -->`), so your existing content is preserved.

## Notes

Codex CLI uses the same `AGENTS.md` format as OpenCode but as a single concatenated skill file rather than individual rule files. The Rulepack system aggregates all rule fragments and skills into one file for Codex.

## See Also

- [Platforms](PLATFORMS.md#codex-cli)
- [Usage](USAGE.md)
