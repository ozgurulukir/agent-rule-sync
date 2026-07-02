# GitHub Copilot

- **Type**: import
- **Scope**: project
- **Base path**: `.github/`
- **Config file**: `copilot-instructions.md`
- **Install method**: copy (separate instruction file)
- **Provider**: GitHub (Microsoft)
- **Features**: VS Code extension, also available on GitHub web and CLI; supports additional instruction files in `.github/instructions/*.md`; custom instructions for repository
- **Update**: VS Code extension updates

## Rulepack Integration

```bash
cd /path/to/project
bin/rulepack install --target github-copilot --project .
# Copies instruction files to .github/
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the project:

```bash
# Install a single package
bin/rulepack install <pkg> -t github-copilot --project .

# Uninstall a single package
bin/rulepack uninstall <pkg> -t github-copilot --project .
```

## Notes

GitHub Copilot reads the entire `copilot-instructions.md` file as custom instructions. Files in `.github/instructions/` are automatically loaded as additional context. The Rulepack system writes platform-specific instruction files (e.g., `memory-instructions.md`) which can be referenced from the main file.

## See Also

- [Platforms](PLATFORMS.md#github-copilot)
- [Usage](USAGE.md)
