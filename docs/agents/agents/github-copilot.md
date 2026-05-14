# GitHub Copilot

- **Type**: import
- **Scope**: project
- **Base path**: `.github/`
- **Config file**: `copilot-instructions.md`
- **Install method**: copy (separate instruction file)
- **Features**: VS Code extension, also available on GitHub web and CLI; supports additional instruction files in `.github/instructions/*.md`; custom instructions for repository
- **Update**: VS Code extension updates

## SSoT Integration

```bash
cd /path/to/project
ruby ssot/install.rb github-copilot --project .
# Copies instruction files to .github/
```

## Notes

GitHub Copilot reads the entire `copilot-instructions.md` file as custom instructions. Files in `.github/instructions/` are automatically loaded as additional context. The SSoT system writes platform-specific instruction files (e.g., `memory-instructions.md`) which can be referenced from the main file.

## See Also

- [Platforms](PLATFORMS.md#github-copilot)
- [Usage](USAGE.md)
