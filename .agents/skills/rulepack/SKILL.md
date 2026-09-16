---
name: rulepack
description: Manage AI-agent rules, skills, and agent definitions with Rulepack — a pacman-style declarative package manager. Use whenever the user wants to install/update/remove/verify agent rules or skills for platforms (opencode, cursor, claude-code, gemini, goose, etc.), edit a PKGBUILD descriptor, check drift, bump upstream versions, or asks anything about the rulepack CLI — even if they just say "install this rule" or "update my agent skills".
---

# Rulepack

Rulepack is a pacman-style declarative package manager for AI-agent rules, skills, and agent definitions. One canonical source (`data/packages/*/PKGBUILD` YAML descriptors) propagates to every agent platform.

**Source repo:** `C:\Github\agent-rule-sync`. **Windows:** always run as `ruby bin/rulepack <command>` from that directory (the `bin/rulepack` script has a Bash shebang).

## Core workflow (always in this order)

```bash
cd /c/Github/agent-rule-sync

ruby bin/rulepack build                        # 1. build all packages
ruby bin/rulepack audit --strict               # 2. validate PKGBUILDs (pre-commit hook runs this)
ruby bin/rulepack install <pkg> -t <plat> --dry-run   # 3. ALWAYS preview first
ruby bin/rulepack install <pkg> -t <plat>      # 4. install
ruby bin/rulepack verify -t <plat>             # 5. confirm no drift
```

- `-t <plat|all>` / `--target` selects platform(s). Platform-scoped (project-level) platforms like `cursor` also need `--project <path>`.
- `--dry-run` never modifies anything. Never skip it when changes are uncertain.

## Exit codes (uniform across all commands)

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Partial **or** failure: drift found, some platforms failed, outdated/upstream changes exist |

So `verify` exiting 1 means "drift exists" — that's a finding, not a crash. `fix -t <plat>` (or `--auto` to skip prompts) repairs drift.

## Commands cheat sheet

| Command | Purpose |
|---|---|
| `build` | Build all packages (fetch → transform → artifacts + vendor skills) |
| `install [pkg] -t <plat>` | Deploy to a platform (`-S` alias; `--needed`, `--force`, `--on-collision stop\|ignore\|overwrite\|append`) |
| `uninstall [pkg] -t <plat>` | Remove (`-R`; marker-bound splicing restores injected files surgically) |
| `verify [pkg] -t <plat>` | Index vs disk reconciliation (`-Qk`) |
| `fix [pkg] -t <plat> [--auto]` | Repair drift (`-F`) |
| `outdated -t <plat>` | Installed packages older than the build |
| `bump [pkg] [--apply]` | Check git-sourced packages upstream; `--apply` rewrites PKGBUILD versions |
| `audit [--strict]` | Validate all PKGBUILD descriptors |
| `query show\|search\|list-packages <term>` | Inspect the package database (`list`, `show`, `search` are aliases) |
| `check <platform>` | Quick "installed state matches index" check |
| `lock` | Show pinned (pkgname, version, source_sha256) entries |

## Machine-readable output

Every Result-producing command accepts `--format text|json|yaml|jsonl`:

```bash
ruby bin/rulepack verify -t opencode --format json | jq '.data.drift'
ruby bin/rulepack build --format jsonl | jq -c 'select(.event == "result")'
```

- `json`/`yaml` emit the full Result envelope: `{status, data, errors, messages}`.
- `jsonl` streams one JSON object per event plus a final `{"event":"result",...}` line — ideal for piping into `jq`.
- Exit codes are scriptable: `0` = clean, `1` = act on it.

## Editing a package (PKGBUILD)

Descriptors live in `data/packages/`:

- `data/packages/<name>/PKGBUILD` — tracked, flat layout
- `data/packages/upstream/<name>/PKGBUILD` — git/url-sourced (bump tracks these)
- `data/packages/local/<name>/PKGBUILD` — personal, git-ignored; overrides same-name tracked packages

Minimal rule package:

```yaml
pkgname: my-rule
pkgver: '1.0.0'
pkgrel: 1
epoch: 0
pkgdesc: What this rule does
arch: any
pkg_type: rule            # rule | skill | skill-bundle | agent | hybrid
order: 10                 # lower = earlier in vendor skill aggregation

source:
  - type: local
    path: src/my-rule.md  # relative to package root; trailing / = directory (skill-bundle)

targets:
  - platform: opencode
    output: 00-my-rule.md
  - platform: cursor
    output: my-rule.md
```

Rules of thumb:
- `targets:` is optional — omit it to auto-expand to all platforms for the `pkg_type`.
- Don't hand-format platform styling (frontmatter/emoji/bullets); the Schema Engine applies each platform's profile automatically.
- After editing a PKGBUILD: `ruby bin/rulepack audit --strict`, then `build`, then `install --dry-run`.
- Git-sourced packages: run `ruby bin/rulepack bump` to check upstream; `bump --apply` rewrites versions and rebuilds.
- **Never edit `build/index.yaml` or `data/index.yaml` by hand** — they're generated state; drift is what `verify`/`fix` are for.

## Notes

- Non-interactive contexts (pipes, CI) automatically decline prompts — pass `--auto` (fix) or `--force` (uninstall) where needed.
- `--format` values: `text` (default), `json`, `yaml`, `jsonl`.
- Deep detail lives in the repo docs: `docs/agents/USAGE.md` (flags/exit codes), `REFERENCE.md` (full PKGBUILD grammar), `PLATFORMS.md` (platform paths).
