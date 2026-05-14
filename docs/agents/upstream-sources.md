# Upstream Sources

## Rule Sources

| Rule | Source | Type | Path | Transformer |
|------|--------|------|------|-------------|
| memory | Original workstation | local | — | copy |
| shell | Original workstation | local | — | copy |
| code-nav | Original workstation | local | — | copy |
| patterns | Original workstation | local | — | copy |
| git | Original workstation | local | — | copy |
| security | Original workstation | local | — | copy |
| tci | Tandem Code Intelligence | local-path | `~/Projects/coderlm/agents/opencode` | strip-frontmatter |
| vibe-security | raroque/vibe-security-skill | url | `vibe-security/SKILL.md` | copy |

Upstream sources declared in `ssot/schema.yaml` under `sources:`. `fetch-upstream.rb` downloads to `ssot/vendor/` (local-path copies, URL fetches). `transform.rb` then transforms upstream → SSoT (`ssot/rules/`, `ssot/docs/`, `ssot/skills/`) using platform-aware transformers.

## Skill Sources

Custom skills authored in `ssot/skills/` and versioned. Vendor skills auto-generated (do not edit).

Upstream skills (from TCI):
- `tci-analyze`, `tci-architecture`, `tci-BFG`, `tci-cognitive-load`, `tci-coupling`, `tci-dependency`, `tci-test` (all `copy` transformer).
