# Transforms — Translate + Schema Engine + Transform System

The content processing pipeline is **fully automatic**. PKGBUILD authors do not need to specify `translate` or `transformer` — the system resolves them based on platform type and target format.

```
Source File (src/)
    ↓
TRANSLATE     — default from data/registry/platforms.yaml (skill→rule_to_skill, import→rule_to_import, agent→platform translator)
    ↓
SCHEMA ENGINE — auto-applied from data/platforms/<agent>.yaml (frontmatter, emoji, bullets, headings)
    ↓
TRANSFORM     — default from data/registry/platforms.yaml (default: copy)
    ↓
Built Artifact (build/<platform>/)
```

**Translate** converts between format families automatically. Defaults are declared per platform in `data/registry/platforms.yaml` (`default_translator`):
- `skill` platforms (crush, goose, droid, codex) → `rule_to_skill.rb`
- `import` platforms (qwen-code, github-copilot) → `rule_to_import.rb`
- `agent` format → platform-specific agent translator

**Schema Engine** applies centralized formatting from platform profiles.
**Transform** applies structural changes. Defaults are declared per platform in `data/registry/platforms.yaml` (`default_transformer`); the built-in default is `copy` (no-op).

`translate:` and `transformer:` in PKGBUILD are **advanced overrides only** — use them for edge cases not covered by the platform registry defaults.

---

## Built-in Transformers

### copy

Identity transformation — no changes.

```yaml
transformer: copy
```

### ~~strip-frontmatter~~ (DEPRECATED)

> **Deprecated**: YAML frontmatter stripping is now handled automatically by the **Schema Engine** based on each platform's `frontmatter` policy in `data/platforms/<agent>.yaml`. Using `strip-frontmatter` as a transformer will produce a validation error. Remove it from your PKGBUILD targets and rely on the Schema Engine instead.

---

## Custom Transformers

### API

Custom transformers are Ruby scripts located in `data/transformers/`. They define a `RulepackTransformer::<Name>` module with a `.transform(content, pkgname:)` class method. The module name is derived from the filename.

```ruby
# data/transformers/example.rb
module RulepackTransformer
  module Example
    def self.transform(content, pkgname:)
      # Modify content as needed
      content
    end
  end
end
```

**Method kwargs**:
- `content:` — full source file content as string
- `pkgname:` — package name (string), optional, for context/logging

**Return value**: Transformed content string.

### Usage in PKGBUILD

```yaml
targets:
  - platform: cursor
    format: directory
    output: rule.md
    transformer: custom:transformers/example.rb
```

### Available Custom Transformers

| Transformer | Purpose | Module |
|---|---|---|
| `add-header.rb` | Prepends a title header extracted from YAML frontmatter | `RulepackTransformer::AddHeader` |
| `add_frontmatter.rb` | Injects YAML frontmatter for OpenCode-style skills | `RulepackTransformer::AddFrontmatter` |
| `strip-comments.rb` | Removes HTML comments and normalizes whitespace | `RulepackTransformer::StripComments` |
| `format-code.rb` | Auto-detects code block language and adds explicit language tags | `RulepackTransformer::FormatCode` |

---

## Schema Engine

`lib/rulepack/schema_engine.rb` — Centralized Dynamic Schema Engine that normalizes document structure based on platform profiles in `data/platforms/<agent>.yaml`.

### What It Does

- **Frontmatter**: Strips or preserves YAML frontmatter per platform policy
- **Emoji policy**: Strips or preserves emoji characters
- **Heading style**: Normalizes ATX heading levels
- **Bullet style**: Normalizes to dash bullets

### Platform Profiles

Each platform has a profile in `data/platforms/<agent>.yaml` that declares formatting preferences. The Schema Engine reads these during the build pipeline's `:schema_engine` stage.

Example: `data/platforms/crush.yaml`
```yaml
skills:
  format: single_file
  file_name: "crush.md"
  frontmatter: strip
  bullet_style: dash
  code_block: fenced
  emoji_policy: strip
```

Available profiles: `opencode`, `crush`, `goose`, `gemini-cli`, `codex`, `cursor`, `windsurf`, `claude-code`, `oh-my-pi`, `qwen-code`, `github-copilot`, `droid`, `antigravity`, `agents`

---

## Translator System

The **translate step** runs before the schema engine and transform steps. It converts content from one format family to another.

### Automatic Translator Resolution

Translators are resolved automatically in this priority order:

1. **PKGBUILD explicit** — if `translate:` is set in a target entry, it always wins
2. **Platform registry** — `data/registry/platforms.yaml` declares the `default_translator` for each platform (e.g., `crush` → `rule_to_skill.rb`, `qwen-code` → `rule_to_import.rb`)

| Platform Type | Default Translator |
|---|---|
| `skill` (crush, goose, droid, codex) | `rule_to_skill.rb` |
| `import` (qwen-code, github-copilot) | `rule_to_import.rb` |
| `directory` | *(none — not needed)* |

This means PKGBUILD authors do **not** need to specify `translate:` for the common case of rules being deployed to skill or import platforms. The system handles it automatically.

### When to Use `translate`

Use `translate` when the target platform needs a fundamentally different content structure:

| Scenario | Translate Needed? |
|----------|-----------------|
| OpenCode rule → Crush skill (flat file → aggregated skill) | Yes: `rule_to_skill` |
| Markdown → Gemini CLI import file | Yes: `rule_to_import` |
| Agent → OpenCode YAML frontmatter format | Yes: `agent_to_opencode` |
| Agent → Cursor manifest + prompt | Yes: `agent_to_cursor` |
| Agent → Claude Code section schema | Yes: `agent_to_claude_code` |
| Raw upstream format → local normalized format | Yes: `normalize_markdown` |
| Just copy as-is | No: omit `translate` (default: no-op) |

### Custom Translators

Create a Ruby script in `data/translators/`:

```ruby
# data/translators/example.rb
module RulepackTranslator
  module Example
    def self.translate(content, args: {})
      pkgname = args[:pkgname]
      extra_args = args[:extra_args] || {}
      # Transform content
      content
    end
  end
end
```

**Requirements**:
- Module name is derived from the filename: `data/translators/my_thing.rb` → `RulepackTranslator::MyThing`
- `.translate(content, args: {})` returns transformed content as string
- `args[:pkgname]` provides the package name for context
- `args[:extra_args]` provides additional metadata (pkgdesc, tags, agent_config)
- The legacy `RulepackTranslator::Impl` / `Translator` forms are still accepted for old scripts

### Available Translators

#### Content Translators

| Translator | Purpose |
|---|---|
| `rule_to_skill.rb` | Converts flat rule files into skill format for aggregation |
| `rule_to_import.rb` | Converts rules into import-ready format |
| `normalize_markdown.rb` | Normalizes markdown formatting |

#### Agent Translators

Agent translators convert agent definitions to platform-specific formats. They are used in PKGBUILD targets with `format: agent`:

| Translator | Target Platform | Transformation |
|---|---|---|
| `agent_to_opencode.rb` | OpenCode | Wraps prompt in YAML frontmatter (name, description, model, tools) |
| `agent_to_cursor.rb` | Cursor | Markdown passthrough; generates `agent.json` manifest from `agent_config` |
| `agent_to_claude_code.rb` | Claude Code | Adds `## Metadata`, `## System Prompt`, `## Capabilities` sections |

**Platforms not needing translators**: Oh My Pi and Windsurf auto-discover plain markdown — no format conversion required.

### Usage in PKGBUILD

**Not needed for normal use** — translators are resolved automatically. Only specify `translate:` for advanced edge cases:

```yaml
targets:
  - platform: crush
    translate: custom:data/translators/my_custom_translator.rb
```

```yaml
targets:
  - platform: cursor
    agent_config:
      model: claude-3.5-sonnet
      temperature: 0.3
```

---

## Transformer Resolution

During build (`lib/rulepack/build.rb`), for each target:

1. **Fetch source**: read local file, fetch URL, or clone git repo
2. **Translate**: resolve translator from platform registry (`default_translator`), apply if non-nil; PKGBUILD `translate:` overrides the registry default
3. **Schema Engine**: apply centralized formatting from platform profile
4. **Transform**: resolve transformer from platform registry (`default_transformer`), apply if non-`copy`; PKGBUILD `transformer:` overrides the registry default
5. **Write artifact**: output to `build/<platform>/<output>`

---

## Debugging Transformers

**Log inspection**: Check `build/build.log` for transformer application errors.

**Manual test**:
```ruby
# From repo root
require_relative 'lib/rulepack/common'
content = File.read('data/packages/my-pkg/src/file.md')
# Test transformer manually
```

---

## Best Practices

1. **Stateless**: Transformers should be pure functions (no side effects, no I/O)
2. **Fast**: Avoid network calls; transformers run synchronously during build
3. **Deterministic**: Same input → same output every time
4. **Idempotent**: Running twice should produce identical output
5. **Error handling**: Raise exceptions on failure; `build.rb` will abort with error message

---

## Security

- **Path validation**: Custom transformer/translator paths are validated with `realpath` to ensure they reside within repository root
- **No code execution outside script**: Only the specified script is `require`d; no eval/instance_eval on user content

---

## See Also

- [Reference](REFERENCE.md) — PKGBUILD schema, index format
- [Usage](USAGE.md) — Build and install workflows
- [Platforms](PLATFORMS.md) — Platform-specific transformation needs
