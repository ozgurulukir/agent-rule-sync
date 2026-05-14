# Repository Guidelines

## Project Overview

This repository implements a **Single Source of Truth (SSoT)** management system for agent rules, skills, and documentation. It serves as a meta-repository that synchronizes content from upstream sources (URLs, local paths) into a canonical `ssot/` directory and then distributes that content to various agent platforms (e.g., Cursor, Windsurf, Claude Desktop) through a configurable schema-driven pipeline.

**Core Purpose**: Maintain one authoritative source for agent behavior definitions (rules, skills, docs) and automatically propagate updates to multiple target platforms with change detection, custom transformers, and symlink-based or import-based distribution strategies.

---

## Architecture & Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                         Upstream Sources                          │
│  (GitHub URLs, local paths → content with optional YAML front-  │
│   matter, various formats)                                        │
└────────────────────────────┬─────────────────────────────────────┘
                             │ fetch (fetch-upstream.rb)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                      ssot/vendor/ (raw fetch)                     │
│              Fetched upstream content as-is                       │
└────────────────────────────┬─────────────────────────────────────┘
                             │ transform (transform.rb)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                       ssot/rules/ & ssot/docs/                    │
│        Canonical, transformed, clean content (YAML-driven)        │
│        - Strip frontmatter                                        │
│        - Apply custom transformers (Ruby scripts)                 │
│        - SHA256 tracking for change detection                     │
└────────────────────────────┬─────────────────────────────────────┘
                             │ sync (sync-workstation-rules.rb)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Target Agent Platforms                         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐      │
│  │   Cursor    │  │  Windsurf   │  │   Claude Desktop   │      │
│  │ (directory) │  │ (directory) │  │    (import-based)  │      │
│  └─────────────┘  └──────────────┘  └────────────────────┘      │
│         │                 │                    │                 │
│         └─────────────────┼────────────────────┘                 │
│                           ▼                                        │
│                   ssot/skills/vendor/                             │
│              (combined skill files per agent)                      │
└──────────────────────────────────────────────────────────────────┘
```

**Key Pipeline Steps**:

1. **Fetch** (`fetch-upstream.rb`) — Download raw content from configured sources (URLs or local paths) into `ssot/vendor/`, skipping if SHA256 matches. Updates `ssot/schema.yaml` with new checksums.

2. **Transform** (`transform.rb`) — Process fetched content with built-in (`copy`, `strip-frontmatter`) or custom transformers, write canonical files to `ssot/rules/` and `ssot/docs/`. Logs results to `ssot/transforms.log`.

3. **Index** (`generate-index.rb`) — Build `ssot/INDEX.md` (human-readable) and `ssot/index.json` (machine-readable) from the schema and current state.

4. **Vendor Skills** (`vendor-skills.rb`) — Compose agent-specific skill files (`ssot/skills/vendor/<agent>.md`) by combining header content, ordered rules, agent-specific skills, and common skills per schema configuration.

5. **Sync** (`sync-workstation-rules.rb`) — Distribute canonical content to target platforms:
   - **Directory agents**: Symlink rule/doc files into target directories
   - **Import agents**: Rewrite target file with `@import` directives pointing at `ssot/` files
   - **Skill agents**: Copy vendored skill file to target location

---

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `ssot/` | Single Source of Truth root (created by pipeline) |
| `ssot/rules/` | Canonical rule files (Markdown) — source of truth for all agent rules |
| `ssot/docs/` | Canonical documentation files (Markdown) |
| `ssot/skills/` | Skill file organization |
| `ssot/skills/common/` | Shared skills used by multiple agents |
| `ssot/skills/agent-specific/` | Per-agent skill Markdown files |
| `ssot/skills/vendor/` | Generated vendored skill bundles per agent (auto-generated) |
| `ssot/vendor/` | Raw upstream fetch cache (before transformation) |
| `ssot/schema.yaml` | **Master configuration** — defines sources, rules, docs, skills, agents, platforms |
| `ssot/INDEX.md` | Generated human-readable index (auto-generated, do not edit) |
| `ssot/index.json` | Generated machine-readable index (auto-generated) |
| `ssot/transforms.log` | YAML-delimited transform history log |
| `skills/` | Development workspace for skill authoring (symlinked from `ssot/skills/`) |
| `*.rb` (root) | Ruby CLI scripts implementing the pipeline |

---

## Development Commands

**Pipeline Execution** (run from repo root):

```bash
# Fetch upstream content into ssot/vendor/ (updates schema SHA256)
ruby fetch-upstream.rb

# Transform vendor content into canonical ssot/rules/, ssot/docs/
ruby transform.rb

# Generate INDEX.md and index.json from schema + current state
ruby generate-index.rb

# Build agent-specific vendored skill files
ruby vendor-skills.rb

# One-shot: ensure vibe-security source/rule exists in schema
ruby ensure-vibe-security.rb

# Full sync: distribute ssot/ content to target agent platforms
ruby sync-workstation-rules.rb [--dry-run] [--check] [--vendored]
```

**Common Options**:
- `--dry-run` — Preview changes without writing files or creating symlinks
- `--check` — Validate all targets match SSoT state, exit non-zero on mismatch
- `--vendored` — With `--check`, validate vendored skill files match targets

**Typical Workflow**:
```bash
# After modifying ssot/schema.yaml or adding new upstream sources:
ruby fetch-upstream.rb && ruby transform.rb && ruby generate-index.rb && ruby vendor-skills.rb && ruby sync-workstation-rules.rb
```

---

## Code Conventions & Common Patterns

### Ruby Style
- **Frozen string literals**: All scripts use `# frozen_string_literal: true`
- **Pathname API**: Heavy use of `Pathname` for filesystem paths (`REPO_ROOT.join('ssot')`)
- **YAML-first configuration**: Schema-driven, parsed via `YAML.load_file()`
- **Error handling**: `warn` for non-fatal issues, `raise` for fatal errors
- **Logging**: `puts` for progress, structured YAML log entries to `ssot/transforms.log`

### Schema Structure Patterns
- **Sources**: `{ id => { platform, type: 'url'|'local'|'local-path', base_url/path, default_transformer } }`
- **Rules/Docs**: Ordered list with `id`, `title`, `order`, `filename`, `source`, `upstream_path`, `transformer`, `sha256`
- **Skills**: Grouped as `common` (array), `agent-specific` (agent → array), `upstream` (id → config)
- **Agents**: `{ name => { display_name, format: 'directory'|'import'|'skill', platform, path, rules, skills, docs, [header/footer] } }`
- **Platforms**: Platform-wide defaults for `rules_dir`, `skills_dir`, `docs_dir`, `transforms`

### Agent Formats
| Format | Mechanism | Use Case |
|--------|-----------|----------|
| `directory` | Symlink individual rule/doc files into target directory | Cursor, Windsurf (file-based agent configs) |
| `import` | Generate a single file with `@import` directives referencing `ssot/` files | Claude Desktop (import-based config) |
| `skill` | Copy pre-vendored combined skill file to target path | Skill-file-based agents |

### Symlink Management
- **Check**: `target.symlink? && target.realpath == source`
- **Sync**: `FileUtils.ln_s(source, target)` after unlinking existing
- **Skills**: Target is `target_skills_dir.join(skill_id, 'SKILL.md')`

### Change Detection
- SHA256 checksums stored in `ssot/schema.yaml` per rule/doc/upstream-skill entry
- `fetch-upstream.rb` and `transform.rb` both compute SHA256 and skip if unchanged
- Schema is rewritten only when changes detected

### Transformer Pattern
- **Built-in**: `copy` (identity), `strip-frontmatter` (remove YAML frontmatter)
- **Custom**: Filename of Ruby script in repo root; must define `Transform` class with `transform` method
- **Resolution**: `entry[:transformer] || source_cfg['default_transformer'] || 'copy'`

### Data Flow Invariants
- `ssot/schema.yaml` is the single source of truth for configuration
- `ssot/rules/` and `ssot/docs/` are the single source of truth for content
- `ssot/skills/vendor/` is auto-generated from schema + `ssot/skills/` content
- Target agents are read-only consumers; never edit agent files directly
- Always run full pipeline after schema/content changes

---

## Important Files

| File | Role |
|------|------|
| `ssot/schema.yaml` | **Master config** — defines all sources, rules, docs, skills, agents, platforms |
| `ssot/rules/*.md` | Canonical rule content (cleaned/transformed) |
| `ssot/docs/*.md` | Canonical documentation |
| `ssot/skills/common/*.md` | Shared skill definitions |
| `ssot/skills/agent-specific/<agent>/*.md` | Per-agent skill overrides |
| `ssot/skills/vendor/<agent>.md` | **Generated** combined skill file for each agent |
| `sync-workstation-rules.rb` | Core distribution engine — handles all agent formats |
| `transform.rb` | Content transformation pipeline (fetch → transform → write) |
| `vendor-skills.rb` | Skill bundler per-agent |
| `generate-index.rb` | Documentation/index generator |
| `fetch-upstream.rb` | Upstream fetcher with SHA256 tracking |

**Entry Points**: Each `.rb` file is a standalone CLI tool; no main dispatcher. Run individually or chain in shell.

---

## Runtime/Tooling Preferences

- **Language**: Ruby (≥ 2.7 recommended, ≥ 3.0 ideal)
- **Standard Library Only**: No external gems required — uses only stdlib:
  - `yaml`, `pathname`, `fileutils`, `time`, `json`, `open-uri`, `digest`, `net/http`, `uri`
- **Runtime**: Works with system Ruby or `rvm`/`rbenv` installations
- **Shell**: POSIX-compatible shell for chaining commands (`&&`, `--dry-run` flags)
- **Encoding**: UTF-8 (Ruby default with frozen string literals)
- **File System**: Requires symlink support (directory agents use `ln_s`)

**Constraints**:
- No Ruby gem dependencies (intentionally zero-dependency)
- No Node.js/Bun/Python runtime needed
- All scripts are executable (`#!/usr/bin/env ruby`)
- Schema YAML must be valid; missing `ssot/` directories are created on-demand

---

## Testing & QA

### No Automated Test Suite

This repository **does not have a traditional test suite**. Validation is performed via:

1. **`--check` mode**: `ruby sync-workstation-rules.rb --check` validates that all target agents are in sync with SSoT state. Returns non-zero exit code on mismatch.
2. **`--dry-run` mode**: Preview changes without modifying filesystem; useful for CI gating.
3. **Manual inspection**: Review `ssot/INDEX.md` and `ssot/index.json` for schema consistency.
4. **Transform log review**: `ssot/transforms.log` tracks history of fetch/transform operations.

### Quality Assurance Workflow

```bash
# Before committing schema changes: validate sync state
ruby sync-workstation-rules.rb --check

# After making changes: dry-run to preview
ruby sync-workstation-rules.rb --dry-run

# If dry-run looks good: execute real sync
ruby sync-workstation-rules.rb
```

**Common Issues Detected**:
- Missing source files (upstream not fetched)
- SHA256 mismatches (content drift)
- Symlink target missing or pointing to wrong file
- Agent `rules`/`skills`/`docs` references nonexistent schema entries
- Vendored skill file out of date (run `vendor-skills.rb` then `sync`)

### Schema Validation
The scripts assume valid YAML but do not strictly validate schema structure. Manual review of `ssot/schema.yaml` against expected keys (`rules`, `docs`, `skills`, `agents`, `sources`, `platforms`) is recommended before pipeline execution.

---

## Quick Reference: Schema Editing

When adding a new rule or agent:

1. **Edit `ssot/schema.yaml`**:
   - Add entry to `rules` array with `id`, `title`, `order`, `filename`, `source`, `upstream_path`, `transformer`
   - Add agent config under `agents` with `format`, `path`, `rules: ['rule-id']`, etc.
2. **Fetch upstream content**: `ruby fetch-upstream.rb`
3. **Transform**: `ruby transform.rb`
4. **Update indexes**: `ruby generate-index.rb`
5. **Vendor skills** (if needed): `ruby vendor-skills.rb`
6. **Sync to agents**: `ruby sync-workstation-rules.rb --dry-run` → review → `ruby sync-workstation-rules.rb`

**Rule Ordering**: `order` field is an integer; lower numbers appear first in generated indexes and are processed first during sync.

**Source Types**:
- `url` — `base_url` + `upstream_path` (fetched via HTTP with redirects)
- `local` / `local-path` — `path` is filesystem root, `upstream_path` relative to it (no SHA check if source missing)

**Custom Transformers**: Create a Ruby script at repo root defining `class Transform` with `def initialize(source_file:, entry:); end` and `def transform; end`. Return transformed content string.
