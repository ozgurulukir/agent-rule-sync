# Coding Agent Rules (SSoT v3)

This workstation has 8 GB RAM (7.4 GB usable). Memory-intensive commands can crash the desktop if not isolated with systemd cgroup memory limits.

## Single Source of Truth

All agent rules are generated from **`~/Projects/your-project/ssot/`**:

- **Sources**: `ssot/schema.yaml` — defines upstream sources (local-path, url), platforms, and transformers
- **Rules** (constraints): `ssot/rules/` — memory, shell, code-nav, patterns, git, security, TCI, vibe-security
- **Docs** (reference): `ssot/docs/` — TCI CLI reference, evo-loop, config tuning
- **Skills** (tips): `ssot/skills/` (custom) + `ssot/skills/vendor/` (generated)
- **Index**: `ssot/INDEX.md` + `ssot/index.json` — auto-generated catalog
- **Sync**: `make setup` (full install) or `make sync` (update)

> **Note**: Agent config files are **derived** from SSoT. Never edit them directly — they will be overwritten by `make sync`.

## Agent Configuration Summary

| Agent | Config File | Format | Mechanism |
|-------|-------------|--------|-----------|
| **OpenCode** | `~/.config/opencode/rules/` | directory | Symlinked per-section rule files |
| **Claurst** | `~/.claurst/rules/` | directory | Symlinked per-section rule files |
| **Oh My Pi** | `~/.omp/agent/rules/` | directory | Symlinked per-section rule files |
| **Gemini CLI** | `~/.gemini/GEMINI.md` | import | `@/abs/path` import tags |
| **Qwen Code** | `~/.qwen/QWEN.md` | import | `@/abs/path` import tags |
| **Factory Droid** | `~/.factory/AGENTS.md` | skill | Concatenated vendor skill file |
| **Goose** | `~/.config/goose/guardrails.md` | skill | Concatenated vendor skill file |
| **Crush** | `~/.config/agents/skills/workstation-rules/SKILL.md` | skill | Concatenated vendor skill file |

## What Each Agent Receives

All agents receive the same core rules via SSoT:

1. **Memory isolation**: Wrap memory-heavy commands (>1 GB) in `systemd-run --user --scope -p MemoryMax=N`
2. **Memory budget**: 3G for Node test runners, 2G for cargo/bun, 3G for npm/pnpm install
3. **Storage**: 931 GB HDD, avoid heavy random I/O, zram only swap (3.7 GB)
4. **Shell**: Non-interactive commands only
5. **Security**: Credential management, code review, dependency auditing, SSH/GPG
6. **Code navigation**: AST-first (ast-grep), semantic (code-tandem), textual (grep), manual (read)
7. **Vibe security**: Full audit framework for AI-generated code vulnerabilities

Additional agent-specific tips are included via skills:
- **Droid**: header + rules + droid-header + droid-extra
- **Goose**: header + rules + goose-guardrails + goose-extra
- **Crush**: rules only (no extra skills)

## Architecture

See [docs/agents/ssot-architecture.md](docs/agents/ssot-architecture.md) for full details on:
- Platform-based transforms (source → platform → agent)
- Upstream source management: [docs/upstream-sources.md](docs/upstream-sources.md)
- Rules vs skills separation
- Vendor workflow (upstream → `ssot/vendor/` → `ssot/rules/` + `ssot/skills/vendor/`)
- Agent format-specific sync mechanisms

## Workflow

```bash
# New machine setup (from debian-sid repo only)
git clone <repo>
cd debian-sid
make setup          # fetch-upstream → transform → index → vendor-skills → sync

# Development cycle
# 1. Edit rules: ssot/rules/*.md  OR  edit skills: ssot/skills/*.md  OR  add upstream source in schema.yaml
make transform      # transform upstream → SSoT (after fetch-upstream or schema change)
make index          # regenerate INDEX.md + index.json
make vendor-skills  # regenerate vendor skill files
make sync          # distribute to all agents
make check         # verify "All agents in sync"

# Clean generated files (keeps vendor/ upstream cache)
make clean
```

## Adding a New Rule

1. Add to `ssot/schema.yaml` under `rules:` with `id`, `title`, `order`, `filename`.
2. If local: create `ssot/rules/<filename>` directly.
3. If upstream: add `source`, `upstream_path`, and optionally `transformer` to rule entry.
4. Run `make fetch-upstream` (if upstream) → `make transform` → `make vendor-skills` → `make sync`.

## Adding a New Skill

1. Create `ssot/skills/<skill-id>.md` (custom) or declare upstream in `schema.yaml` under `skills.upstream`.
2. Reference in `schema.yaml` under `skills.agent-specific[agent]`.
3. Run `make vendor-skills && make sync`.

## Adding a New Upstream Source

1. Add source to `ssot/schema.yaml` under `sources:` with `id`, `platform`, `type` (`local-path` or `url`), `path` or `base_url`, `default_transformer`.
2. Add rules/docs/skills referencing that `source` with `upstream_path` and `filename`.
3. Run `make fetch-upstream` (copies to `ssot/vendor/`) → `make transform` (transforms to SSoT) → `make index` → `make vendor-skills` → `make sync`.

## Adding a New Platform (Agent Type)

1. Add platform to `ssot/schema.yaml` under `platforms:` with `id`, `format`, `transforms.from` (source platforms), `transforms.custom` (transform script path, optional).
2. Add agent entry under `agents:` with `platform` reference.
3. If `transforms.custom` is set, write the transformer script (`scripts/transforms/<platform>.rb`) implementing `Transform#transform`.
4. Run `make sync`.

## Verification

After any change:
```bash
make check   # Should output: "All agents in sync"
```

Check mode validates:
- Directory agents: all rule symlinks present and point to `ssot/rules/`
- Import agents: all `@/abs/path` imports present and correct
- Skill agents: vendor skill file content matches `ssot/skills/vendor/<agent>.md`
