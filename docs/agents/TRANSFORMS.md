# Transforms — Translate + Transform System

The content processing pipeline has two sequential steps:

```
Source File (src/)
    ↓
TRANSLATE  — content format conversion (format family change)
    ↓
TRANSFORM  — structural/format changes
    ↓
Built Artifact (ssot/build/<platform>/)
```

**Translate** converts between format families (e.g., flat rule → skill, markdown → import).
**Transform** applies structural changes (copy, strip-frontmatter, add-header, etc.).

Both steps are specified per-target in the PKGBUILD. Translate runs first, then transform.

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

**Use case**: Upstream sources (e.g., TCI AGENTS.md) that include frontmatter for their own system.

---

## Custom Transformers

### API

Custom transformers are Ruby scripts located in `ssot/transformers/`. They must define a `Transform` class with a `#transform` instance method.

```ruby
# ssot/transformers/example.rb
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

**Path resolution**:
- Relative to repository root (`SSOT_ROOT`)
- Supports `~` expansion: `custom:~/my-transformers/foo.rb`
- Must resolve within repo (symlink attack prevention via `realpath`)

### Example Transformers

#### add-header.rb

Prepends a title header from YAML frontmatter.

```ruby
class Transform
  def initialize(content:, pkgname:)
    @content = content
    @pkgname = pkgname
  end

  def transform
    # Extract title from frontmatter if present
    if @content.start_with?('---')
      lines = @content.lines
      end_frontmatter = lines.index { |l| l.strip == '---' } || 0
      frontmatter = lines[1...end_frontmatter].join
      metadata = YAML.safe_load(frontmatter, permitted_classes: [Symbol])
      title = metadata['title'] || 'Agent Rule'

      # Insert header after frontmatter block
      after_frontmatter = lines[(end_frontmatter + 1)..-1].join
      header = "#{title}\n#{'=' * title.length}\n\n"
      header + after_frontmatter
    else
      @content
    end
  end
end
```

#### strip-comments.rb

Removes HTML comments and normalizes whitespace.

```ruby
class Transform
  def transform
    # Remove HTML comments <!-- ... -->
    content = @content.gsub(/<!--.*?--/m, '')
    # Normalize multiple blank lines to max 2
    content.gsub(/\n{3,}/, "\n\n").strip
  end
end
```

#### format-code.rb

Auto-detects code block language and adds explicit language tags.

```ruby
class Transform
  def transform
    # Detect Ruby code blocks and tag them if untagged
    @content.gsub(/```(\n.*?```m) do |block|
      if block.start_with?("```\n") && block.lines[1].strip =~ /^(def|class|module|if|while|until|for|begin)/
        "```ruby\n#{block[4..-4]}\n```"
      else
        block
      end
    end
  end
end
```

---

## Transformer Resolution

During build (`build.rb`), for each target:

1. **Check target-level override**: If target specifies `transformer`, use it.
2. **Check source default**: Otherwise use `source.default_transformer` from registry (not currently in PKGBUILD model; future).
3. **Default**: If none specified, `copy` is assumed.

**Execution**:
- Built-in (`copy`, `strip-frontmatter`) → inline apply
- Custom (`custom:<path>`) → `require_relative` script, instantiate `Transform`, call `#transform`

---

## Debugging Transformers

**Verbose build**:
```bash
ruby ssot/build.rb --verbose   # future flag
```

**Manual test**:
```ruby
# From ssot/ directory
require_relative 'lib/common'
content = File.read('ssot/packages/my-pkg/src/file.md')
transformer = Ssot::Lib::Common.load_transformer('custom:transformers/example.rb')
result = transformer.transform(content, pkgname: :my-pkg)
puts result
```

**Log inspection**:
Check `ssot/build/build.log` for transformer application errors.

---

## Best Practices

1. **Stateless**: Transformers should be pure functions (no side effects, no I/O)
2. **Fast**: Avoid network calls; transformers run synchronously during build
3. **Deterministic**: Same input → same output every time
4. **Idempotent**: Running twice should produce identical output
5. **Error handling**: Raise exceptions on failure; `build.rb` will abort with error message
6. **Encoding**: Assume UTF-8 input/output
7. **Line endings**: Preserve `\n` (do not convert to `\r\n`)

---

## Security

- **Path validation**: Custom transformer paths are validated with `realpath` to ensure they reside within repository root
- **No code execution outside transformer**: Only the specified script is `require`d; no eval/instance_eval on user content
- **Sandbox**: Transformers run in main Ruby process (no separate sandbox). Trust transformer code.

---

## Future: LLM-Based Transformers

Planned: `transformer: llm-prompt:<prompt-file>` type.

```yaml
transformer: llm-prompt:prompts/opencode-to-claude.md
```

The transformer would:
1. Read prompt file (instructions for LLM)
2. Send source content + prompt to configured LLM API
3. Return LLM's transformed response

This enables intelligent format conversion without hand-written Ruby.

---

## See Also

- [Reference](REFERENCE.md) — PKGBUILD schema, index format
- [Usage](USAGE.md) — Build and install workflows
- [Platforms](PLATFORMS.md) — Platform-specific transformation needs
