# Antigravity

- **Type**: directory
- **Scope**: project
- **Base path**: project root (`.`)
- **Skills directory**: `.agent/skills/`
- **Rules directory**: none (skills only)
- **Install method**: copy (skill-bundle)
- **Provider**: Google
- **Features**: Project-scoped skills directory, supports skill-bundle packages with sub-skill selection

## SSoT Integration

```bash
cd /path/to/project
ruby ssot/install.rb antigravity --project .
# Copies skill-bundle packages to .agent/skills/<pkgname>/
```

## Sub-skill Selection

Antigravity primarily receives skills via the `antigravity-skills` package (306 sub-skills). Use `--select` to install specific skills:

```bash
# Install specific sub-skills
ruby ssot/install.rb antigravity --project . --select agent-orchestration-improve-agent,workflow-patterns

# Interactive menu (TTY only)
ruby ssot/install.rb antigravity --project .
```

## Notes

Antigravity is a project-scoped agent that reads skills from `.agent/skills/*/`. It does not have a separate rules directory — all behavior definitions come through skill files. The SSoT system deploys skill-bundles directly to this directory.

## See Also

- [Antigravity Platform Profile](../../platforms/antigravity.yaml)
- [Platforms Registry](../../PLATFORMS.md)
