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
    transformer: copy|strip-frontmatter|custom:<path>  # Optional (default: copy)
    install:                        # Optional: overrides platform defaults
      type: symlink|copy|inject|append
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

Create a Ruby script in `data/transformers/`:

```ruby
# data/transformers/example.rb
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
- Path is relative to repo root (`RULEPACK_ROOT`)
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
| OpenCode rule → Crush skill (flat file → aggregated skill) | ✅ `rule_to_skill` |
| Markdown → Gemini CLI import file | ✅ `markdown-to-import` |
| Raw upstream format → local normalized format | ✅ `normalize_markdown` |
| Just strip frontmatter | ❌ Use `strip-frontmatter` transformer instead |
| Just copy as-is | ❌ Omit `translate` (default: no-op) |

### Built-in Translators

#### `copy` / `identity`

No conversion — content passes through unchanged. This is the default.

```yaml
translate: copy    # or omit entirely
```

### Custom Translators

Create a Ruby script in `data/translators/`:

```ruby
# data/translators/example.rb
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
    translate: custom:translators/rule_to_skill.rb  # runs first
    transformer: strip-frontmatter                  # runs second
```

**Pipeline for this target**: fetch → `rule_to_skill.rb` → `strip-frontmatter` → `SKILL.md`

**Path resolution**:
- Path is relative to repo root (`RULEPACK_ROOT`)
- Can use `~` expansion (e.g., `custom:~/my-translators/foo.rb`)
- Validated with `realpath` to ensure within repo (prevents symlink attacks)

### Standalone Script

Run a translator from the command line:

```bash
# Read from stdin, write to stdout
echo "# Title\n\nContent" | ruby data/translate.rb copy

# Read from file, write to file
ruby data/translate.rb custom:translators/normalize.rb input.md output.md
```

### Platform Format Profiles

Each platform has a format profile in `data/platforms/<agent>.yaml`. These describe what the platform expects for rules, skills, content type, heading style, bullet style, etc. **These are informational — for LLM reference when writing translators, not enforced by the build system.**

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

Available profiles:
- `data/platforms/opencode.yaml`
- `data/platforms/crush.yaml`
- `data/platforms/goose.yaml`
- `data/platforms/gemini-cli.yaml`
- `data/platforms/codex.yaml`
- `data/platforms/cursor.yaml`
- `data/platforms/windsurf.yaml`
- `data/platforms/claude-code.yaml`
- `data/platforms/oh-my-pi.yaml`
- `data/platforms/qwen-code.yaml`
- `data/platforms/github-copilot.yaml`
- `data/platforms/droid.yaml`
- `data/platforms/antigravity.yaml`
- `data/platforms/agents.yaml`

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
        checksum: <sha256>
        installed_at: '2026-05-14T...'
    available_targets: [<platform>, ...]
    dependencies: []
    conflicts: []
    provides: []
    tags: []
    checksums:
      source: <sha256>
      built:
        <platform>: <sha256>
    targets:
      - platform: <platform-id>
        format: directory|import|skill|skill-bundle
        output: <filename>
        transformer: copy|custom:<path>
```

Key fields:
- `installed[]` — one record per platform+output combination
- `checksums.built[<platform>]` — artifact checksum after transformation
- `available_targets` — list of platforms this package can deploy to
- `targets[]` — raw target definitions from PKGBUILD

### index.json

Auto-generated from `index.yaml` for programmatic access. Schema matches `index.yaml` but in JSON format.

---

## Platform Registry Schema

Platforms are defined in `data/registry/platforms.yaml`:

```yaml
<platform_id>:
  type: directory|import|skill      # Required
  scope: user|project               # Required: installation scope
  display_name: <string>            # Required: human-readable name
  base_path: <path>                 # Required: base directory (user: ~/.config/..., project: .)

  # For directory platforms:
  rules_dir: <relative-path>        # Required (type=directory)
  skills_dir: <relative-path>       # Optional (type=directory)
  docs_dir: <relative-path>         # Optional (type=directory)
  rule_install:
    type: symlink|copy              # Required (type=directory)
  skill_install:
    type: copy|append               # Optional (type=directory)

  # For import platforms:
  config_file: <filename>           # Required (type=import)
  rule_install:
    type: inject|copy               # Required (type=import)
    directive: '@import'            # Optional (for inject)
  skill_install:
    type: inject|copy               # Optional (type=import)

  # For skill platforms:
  skill_file: <filename>            # Required (type=skill)
  rule_install: null                # Not used for skill platforms
  skill_install:
    type: copy|append               # Required (type=skill)
```

**Validation**:
- `type` must be one of: `directory`, `import`, `skill`
- `scope` must be one of: `user`, `project`
- Required fields per type:
  - `directory`: `rules_dir`, `rule_install.type`
  - `import`: `config_file`, `rule_install.type`
  - `skill`: `skill_file`, `skill_install.type`
- `base_path` must be tilde-expandable absolute path (user-level) or `.` (project-level)

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RULEPACK_MAX_REDIRECTS` | `3` | Maximum HTTP redirects for URL source fetches |
| `RULEPACK_READ_TIMEOUT` | `30` | HTTP read timeout in seconds |
| `RULEPACK_CACHE_DIR` | `cache` | Cache directory name under `build/` |
| `RULEPACK_GIT_DEPTH` | `1` | Git shallow clone depth |
| `RULEPACK_LOG_LEVEL` | `info` | Log level filtering (`error`, `warn`, `info`, `debug`) |

---

## CLI Reference

```
bin/rulepack <command> [options]

Commands:
  build                  Build all packages
  install <platform>     Install to platform
  uninstall <platform>   Remove from platform
  query <cmd>            Query package database
  list                   List all packages
  show <pkgname>         Show package details
  search <tag>           Search by tag
  status                 Show system status
  check <platform>       Verify installed state
  verify [platform]      Index-disk reconciliation
  fix [platform]         Repair drift
  catalog                Show package catalog (JSON)
  platforms              List available platforms
  help                   Show this help

Global Flags:
  --timing               Show operation timing
  --verbose, -v          Show debug output
```

---

## Version Comparison

Rulepack uses pacman-style version comparison: `epoch:pkgver-pkgrel`.

Components are compared left-to-right:
1. `epoch` (integer)
2. `pkgver` (string, with dot/numeric segment comparison)
3. `pkgrel` (integer)

Examples:
- `1:2.0-1` > `1:1.9-1` (epoch equal, pkgver 2.0 > 1.9)
- `0:1.10.0` > `0:1.9.0` (pkgver 1.10 > 1.9, numeric segments)
- `0:1.0-2` > `0:1.0-1` (pkgrel 2 > 1)

Downgrades are blocked by default; use `--force` to allow.

---

## Validation Rules

### PKGBUILD Validation

`lib/rulepack/validation.rb` validates:
- Required fields present
- Field types correct (string, integer, array)
- `pkgname` format (lowercase, alphanumeric + hyphens)
- `source` entries have required fields per type
- `targets` entries have required fields per format
- `checksums` structure correct

### Platform Registry Validation

`lib/rulepack/common.rb` validates:
- `type` is one of: `directory`, `import`, `skill`
- `scope` is one of: `user`, `project`
- Required fields present per type
- `base_path` is tilde-expandable absolute or `.`

### Output Filename Validation

`lib/rulepack/common.rb` validates:
- Filename only (no directory separators)
- No `..` traversal
- No absolute paths
- Not empty

---

## Build Cache

### Cache Structure

```
build/
├── cache/
│   ├── <key>/
│   │   ├── extracted/       # Extracted/fetched source
│   │   └── metadata.json    # Cache metadata
│   └── ...
├── build.log
├── index.yaml
└── <platform>/
    └── ...
```

### Cache Keys

- **URL fetch**: SHA256 of URL + params
- **Git clone**: commit SHA
- **Local source**: not cached

### Cache Operations

- `bin/rulepack build` checks cache before fetching
- Cache hits show: `"Fetching git repo (cached)"`
- Manual cache clear: `rm -rf build/cache/`

---

## Security

### Path Traversal Protection

All file paths are validated with `realpath` to ensure they resolve within the repository root. Prevents malicious paths like `../../etc/passwd`.

### Safe YAML Loading

All YAML parsing uses `YAML.safe_load` with permitted classes. No arbitrary object deserialization.

### Command Injection Prevention

All `system()` calls use array form (`system('cmd', arg1, arg2)`) to prevent shell injection.

### Checksum Verification

All sources are verified against expected SHA256 checksums. Mismatches abort the build.

---

## See Also

- [Architecture](ARCHITECTURE.md) — System design and data flow
- [Platforms](PLATFORMS.md) — Platform reference and registry schema
- [Usage](USAGE.md) — User guide and workflows
- [Transforms](TRANSFORMS.md) — Transformer system documentation
- [Upstream](UPSTREAM.md) — Upstream source tracking
