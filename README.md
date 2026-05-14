# Agent Rule Sync — SSoT v3 Distribution Toolkit

Standalone toolkit for distributing Single Source of Truth (SSoT) v3 rule sets to multiple AI coding agent configurations.

## What Is This?

This repository contains the **distribution layer** of the SSoT v3 architecture:

- **Fetch** upstream sources (URL or local-path) → `ssot/vendor/`
- **Transform** upstream content → `ssot/rules/`, `ssot/docs/`, `ssot/skills/`
- **Generate** vendor skill files (concatenated rules + skills per agent)
- **Sync** all agent configs (directory symlinks, import lines, or skill copies)
- **Validate** that all agents match the SSoT

It is designed to be used as a **git submodule** in projects that maintain their own SSoT.

## Project Structure

```
agent-rule-sync/
├── scripts/              # Ruby distribution scripts (entry points)
│   ├── fetch-upstream.rb
│   ├── transform.rb
│   ├── generate-index.rb
│   ├── vendor-skills.rb
│   └── sync-workstation-rules.rb
├── example/              # Minimal working SSoT example
│   ├── schema.yaml
│   └── rules/
│       ├── 00-memory.md
│       └── 01-shell.md
├── docs/agents/          # SSoT documentation (reusable)
│   ├── ssot-architecture.md
│   ├── transforms.md
│   ├── agent-rules.md
│   ├── upstream-sources.md
│   └── coding-agents.md
└── README.md
```

## Quick Start (As Submodule)

In your project:

```bash
# Add as submodule
git submodule add <url-to-agent-rule-sync> scripts
git submodule update --init --recursive
```

Create your `ssot/schema.yaml` and rule files, then:

```bash
make fetch-upstream   # Download upstream sources (if any)
make transform        # Transform to SSoT
make index            # Generate INDEX.md + index.json
make vendor-skills    # Build vendor skill files
make sync             # Distribute to all agent configs
make check            # Verify all agents in sync
```

The Makefile in your project should call the scripts from the submodule:

```makefile
fetch-upstream:
	@ruby scripts/fetch-upstream.rb

transform:
	@ruby scripts/transform.rb

index:
	@ruby scripts/generate-index.rb

vendor-skills:
	@ruby scripts/vendor-skills.rb

sync:
	@ruby scripts/sync-workstation-rules.rb

check:
	@ruby scripts/sync-workstation-rules.rb --check --vendored
```

## Agent Formats Supported

| Format | Agents | Mechanism |
|--------|--------|-----------|
| `directory` | OpenCode, Claurst, Oh My Pi | Symlink each rule file |
| `import` | Gemini, Qwen | Write `@/abs/path` import lines |
| `skill` | Droid, Goose, Crush | Copy vendored skill file |

## Schema Configuration

Your `ssot/schema.yaml` defines:

- **rules**: workstation constraint rules (local or upstream)
- **docs**: reference documentation (upstream)
- **skills**: common + agent-specific skills
- **agents**: target agent configs (format, path, rules, skills, header/footer)
- **sources**: upstream source definitions (local-path or url)
- **platforms**: per-platform transformers (for format conversion)

See `example/schema.yaml` for a minimal configuration.

## Upstream Sources

Two patterns supported:

**Pattern A (legacy, deprecated):**
```yaml
rules:
  - id: security
    filename: 05-security.md
    upstream:
      source: https://...
      filename: vibe-security.md
```

**Pattern B (recommended):**
```yaml
rules:
  - id: vibe-security
    filename: vibe-security.md
    source: vibe-security
    upstream_path: vibe-security/SKILL.md
    transformer: copy
```

Pattern B is canonical — it works with both `fetch-upstream` and `transform`.

## Transformers

Built-in:
- `copy` — pass through unchanged
- `strip-frontmatter` — remove YAML frontmatter (`---` blocks)

Custom transformers are Ruby scripts that implement a `Transform` class with a `#transform` method. Place them in your project (e.g., `scripts/transforms/`) and reference in `schema.yaml` under `platforms[].transforms.custom`.

## Documentation

- **SSoT Architecture**: `docs/agents/ssot-architecture.md` — full v3 architecture
- **Transforms**: `docs/agents/transforms.md` — platform-based transform system
- **Agent Rules**: `docs/agents/agent-rules.md` — workflow and agent formats
- **Upstream Sources**: `docs/agents/upstream-sources.md` — fetch process
- **Coding Agents**: `docs/agents/coding-agents.md` — comprehensive agent reference

## Development

```bash
# Run all steps
make setup

# Individual steps
make fetch-upstream
make transform
make index
make vendor-skills
make sync
make check

# Clean generated vendor files
make clean
```

## License

MIT — same as the upstream TCI project and vibe-security skill.

## Origin

This toolkit implements the SSoT v3 distribution layer: fetch, transform, generate vendor skills, sync to agents, and validate. It was originally developed for the debian-sid workstation configuration and is now reusable across any project.
