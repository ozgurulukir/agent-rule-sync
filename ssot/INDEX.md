# SSoT Index

**Generated:** 2026-05-14T06:22:33Z
**Schema version:** 2.0

## Sources

| ID | Platform | Type | Path | Default Transformer |
|----|----------|------|------|---------------------|
| `local` | generic | local | `` | copy |
| `vibe-security` | generic | url | `` | copy |

## Platforms

| ID | Format | Rules Dir | Skills Dir | Docs Dir | Transforms From | Custom Transform |
|----|--------|-----------|------------|----------|-----------------|------------------|
| `opencode` | directory | `rules/` | `skills/` | `docs/` | ["opencode", "generic"] | {} |

## Rules (3)

| Order | ID | Title | Source | Upstream | Transformer |
|-------|----|-------|--------|----------|-------------|
| 0 | `memory` | Workstation Memory Constraints |  | `` | — |
| 1 | `shell` | Non-Interactive Shell Strategy |  | `` | — |
| 2 | `vibe-security` | Vibe Security Skill | vibe-security | `vibe-security/SKILL.md` | copy |

## Docs (0)

| ID | Filename | Source | Upstream | Transformer |
|----|----------|--------|----------|-------------|

## Skills

### Common (0)


### Agent-Specific


### Upstream (0)

| ID | Source | Upstream | Transformer |
|----|--------|----------|-------------|

## Agents (1)

| Name | Display | Platform | Format | Path | Rules | Skills | Docs |
|------|---------|----------|--------|------|-------|--------|------|
| `opencode` | OpenCode | opencode | directory | `~/.config/opencode/rules/` | all |  |  |

## Transform Log

**Last transform:** 2026-05-14T06:22:33Z

- Transformed: 1
- Skipped: 0
- Errors: 0

---
*This index is auto-generated from `ssot/schema.yaml`. Do not edit manually.*
