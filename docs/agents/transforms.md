# Platform-Based Transforms

## Overview

SSoT v3 introduces platform-aware transformation: upstream sources are transformed per-agent platform via `scripts/transform.rb`. This allows a single upstream source (e.g., TCI in `opencode` format) to be adapted to different agent platforms (Claude, Gemini, Qwen, Droid, etc.) with minimal custom code.

## Transform Pipeline

```
upstream (source.platform) 
  → fetch (ssot/vendor/) 
  → transform (built-in/custom) 
  → SSoT (ssot/rules/, docs/, skills/) 
  → sync (agent configs)
```

**Commands:**
```bash
make fetch-upstream   # Populate ssot/vendor/ from sources (local-path copy or URL fetch)
make transform        # Transform upstream → SSoT using platform-based rules
make index            # Regenerate INDEX.md + index.json from schema
make vendor-skills    # Generate vendor skill files from SSoT content
make sync             # Distribute SSoT to all agent configs
```

## Schema Structure

### sources

```yaml
sources:
  local:
    platform: generic
    type: local
    default_transformer: copy

  tci:
    platform: opencode
    type: local-path
    path: "~/Projects/coderlm/agents/opencode"
    default_transformer: strip-frontmatter

  vibe-security:
    platform: generic
    type: url
    base_url: "https://github.com/raroque/vibe-security-skill/raw/main/"
    default_transformer: copy
```

- `type`: `local` (inline), `local-path` (directory), `url` (HTTP fetch)
- `platform`: upstream content's native platform format
- `default_transformer`: built-in (`copy`, `strip-frontmatter`) or custom script path
- `path` / `base_url`: location of upstream content

### platforms

```yaml
platforms:
  opencode:
    format: directory
    rules_dir: rules/
    skills_dir: skills/
    docs_dir: docs/
    transforms:
      from: [opencode, generic]   # source platforms that need no transform
      custom: null                 # no custom script needed

  claude:
    format: import
    config_file: CLAUDE.md
    rules_import: "@{ssot}/rules/{file}"
    transforms:
      from: [opencode]             # only opencode sources need transform
      custom: scripts/transforms/opencode-to-claude.rb
```

- `from`: list of source `platform` IDs that can be used as-is (copy) for this agent platform
- `custom`: path to custom transformer script (relative to repo root) if source platform not in `from`

### rules / docs / skills.upstream

Each entry references a `source` and `upstream_path`:

```yaml
rules:
  - id: tci
    filename: 06-tci.md
    source: tci
    upstream_path: AGENTS.md
    transformer: strip-frontmatter   # optional; overrides source default

docs:
  - id: tci-cli-reference
    filename: tci-cli-reference.md
    source: tci
    upstream_path: docs/cli-reference.md
    # transformer: copy (inherits from source)

skills:
  upstream:
    tci-analyze:
      source: tci
      upstream_path: skills/tci-analyze/SKILL.md
      transformer: copy
```

- `source`: references `sources[source_id]`
- `upstream_path`: relative path within the source (for `local-path` and `url` types)
- `transformer`: optional; overrides `sources[source_id].default_transformer`

## Transform Resolution

For each rule/doc/skill entry, `transform.rb` determines:

1. Look up `source_cfg = sources[entry.source]`
2. Fetch content:
   - `type: local` or `local-path` → `Pathname(source_cfg.path).join(entry.upstream_path)`
   - `type: url` → `URI.open(source_cfg.base_url + entry.upstream_path)` (follows redirects)
3. Determine transformer:
   - If `entry.transformer` set → use that
   - Else `source_cfg.default_transformer`
4. Apply:
   - If transformer is `copy` or `strip-frontmatter` (built-in) → apply inline
   - Else → `require_relative` custom script, instantiate `Transform` class, call `#transform(source_file:, entry:)`
5. Write to SSoT:
   - rules → `ssot/rules/<filename>`
   - docs → `ssot/docs/<filename>`
   - skills → `ssot/skills/<filename>`

## Built-in Transformers

| Name | Behavior |
|------|----------|
| `copy` | Identity — content written as-is |
| `strip-frontmatter` | Removes YAML frontmatter (`---\n...\n---`) from top of file |

## Custom Transformers

Custom transformers are Ruby scripts (`scripts/transforms/*.rb`) that define a `Transform` class:

```ruby
# scripts/transforms/opencode-to-claude.rb
class Transform
  def initialize(source_file:, entry:)
    @source_file = source_file
    @entry = entry
  end

  def transform
    content = File.read(@source_file)
    # ... transform content to target platform format ...
    transformed_content
  end
end
```

**Conventions:**
- Script path referenced in `platforms[platform].transforms.custom` or `rules[].transformer`
- Class name must be `Transform`
- `#transform` returns transformed content as a string
- Access `@entry` (hash with `:id`, `:filename`, `:source_id`, `:upstream_path`, `:transformer`) and `@source_file` (Pathname, may be `nil` for URL sources)

**When to write a custom transformer:**
- Source and target platforms differ in format (e.g., `directory` → `import` requires rewriting as import tags)
- Content restructuring needed (e.g., extracting specific sections, reformatting frontmatter)
- LLM-based transformation (future: `llm-prompt` transformer type reads prompt from `transformer-prompts/`)

## Platform Compatibility Matrix

| Source Platform → Target | opencode | claude | gemini | qwen | factory-droid | goose | crush | oh-my-pi |
|--------------------------|----------|--------|--------|------|---------------|-------|-------|----------|
| **opencode** | copy | custom | custom | custom | custom | custom | custom | custom |
| **generic** | copy | custom | custom | custom | custom | custom | custom | custom |
| **local** | copy | — | — | — | — | — | — | — |

- `copy`: no transform needed (source and target formats compatible)
- `custom`: requires `scripts/transforms/<target>.rb` to convert from source platform to target platform
- `—`: not applicable (source not listed in `transforms.from` for that target)

## Future: LLM-Based Transformers

Planned: `transformer: llm-prompt` type. The script reads a prompt file (`transformer-prompts/<source>/<rule>.md`), sends upstream content to an LLM with the prompt, and writes the response. This enables intelligent extraction and reformatting without hand-written Ruby.

## Debugging

- **Transform log**: `ssot/transforms.log` (YAML chunks, one per `make transform` run). Shows timestamp, transformed entries, skipped, errors.
- **Check mode**: `make check` validates all agent targets match SSoT.
- **Dry-run**: Not yet implemented for `transform.rb`; run with `--dry-run` flag (future).
- **Verbose**: `transform.rb` prints each entry's transformer name and source/target paths.

## Examples

### Example 1: TCI Rule (opencode → opencode, no transform)

`sources.tci.platform = opencode`, `platforms.opencode.transforms.from = [opencode, generic]`. Rule entry `06-tci.md` has `source: tci`, `transformer: strip-frontmatter` (built-in). Content fetched from `~/Projects/coderlm/agents/opencode/AGENTS.md`, frontmatter stripped, written to `ssot/rules/06-tci.md`.

### Example 2: Vibe Security (url → generic, copy)

`sources.vibe-security.type = url`, `platform = generic`. Rule entry `vibe-security.md` has `source: vibe-security`, `upstream_path: vibe-security/SKILL.md`, `transformer: copy`. Content fetched from `https://github.com/.../vibe-security/SKILL.md`, copied as-is to `ssot/rules/vibe-security.md`.

### Example 3: Future Claude Import (opencode → claude, custom)

When we add Claude agent, `platforms.claude.transforms.custom = scripts/transforms/opencode-to-claude.rb` will convert opencode-format rules (markdown files) into Claude's import format (`@/abs/path` lines in `CLAUDE.md`).

## See Also

- `docs/agents/ssot-architecture.md` — Full SSoT v3 architecture overview
- `docs/agents/index.md` — Index guide (INDEX.md + index.json)
- `AGENTS.md` — Repository guidelines (AI assistant context)
- `scripts/transform.rb` — Transform engine implementation