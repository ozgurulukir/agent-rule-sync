# Antigravity

- **Type**: directory
- **Scope**: user
- **Base path**: `~/.gemini/`
- **Rules file**: `GEMINI.md`
- **Install method**: append (marker-aware replace)
- **Provider**: Google

## Rulepack Integration

```bash
bin/rulepack install antigravity
# Appends rules to ~/.gemini/GEMINI.md with marker boundaries
```


### Surgical install / uninstall

Install or remove individual packages without touching the rest of the platform:

```bash
# Install a single package
bin/rulepack install <pkg> -t antigravity

# Uninstall a single package
bin/rulepack uninstall <pkg> -t antigravity
```

## Notes

Antigravity is a user-scoped agent (Google). Rules are appended to the shared `~/.gemini/GEMINI.md` file using marker-aware boundaries, merged with any existing content.

## See Also

- [Antigravity Platform Profile](../../platforms/antigravity.yaml)
- [Platforms Registry](../../PLATFORMS.md)
