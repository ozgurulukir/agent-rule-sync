# Reference

Technical reference for PKGBUILD format, transformer API, index schema, and validation rules.

---

## PKGBUILD Schema

### Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `pkgname` | string | yes | Unique package identifier (lowercase, alphanumeric + hyphens) |
| `pkgver` | string | yes | Upstream version string (e.g., `'1.0.0'`, `'2026.05'`) |
| `pkgrel` | integer | no | Package release (incremented for repackaging; default: 1) |
| `epoch` | integer | no | Upstream versioning scheme override (default: 0) |
| `pkgdesc` | string | yes | Short description |
| `arch` | string | yes | Architecture (currently only `any` supported) |
| `order` | integer | yes | Order in vendor skill aggregation (lower = earlier) |
| `source` | array | yes | Source entries (local, url, or git) |
| `targets` | array | yes | Deployment targets (platform, format, output, transformer, install) |
| `checksums` | hash | auto | `{source: null, built: {}}` (auto-populated by build) |
| `dependencies` | array | no | Package dependencies (future: resolution) |
| `conflicts` | array | no | Conflicting packages |
| `provides` | array | no | Virtual capabilities |
| `requires` | hash | no | System tool requirements (informational): `{ python: ">=3.8", ruby: ">=2.7" }` |
| `tags` | array | no | Tags for search/categorization |
| `maintainer` | string | no | Maintainer identifier |
| `license` | string | no | License (default: MIT) |

### Source Entry

```yaml
source:
  - type: local|url|git
    path: <relative-path>           # for type=local (relative to package dir)
    url: <url>                      # for type=url or git
    sha256: "<hex>"                 # for type=url (required)
    # For type=git:
    ref: <branch-tag-commit>        # git ref (default: 'main' or 'master')
    path: <subdir>                  # path within repo (default: '.')
    depth: <integer>                # shallow clone depth (optional, default: 1)
```

**Examples**:
```yaml
source:
  - type: local
    path: src/00-memory.md

source:
  - type: url
    url: https://example.com/rules/memory.md
    sha256: "a1b2c3..."

source:
  - type: git
    url: https://github.com/owner/repo.git
    ref: v1.2.3          # tag, branch, or commit hash
    path: skills/        # subdirectory inside the repo (optional, default: '.')
    depth: 1             # shallow clone (optional)
```

**Notes**:
- `git` source: repository is cloned to a temporary directory; `path` is resolved inside the cloned repo; `depth=1` recommended for speed.
- Git source checksum is the commit SHA256 (or SHA1 for legacy), not file content hash.

### Target Entry

```yaml
targets:
  - platform: <platform-id>         # Required: platform key from registry
    format: directory|import|skill|skill-bundle  # Required: output format
    output: <filename|.>            # Required: output filename (or "." for skill-bundle)
    translate: copy|custom:<path>   # Optional: platform-specific content conversion (runs BEFORE transformer)
    transformer: copy\|strip-frontmatter\|custom:<path>  # Optional (default: copy)
    install:                        # Optional: overrides platform defaults
      type: symlink\|copy\|inject\|append
      target_dir: <path>            # Optional: override install directory (required for skill-bundle)
      directive: '@import'          # Optional: for inject type
```

**Output path rules**:
- Must be a filename only (no directory separators)
- No `..` traversal
- No absolute paths
- Platform's `rules_dir`/`skills_dir`/`config_file` determines final location

**Transformer types**:
- `copy` — no transformation
- `strip-frontmatter` — remove YAML frontmatter block
- `custom:transformers/example.rb` — custom Ruby script

**Install types**:
- `symlink` — create symbolic link (relative path)
- `copy` — copy file
- `inject` — prepend directive line to config file
- `append` — append content to file (used for vendor skill aggregation)

---

## Transformer API

### Built-in Transformers

#### `copy`

Identity transformation — content written as-is.

```ruby
# No custom code needed; built into build.rb
transformer: copy
```

#### `strip-frontmatter`

Removes YAML frontmatter (`---` delimited block) from the top of the file.

```ruby
transformer: strip-frontmatter
```

**Behavior**: Strips leading `---\n...\n---` block if present; passes through content unchanged otherwise.

### Custom Transformers

Create a Ruby script in `ssot/transformers/`:

```ruby
# ssot/transformers/example.rb
class Transform
  def initialize(content:, pkgname:)
    @content = content
    @pkgname = pkgname
  end

  def transform
    # Transform @content (string) and return new string
    @content.upcase  # example: uppercase everything
  end
end
```

**Requirements**:
- Class name must be `Transform`
- `#transform` method returns transformed content as string
- Constructor accepts keyword args: `content:` (source string), `pkgname:` (package name, optional)

**Reference in PKGBUILD**:
```yaml
targets:
  - platform: cursor
    format: directory
    output: rule.md
    transformer: custom:transformers/example.rb
```

**Path resolution**:
- Path is relative to repo root (`SSOT_ROOT`)
- Can use `~` expansion (e.g., `custom:~/my-transformers/foo.rb`)
- Validated with `realpath` to ensure within repo (prevents symlink attacks)

---

## Translator API (Translate Layer)

The **translate step** runs *before* the transform step. It converts content from one format family to another — e.g., flat rule files into skill format, markdown into import-ready format.

### Pipeline Order

```
Source (fetched)
    ↓
TRANSLATE  ← platform-specific content conversion (format family change)
    ↓
TRANSFORM  ← structural/format changes (copy, strip-frontmatter, custom)
    ↓
Build artifact → Install → Target platform
```

### When to Use `translate`

Use `translate` when the target platform needs a fundamentally different content structure:

| Scenario | Translate Needed? |
|----------|-----------------|
| OpenCode rule → Crush skill (flat file → aggregated skill) | ✅ `rule-to-skill` |
| Markdown → Gemini CLI import file | ✅ `markdown-to-import` |
| Raw upstream format → local normalized format | ✅ `normalize-markdown` |
| Just strip frontmatter | ❌ Use `strip-frontmatter` transformer instead |
| Just copy as-is | ❌ Omit `translate` (default: no-op) |

### Built-in Translators

#### `copy` / `identity`
No conversion — content passes through unchanged. This is the default.

```yaml
translate: copy    # or omit entirely
```

### Custom Translators

Create a Ruby script in `ssot/translators/`:

```ruby
# ssot/translators/example.rb
# Converts markdown heading style from ## to # for platforms that prefer atx

class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname]
    # Transform content
    content.gsub(/^## /, '# ')
  end
end
```

**Requirements**:
- Class name must be `Translator`
- `.translate(content, args: {})` returns transformed content as string
- `args[:pkgname]` provides the package name for context

**Reference in PKGBUILD**:
```yaml
targets:
  - platform: crush
    format: skill
    output: SKILL.md
    translate: custom:translators/rule-to-skill.rb  # runs first
    transformer: strip-frontmatter                  # runs second
```

**Pipeline for this target**: fetch → `rule-to-skill.rb` → `strip-frontmatter` → `SKILL.md`

**Path resolution**:
- Path is relative to repo root (`SSOT_ROOT`)
- Can use `~` expansion (e.g., `custom:~/my-translators/foo.rb`)
- Validated with `realpath` to ensure within repo (prevents symlink attacks)

### Standalone Script

Run a translator from the command line:

```bash
# Read from stdin, write to stdout
echo "# Title\n\nContent" | ruby ssot/translate.rb copy

# Read from file, write to file
ruby ssot/translate.rb custom:translators/normalize.rb input.md output.md
```

### Platform Format Profiles

Each platform has a format profile in `ssot/platforms/<agent>.yaml`. These describe what the platform expects for rules, skills, content type, heading style, bullet style, etc. **These are informational — for LLM reference when writing translators, not enforced by the build system.**

Example: `ssot/platforms/crush.yaml`
```yaml
skills:
  format: single_file
  file_name: "crush.md"
  frontmatter: strip
  bullet_style: dash
  code_block: fenced
  emoji_policy: strip
```

Available profiles:
- `ssot/platforms/opencode.yaml`
- `ssot/platforms/crush.yaml`
- `ssot/platforms/goose.yaml`
- `ssot/platforms/gemini-cli.yaml`
- `ssot/platforms/codex.yaml`
- `ssot/platforms/cursor.yaml`
- `ssot/platforms/windsurf.yaml`
- `ssot/platforms/claude-code.yaml`
- `ssot/platforms/oh-my-pi.yaml`
- `ssot/platforms/qwen-code.yaml`
- `ssot/platforms/github-copilot.yaml`
- `ssot/platforms/droid.yaml`
- `ssot/platforms/agents.yaml`

---

## Index Schema

### index.yaml (master database)

```yaml
version: 3.0
generated: '2026-05-14T12:00:00Z'
packages:
  <pkgname>:
    pkgver: '1.0.0'
    pkgdesc: <string>
    order: <integer>
    status: stable|beta|experimental
    installed:
      - platform: <platform-id>
        output: <filename>
        checksum: <sha256-hex>
        installed_at: '2026-05-14T...'
      # ... multiple records per package (one per installed platform)
    available_targets: [<platform-id>, ...]
    dependencies: []
    conflicts: []
    provides: []
    tags: []
    checksums:
      source: <sha256-hex>         # source content checksum
      built:
        <platform-id>: <sha256>    # built artifact per platform
    targets:                       # raw target list from PKGBUILD
      - platform: <platform-id>
        format: directory|import|skill
        output: <filename>
        transformer: <string>
        install:
          type: symlink|copy|inject|append
```

**Notes**:
- Keys are YAML symbols (`:pkgname`) when loaded with `symbolize_names: true`
- `installed[]` contains one entry per platform+output combination
- `checksums.built` has entry for every platform the package was built for (even if not installed)

### index.json (machine-readable)

Auto-generated from `index.yaml`. Same structure with JSON keys (strings, not symbols). Use for scripts/tooling.

### build/index.yaml (build metadata)

Intermediate file written by `build.rb`:

```yaml
version: 3.0
generated: '2026-05-14T...'
packages:
  <pkgname>:
    pkgver: '1.0.0'
    pkgdesc: <string>
    available_targets: [<platform-id>, ...]
    checksums:
      source: <sha256>
      built:
        <platform-id>: <sha256>
    targets:
      - platform: <platform-id>
        format: ...
        output: ...
        transformer: ...
```

**Consumers**: `install.rb` reads this to know which artifacts exist; `query.rb` falls back to this if `index.yaml` missing.

---

## Validation

### PKGBUILD Validation

`build.rb` validates each PKGBUILD:

- Required fields: `pkgname`, `pkgver`, `pkgdesc`, `arch`, `order`, `source`, `targets`
- `source` must be non-empty array with at least one entry having `type: local` or `type: url`
- For `type: url`, `sha256` is required
- `targets` entries must have `platform`, `format`, `output`
- `format` must be one of: `directory`, `import`, `skill`, `skill-bundle`
- `transformer` (if specified) must be `copy`, `strip-frontmatter`, or `custom:<path>`
- `install.type` (if specified) must be valid for format/context

### Output Path Validation

`validate_output_filename(output, pkgname)` in `lib/common.rb`:

- No `..` components
- Not an absolute path
- After `Pathname#cleanpath`, result must not contain `File::SEPARATOR` (no subdirectories)
- Raises `ArgumentError` on violation

**Rationale**: Output filenames are joined with platform's `rules_dir`/`skills_dir`/`config_file` directory. Allowing subdirectories in `output` would break path resolution and potentially escape intended directories.

### Platform Registry Validation

`validate_platform_config(id, cfg)`:

- Required top-level: `type`, `base_path`, `display_name`
- Type-specific required fields:
  - `directory`: `rules_dir`
  - `import`: `config_file`
  - `skill`: `skill_file`
- `rule_install.type` / `skill_install.type` must be valid (symlink, copy, inject, append, null)
- `scope` must be `user` or `project` (default: `user`)

### Transformer Path Validation

Custom transformer paths are resolved with `realpath` and must be within `SSOT_ROOT` (repo root). Symlink attacks prevented by checking resolved path starts with repo root.

### skill-bundle Format Validation

`build.rb` and `install.rb` validate `skill-bundle` packages:

- `output` must be exactly `.` (directory marker)
- `install.target_dir` must be present (non-empty string)
- `install.type` must be `copy`
- `source` must be `type: local` or `type: git` with a directory path
- Source directory must exist and be readable

**Manifest format** (`manifest.json`):
```json
{
  "pkgname": "golang-security-bundle",
  "platform": "cursor",
  "generated_at": "2026-05-14T16:01:56Z",
  "sub_skills": [
    {
      "path": "golang-security",
      "name": "golang-security",
      "sha256": "a38396e7...",
      "files": {
        "golang-security/SKILL.md": "df1f23e9..."
      }
    }
  ]
}
```

**Index record**: `output` stored as `'.'`; no single-file checksum recorded (`built[platform] = nil` for local source, commit hash for git).

**Sub-skill selection** (`--select`):
```bash
# Install only specific sub-skills
bin/ssot install golang-security --select auth,sql

# Install all sub-skills (default)
bin/ssot install golang-security
```

**Meta-packages** (pacman-style):
Use `depends` to create virtual meta-packages that pull in multiple sub-skills:

```yaml
pkgname: golang-security-all
pkgdesc: All Go security skills (meta-package)
depends:
  - golang-security/auth
  - golang-security/sql-injection
  - golang-security/xss
```

---

## Version Comparison

The system uses a pacman-inspired version comparison algorithm (`compare_versions` in `lib/common.rb`):

- **Components**: `epoch`, `pkgver`, `pkgrel`
- **Comparison order**: epoch → pkgver (alphanumeric segments) → pkgrel (integer)
- `pkgver` segments: numeric segments compared as integers, alphabetic segments as locale strings; `1.2.3a` < `1.2.3b` < `1.2.4`; numeric < alphabetic (`1` < `1a`)
- Same `pkgver` with higher `pkgrel` is considered an upgrade (rebuild)
- `epoch` overrides everything: higher epoch always wins (used when upstream versioning scheme changes)

**Usage**: During install, if a package is already installed, `compare_versions` determines whether to skip (same), upgrade (newer), or reject downgrade (older, requires `--force`).

---

## Common Patterns

### Multi-Target Package

One package → multiple platforms:

```yaml
targets:
  - platform: opencode
    format: directory
    output: 00-rule.md
    transformer: copy
  - platform: cursor
    format: directory
    output: rule.md
    transformer: copy
  - platform: codex
    format: skill
    output: 00-rule.md
    transformer: copy
```

All three outputs are built from same source; installed to respective platforms.

### Custom Transformer per Target

```yaml
targets:
  - platform: opencode
    format: directory
    output: rule.md
    transformer: copy
  - platform: cursor
    format: directory
    output: rule.md
    transformer: custom:transformers/add-header.rb
```

Same package, different transformation per platform.

### Override Install Directory

```yaml
targets:
  - platform: opencode
    format: directory
    output: my-rule.md
    transformer: copy
    install:
      type: symlink
      target_dir: ~/.config/opencode/rules/   # override platform rules_dir
```

Useful for non-standard layouts.

### Dependency Tracking (Future)

```yaml
dependencies:
  - base-constraints
  - security-basics
```

Currently informational; future versions may support automatic install order.

---

## Error Codes

| Error | Meaning | Fix |
|-------|---------|-----|
| `Unknown platform` | Platform ID not in registry | Add to `platforms.yaml` or correct spelling |
| `Built artifact missing` | Build artifact not found at `build/<platform>/<output>` | Run `ruby ssot/build.rb` first |
| `Invalid output path` | `output` contains `..`, absolute path, or subdirectory | Use filename only; no path separators |
| `Transformer not found` | Custom transformer script doesn't exist | Create script at specified path |
| `Path traversal` | `target_dir` or resolved path escapes base | Use relative paths within allowed directories |
| `Platform config invalid` | Registry entry missing required fields | Fix `platforms.yaml` schema |

---

## FAQ

**Q: Can I have multiple `source` entries?**  
A: Yes. Each is processed sequentially; later ones can override earlier (for upstream overlays). All sources must exist.

**Q: Do I need to commit `ssot/build/`?**  
A: No. `build/` is generated. Commit only `packages/`, `registry/`, `transformers/`, and scripts.

**Q: Where are logs?**  
A: `ssot/build/install.log`, `ssot/build/uninstall.log`, `ssot/build/build.log`

**Q: How do I force rebuild?**  
A: Delete `ssot/build/` or specific file; `build.rb` always rewrites artifacts.

**Q: Can I install to multiple projects at once?**  
A: Yes, run multiple commands with different `--project` paths in parallel or script loop.

**Q: Are dependencies resolved automatically?**  
A: Not yet. `dependencies` field is informational. Manual install order required.

**Q: How do I remove a package entirely?**  
A: `ruby ssot/uninstall.rb <platform>` removes from that platform. To delete package: remove PKGBUILD and src/, then rebuild.

---

## See Also

- [Architecture](ARCHITECTURE.md) — System design
- [Platforms](PLATFORMS.md) — Platform reference
- [Usage](USAGE.md) — Installation workflows
- [Transforms](TRANSFORMS.md) — Transformer system
