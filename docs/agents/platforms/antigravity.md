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


### Appending without overwriting

By default, rules are appended to `GEMINI.md` using marker-boundary blocks:

```bash
bin/rulepack install <pkg> -t antigravity
```

Rulepack wraps each package in `<!-- rulepack:<pkg> start -->` / `<!-- rulepack:<pkg> end -->` markers, so existing content is preserved and re-install/uninstall only affect that package's block.

## Notes

Antigravity is a user-scoped agent (Google). Rules are appended to the shared `~/.gemini/GEMINI.md` file using marker-aware boundaries, merged with any existing content.

## See Also

- [Antigravity Platform Profile](../../platforms/antigravity.yaml)
- [Platforms Registry](../../PLATFORMS.md)
