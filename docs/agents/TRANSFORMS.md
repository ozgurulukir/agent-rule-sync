# Transforms — Translate + Schema Engine + Transform System

The content processing pipeline has three sequential steps:

```
Source File (src/)
    ↓
TRANSLATE     — content format conversion (format family change)
    ↓
SCHEMA ENGINE — centralized formatting (frontmatter, emoji, bullets, headings)
    ↓
TRANSFORM     — structural/format changes
    ↓
Built Artifact (build/<platform>/)
```

**Translate** converts between format families (e.g., flat rule → skill, agent → platform-specific format).
**Schema Engine** applies centralized formatting rules from `data/platforms/<agent>.yaml` profiles.
**Transform** applies structural changes (copy, strip-frontmatter, add-header, etc.).

Both translate and transform are specified per-target in the PKGBUILD. Translate runs first, then schema engine, then transform.

---

## Built-in Transformers

### copy

Identity transformation — no changes.

```yaml
transformer: copy
```

### strip-frontmatter

Removes YAML frontmatter block from the beginning of the file.

```yaml
transformer: strip-frontmatter
```

**Behavior**:
- Strips `---\n<yaml>\n---` block if present at file start
- Preserves all content after frontmatter
- No-op if no frontmatter found

---

## Custom Transformers

### API

Custom transformers are Ruby scripts located in `data/transformers/`. They must define a `Transform` class with a `#transform` instance method.

```ruby
# data/transformers/example.rb
class Transform
  def initialize(content:, pkgname:)
    @content = content    # Source file content (string)
    @pkgname = pkgname    # Package name (symbol, optional)
  end

  def transform
    # Modify @content as needed
    @content
  end
end
```

**Constructor kwargs**:
- `content:` — full source file content as string
- `pkgname:` — package name (symbol), optional, for context/logging

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

| Transformer | Purpose |
|---|---|
| `add-header.rb` | Prepends a title header extracted from YAML frontmatter |
| `strip-comments.rb` | Removes HTML comments and normalizes whitespace |
| `format-code.rb` | Auto-detects code block language and adds explicit language tags |

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
| Just strip frontmatter | No: use `strip-frontmatter` transformer |
| Just copy as-is | No: omit `translate` (default: no-op) |

### Custom Translators

Create a Ruby script in `data/translators/`:

```ruby
# data/translators/example.rb
class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname]
    extra_args = args[:extra_args] || {}
    # Transform content
    content
  end
end
```

**Requirements**:
- Class name must be `Translator`
- `.translate(content, args: {})` returns transformed content as string
- `args[:pkgname]` provides the package name for context
- `args[:extra_args]` provides additional metadata (pkgdesc, tags, agent_config)

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

```yaml
targets:
  - platform: crush
    format: skill
    output: SKILL.md
    translate: custom:data/translators/rule_to_skill.rb  # runs first
    transformer: strip-frontmatter                        # runs after schema engine
```

```yaml
targets:
  - platform: cursor
    format: agent
    output: .
    translate: custom:data/translators/agent_to_cursor.rb
    agent_config:
      model: claude-3.5-sonnet
      temperature: 0.3
    install:
      type: copy
```

---

## Transformer Resolution

During build (`lib/rulepack/build.rb`), for each target:

1. **Fetch source**: read local file, fetch URL, or clone git repo
2. **Translate**: if `translate` specified, apply custom translator
3. **Schema Engine**: apply centralized formatting from platform profile
4. **Transform**: if `transformer` specified, apply (built-in or custom)
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
