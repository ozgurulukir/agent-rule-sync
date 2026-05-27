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
| `pkg_type` | string | yes | Package type: `rule`, `skill`, `agent`, or `hybrid` |
| `order` | integer | yes | Order in vendor skill aggregation (lower = earlier) |
| `source` | array | yes | Source entries (local, url, or git) |
| `targets` | array | yes | Deployment targets (platform, format, output, transformer, install) |
| `checksums` | hash | auto | `{source: null, built: {}}` (auto-populated by build) |
| `dependencies` | array | no | Package dependencies (future: resolution) |
| `conflicts` | array | no | Conflicting packages |
| `provides` | array | no | Virtual capabilities |
| `requires` | hash | no | System tool requirements (informational): `{ python: ">=3.8", ruby: ">=2.7" }` |
| `tags` | array | no | Tags for search/categorization |
| `pkgver_func` | string | no | Shell command to auto-derive `pkgver` from upstream source (makepkg `pkgver()` parallel). Runs inside the fetched source directory. Example: `"git log -1 --format=%cd --date=short 2>/dev/null | tr -d '-'"` |
| `maintainer` | string | no | Maintainer identifier |
| `license` | string | no | License (default: MIT) |

### Package Types

| `pkg_type` | Description | Examples |
|---|---|---|
| `rule` | Pure rule file(s) — agent instructions, constraints, conventions | memory, shell, ast-grep |
| `skill` | Pure skill file(s) — tool-like capabilities with SKILL.md manifest | vibe-security, line-repetition-control |
| `agent` | Custom agent definition — installed to platform's `agents_dir` | ruby-update-signatures |
| `hybrid` | Contains both rule and skill content — use multiple targets per platform | (future use) |

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
    ref: v1.2.3
    path: skills/
    depth: 1
```

### Target Entry

```yaml
targets:
  - platform: <platform-id>         # Required: platform key from registry
    format: directory|import|skill|skill-bundle|agent  # Required: output format
    output: <filename|.>            # Required: output filename (or "." for skill-bundle)
    translate: copy|custom:<path>   # Optional: content conversion (runs BEFORE schema engine + transformer)
    transformer: copy|strip-frontmatter|custom:<path>  # Optional (default: copy)
    agent_config:                   # Optional: for format=agent on Cursor (generates agent.json)
      model: <string>
      temperature: <float>
      triggers:
        file_patterns: [<glob>, ...]
    install:                        # Optional: overrides platform defaults
      type: symlink|copy|inject|append
      target_dir: <path>            # Optional: override install directory (required for skill-bundle)
      directive: '@import'          # Optional: for inject type
```

**Format types**:
- `directory` — individual rule files in `rules_dir`
- `import` — `@import` directives in config file
- `skill` — single aggregated skill file
- `skill-bundle` — entire directory tree with sub-skill selection
- `agent` — custom agent definition installed to `agents_dir` (always copy, not symlink)

**Install types**:
- `symlink` — create symbolic link (relative path)
- `copy` — copy file
- `inject` — prepend directive line to config file
- `append` — append content to file (used for vendor skill aggregation or `--rules-to`)

### Agent Package Example

```yaml
---
pkgname: ruby-update-signatures
pkgver: '1.0.0'
pkgrel: 1
pkgdesc: Ruby type signature update agent
arch: any
pkg_type: agent
order: 50

source:
  - type: git
    url: https://github.com/DmitryPogrebnoy/ruby-agent-skills.git
    ref: main
    path: plugins/ruby-type-signature-skills/agents

targets:
  - platform: opencode
    format: agent
    output: .
    translate: custom:data/translators/agent_to_opencode.rb
    install:
      type: copy
      target_dir: ruby-update-signatures/
  - platform: cursor
    format: agent
    output: .
    translate: custom:data/translators/agent_to_cursor.rb
    agent_config:
      model: claude-3.5-sonnet
      temperature: 0.3
      triggers:
        file_patterns: ["*.rb", "*.rbs"]
    install:
      type: copy
      target_dir: ruby-update-signatures/
  - platform: oh-my-pi
    format: agent
    output: .
    install:
      type: copy
      target_dir: ruby-update-signatures/
```

Platforms without `agents_dir` in their registry config will skip `format: agent` targets automatically.

---

## Transformer API

### Built-in Transformers

#### `copy`

Identity transformation — content written as-is.

```yaml
transformer: copy
```

#### `strip-frontmatter`

Removes YAML frontmatter (`---` delimited block) from the top of the file.

```yaml
transformer: strip-frontmatter
```

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
    @content
  end
end
```

**Requirements**:
- Class name must be `Transform`
- `#transform` method returns transformed content as string
- Constructor accepts keyword args: `content:` (source string), `pkgname:` (package name, optional)

---

## Translator API (Translate Layer)

The **translate step** runs *before* the schema engine and transform steps. It converts content from one format family to another.

### Pipeline Order

```
Source (fetched)
    ↓
TRANSLATE     ← platform-specific content conversion
    ↓
SCHEMA ENGINE ← centralized formatting (frontmatter, emoji, bullets, headings)
    ↓
TRANSFORM     ← structural/format changes (copy, strip-frontmatter, custom)
    ↓
Build artifact → Install → Target platform
```

### Custom Translators

Create a Ruby script in `data/translators/`:

```ruby
# data/translators/example.rb
class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname]
    extra_args = args[:extra_args] || {}  # pkgdesc, tags, agent_config
    # Transform content
    content
  end
end
```

**Requirements**:
- Class name must be `Translator`
- `.translate(content, args: {})` returns transformed content as string
- `args[:pkgname]` provides the package name
- `args[:extra_args]` provides additional PKGBUILD metadata

### Available Translators

| Translator | Purpose | Used For |
|---|---|---|
| `rule_to_skill.rb` | Converts flat rule → skill format | Crush, Goose, Droid, Codex |
| `rule_to_import.rb` | Converts rule → import-ready format | Gemini CLI, Qwen Code |
| `normalize_markdown.rb` | Markdown normalization | General cleanup |
| `agent_to_opencode.rb` | Agent → OpenCode YAML frontmatter | Agent packages on OpenCode |
| `agent_to_cursor.rb` | Agent → Cursor manifest + prompt | Agent packages on Cursor |
| `agent_to_claude_code.rb` | Agent → Claude Code section schema | Agent packages on Claude Code |

### Platform Format Profiles

Each platform has a format profile in `data/platforms/<agent>.yaml`. These describe what the platform expects for rules, skills, content type, heading style, bullet style, etc. The Schema Engine reads these profiles during build to apply centralized formatting.

---

## Index Schema

### index.yaml (master database)

```yaml
version: 3.0
generated: '2026-05-14T12:00:00Z'
packages:
  <pkgname>:
    pkgver: '1.0.0'
    pkgrel: 1
    epoch: 0
    pkgdesc: <string>
    pkg_type: rule|skill|agent|hybrid
    order: <integer>
    status: stable|beta|experimental
    installed:
      - platform: <platform-id>
        output: <filename>
        checksum: <sha256>
        format: <format-type>
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
        format: directory|import|skill|skill-bundle|agent
        output: <filename>
```

Key fields:
- `installed[]` — one record per platform+output combination
- `installed[].format` — format type at install time
- `checksums.built[<platform>]` — artifact checksum after transformation
- `available_targets` — list of platforms this package can deploy to
- `targets[]` — raw target definitions from PKGBUILD
- `pkg_type` — package type: `rule`, `skill`, `agent`, or `hybrid`

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
  agents_dir: <relative-path>       # Optional: agent installation directory
  rules_file: <filename>            # Optional: single file for rule append (--rules-to)
  rule_install:
    type: symlink|copy|append       # Required (type=directory)
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

  # Optional:
  prerequisites:                    # Informational tool requirements
    tools: [<tool-name>, ...]
```

**Validation**:
- `type` must be one of: `directory`, `import`, `skill`
- `scope` must be one of: `user`, `project`
- Required fields per type:
  - `directory`: `rules_dir`, `rule_install.type`
  - `import`: `config_file`, `rule_install.type`
  - `skill`: `skill_file`, `skill_install.type`
- `base_path` must be tilde-expandable absolute path (user-level) or `.` (project-level)
- `agents_dir` enables `format: agent` target support

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
  audit [options]        Audit PKGBUILD descriptors
  verify [platform]      Index-disk reconciliation (pacman -Qk)
  fix [platform]         Repair drift (pacman -F)
  catalog                Show package catalog (JSON)
  platforms              List available platforms
  help                   Show this help

Pacman-style shortcuts:
  -S <platform>          Install (same as: install)
  -R <platform>          Uninstall (same as: uninstall)
  -Qk <platform>         Verify (same as: verify)
  -F <platform>          Fix (same as: fix)
  -Q <command>           Query (same as: query)

Global Flags:
  --timing               Show operation timing
  --verbose, -v          Show debug output

Install Flags:
  --target PLATFORM      Target platform (alternative to positional arg)
  --project PATH         Project root for project-level platforms
  --dry-run              Preview without changes
  --force                Allow downgrades
  --needed               Skip already-installed packages
  --select <names>       Comma-separated sub-skill names for skill-bundle
  --on-collision <mode>  Collision handling: stop|ignore|overwrite|append
  --rules-to <path>      Redirect rules to single file (e.g., AGENTS.md)
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
├── catalog.json
├── index.yaml
└── <platform>/
    └── ...
```

### Cache Operations

- `bin/rulepack build` checks cache before fetching
- Cache hits show: `"Fetching git repo (cached)"`
- Manual cache clear: `rm -rf build/cache/`

---

## Security

### Path Traversal Protection

All file paths are validated with `realpath` to ensure they resolve within the repository root.

### Safe YAML Loading

All YAML parsing uses `YAML.safe_load` with permitted classes.

### Command Injection Prevention

All `system()` calls use array form (`system('cmd', arg1, arg2)`).

### Checksum Verification

All sources are verified against expected SHA256 checksums.

---

## See Also

- [Architecture](ARCHITECTURE.md) — System design and data flow
- [Platforms](PLATFORMS.md) — Platform reference and registry schema
- [Usage](USAGE.md) — User guide and workflows
- [Transforms](TRANSFORMS.md) — Transformer system documentation
- [Upstream](UPSTREAM.md) — Upstream source tracking
