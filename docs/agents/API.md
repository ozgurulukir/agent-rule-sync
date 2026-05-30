# Rulepack API Documentation

Developer reference for extending and integrating with Rulepack.

## Table of Contents

- [Library Modules](#library-modules)
- [Common Module](#common-module)
- [Build API](#build-api)
- [Install API](#install-api)
- [Query API](#query-api)
- [Cache API](#cache-api)
- [Transformers API](#transformers-api)
- [Translators API](#translators-api)
- [Platform Registry](#platform-registry)
- [Version Comparison](#version-comparison)

---

## Library Modules

Rulepack is organized into modular components under `lib/rulepack/`:

| Module | Purpose | Key Classes/Functions |
|--------|---------|----------------------|
| `common.rb` | Shared utilities, config, constants | `Rulepack::Common`, `Rulepack::Config` |
| `cli_parser.rb` | Unified CLI argument parsing | `Rulepack::CliParser.parse` |
| `logging.rb` | Centralized logging | `Rulepack::Common.log`, `log_error`, `log_warn` |
| `cache.rb` | HTTP/Git caching | `Rulepack::Common.cache_fetch`, `cache_store` |
| `backup.rb` | Backup/rollback support | `backup_index`, `restore_index` |
| `version.rb` | Version comparison | `Rulepack::Common.compare_versions` |
| `source.rb` | Source fetching | `fetch_git_source`, `fetch_url_source` |
| `translate.rb` | Translator loading/dispatch | `apply_translator` |
| `transform.rb` | Content transformation | `apply_transformer`, `load_transformer` |
| `schema_engine.rb` | Centralized Dynamic Schema Engine | `SchemaEngine.apply` (frontmatter, emoji, bullets, headings) |
| `build_pipeline.rb` | 4-stage build pipeline | `BuildPipeline.run` (fetch → translate → schema → transform) |
| `validation.rb` | PKGBUILD validation | `validate_pkgbuild`, `validate_target` |
| `platform.rb` | Platform registry | `load_platform_registry`, `platform_cfg_for` |
| `installer.rb` | Installation engine | `Rulepack::Install`, `install_package` |
| `uninstaller.rb` | Uninstallation logic | `uninstall_package_from_platform` |
| `build.rb` | Build orchestrator | Main build loop, per-package processing |
| `aggregate.rb` | Vendor skill aggregation | `aggregate_skills` |
| `query.rb` | Package database queries | `list_packages`, `show_package`, `search_packages` |
| `verify.rb` | Installation verification | `verify_platform`, `detect_drift` |
| `fix.rb` | Drift repair | `fix_platform`, `repair_drift` |
| `audit.rb` | PKGBUILD descriptor auditing | `Rulepack::Audit.run` |

**Sub-modules** under `lib/rulepack/lib/`:

| Module | Purpose |
|--------|---------|
| `transaction.rb` | Atomic transaction logs, backup, and filesystem rollback |
| `install_handlers.rb` | Low-level copy, symlink, and injection routines (marker-aware) |
| `skill_bundle.rb` | Complex directory skill-bundle resolution |
| `tui_selector.rb` | Terminal keyboard UI for interactive sub-skill selection |

---

## Common Module

`lib/rulepack/common.rb` — Shared utilities used across all modules.

### Configuration

```ruby
module Rulepack
  module Config
    module_function

    # Maximum HTTP redirects for URL fetches
    def max_redirects
      Integer(ENV.fetch('RULEPACK_MAX_REDIRECTS', '3'))
    end

    # HTTP read timeout in seconds
    def read_timeout
      Integer(ENV.fetch('RULEPACK_READ_TIMEOUT', '30'))
    end

    # Cache directory name under build/
    def cache_dir_name
      ENV.fetch('RULEPACK_CACHE_DIR', 'cache')
    end

    # Git shallow clone depth
    def git_clone_depth
      Integer(ENV.fetch('RULEPACK_GIT_DEPTH', '1'))
    end

    # Log level (:error, :warn, :info, :debug)
    def log_level
      ENV.fetch('RULEPACK_LOG_LEVEL', 'info').to_sym
    end
  end
end
```

### Logging

```ruby
# Set log file for current operation
Rulepack::Common.log_file = BUILD_DIR.join('install.log')

# Log at different levels
Rulepack::Common.log("Processing #{pkgname}...", level: :info)
Rulepack::Common.log_error("Failed to fetch #{url}: #{e.message}")
Rulepack::Common.log_warn("Cache miss for #{key}")
```

### YAML/JSON I/O

```ruby
# Load YAML with safe_load
data = Rulepack::Common.load_yaml(path)

# Write YAML atomically (temp file + rename)
Rulepack::Common.write_yaml_atomic(path, data)
```

### File Utilities

```ruby
# Validate output filename (no directory separators, no ..)
Rulepack::Common.validate_output_filename!("00-memory.md", :memory)

# Expand ~ in paths
expanded = Rulepack::Common.expand_user_path("~/.config/opencode/")
```

### Checksum Utilities

```ruby
# Compute SHA256 of file
checksum = Rulepack::Common.checksum_file(path)

# Compute SHA256 of string
checksum = Rulepack::Common.checksum_content(content)
```

---

## Build API

`lib/rulepack/build.rb` — Main build orchestrator.

### Build Flow

1. **Discover PKGBUILDs**: `Dir.glob('data/packages/*/PKGBUILD')`
2. **Load registry**: `Rulepack::Common.load_platform_registry`
3. **Process each package** via `BuildPipeline.run`:
   - **Fetch**: read local file, fetch URL (SHA256 verify), or clone git repo
   - **Translate**: platform-specific format conversion (e.g., rule → skill, agent → platform format)
   - **Schema Engine**: centralized formatting (frontmatter, emoji, bullets, headings)
   - **Transform**: structural changes (copy, strip-frontmatter, custom)
4. **Write build index**: `write_yaml_atomic(BUILD_INDEX_PATH, build_index_data)`
5. **Generate catalog**: `load generate-catalog.rb`

### 4-Stage Build Pipeline

`lib/rulepack/build_pipeline.rb` orchestrates:

```
:fetch → :translate → :schema_engine → :transform
```

Each stage validates completion before transitioning to the next.

### Schema Engine

`lib/rulepack/schema_engine.rb` — Centralized formatting based on `data/platforms/<agent>.yaml` profiles:

- `frontmatter`: strip or preserve YAML frontmatter
- `emoji_policy`: strip or preserve emoji characters
- `heading_style`: ATX heading normalization
- `bullet_style`: dash bullet normalization

---

## Install API

`lib/rulepack/installer.rb` — Installation engine.

### Install Flow

1. Load `build/index.yaml` and platform registry
2. For project-level platforms, resolve `--project` dir
3. For each package with target matching platform:
   - Resolve install path (`rules_dir`, `skills_dir`, `agents_dir`, `config_file`, `skill_file`)
   - `--rules-to <file>` redirects rules to a single file instead of `rules_dir`
   - Perform install (symlink, copy, inject, append)
   - Record installation in `data/index.yaml`

### Transaction Support

```ruby
def install_with_transaction(index, &block)
  backup_path = backup_index(index)  # Copy index to temp file

  begin
    block.call  # Perform installs

    # Write final index
    Rulepack::Common.write_yaml_atomic(INDEX_PATH, index)
    cleanup_backups(backup_path)
  rescue => e
    # Rollback: restore index + undo filesystem changes via journal
    Rulepack::Transaction.transaction_rollback(e, backup_path, ctx.journal)
    raise e
  end
end
```

---

## Query API

`lib/rulepack/query.rb` — Package database queries.

### Commands

```ruby
module Rulepack
  module Query
    def self.run(argv)
      argv.shift if argv.first == '-Q'  # Pacman-style flag
      command = argv.shift

      case command
      when 'list-packages', 'ls'
        list_packages
      when 'show', 'info'
        show_package(argv.first)
      when 'search', 's'
        search_packages(argv.first)
      when 'installed', 'i'
        list_installed(argv)
      when 'list-platforms', 'lp'
        list_platforms
      end
    end
  end
end
```

---

## Cache API

`lib/rulepack/cache.rb` — HTTP/Git caching.

- **HTTP fetches**: cached by SHA256 of URL
- **Git clones**: cached by commit hash
- Cache directory: `build/cache/` (configurable via `RULEPACK_CACHE_DIR`)

---

## Transformers API

`lib/rulepack/transform.rb` — Content transformation.

### Custom Transformer Interface

```ruby
# data/transformers/example.rb
class Transform
  def initialize(content:, pkgname:)
    @content = content
    @pkgname = pkgname
  end

  def transform
    # Transform @content and return new string
    @content
  end
end
```

---

## Translators API

`lib/rulepack/translate.rb` — Content translation (runs before transform).

### Custom Translator Interface

```ruby
# data/translators/example.rb
class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname]
    extra_args = args[:extra_args] || {}  # e.g., pkgdesc, tags, agent_config
    # Transform content
    content
  end
end
```

### Agent Translators

| Translator | Target | Transformation |
|---|---|---|
| `agent_to_opencode.rb` | OpenCode | Wraps prompt in YAML frontmatter (name, model, tools) |
| `agent_to_cursor.rb` | Cursor | Markdown passthrough; generates `agent.json` manifest from `agent_config` |
| `agent_to_claude_code.rb` | Claude Code | Adds `## Metadata`, `## System Prompt`, `## Capabilities` sections |

---

## Platform Registry

`data/registry/platforms.yaml` — Platform definitions.

### Loading Registry

```ruby
def load_platform_registry
  @platform_registry ||= begin
    raw = Rulepack::Common.load_yaml(Rulepack::Common::REGISTRY_PATH)
    raw.each { |id, cfg| validate_platform_config(id, cfg) }
    raw
  end
end

def clear_platform_registry_cache!
  @platform_registry = nil
end
```

---

## Version Comparison

`lib/rulepack/version.rb` — Pacman-style version comparison: `epoch:pkgver-pkgrel`.

```ruby
# Compare two version strings
# Returns: 1 if a > b, -1 if a < b, 0 if equal
result = Rulepack::Common.compare_versions('1:2.0-1', '1:1.9-1')
# => 1

# Format version to string
version_str = Rulepack::Common.format_version(0, '1.0.0', 1)
# => '1.0.0-1'
```

---

## Error Handling

All errors use `Rulepack::Error`:

```ruby
module Rulepack
  class Error < StandardError; end
end
```

Raised for build failures, install failures, validation errors, checksum mismatches, and path traversal attempts.

---

## Testing

### Running Tests

```bash
rake test                    # All tests (277 tests, 855 assertions)
```

### Test Helpers

```ruby
# test/helper.rb provides:
module TestHelpers
  def with_tmpdir
    Dir.mktmpdir do |tmpdir|
      yield Pathname.new(tmpdir)
    end
  end

  def mock_git_packages(packages_dir, mock_repos_dir)
    # Creates local git repos for all git-sourced packages
    # Rewrites PKGBUILDs to use file:// URLs
    # Enables 100% offline E2E testing
  end
end
```

---

## Extension Points

### Adding a New Transformer

1. Create `data/transformers/my-transform.rb`
2. Define `Transform` class with `#transform` method
3. Add entry to `data/build_schema.yaml` for automatic resolution, or reference in PKGBUILD as advanced override: `transformer: custom:transformers/my-transform.rb`

### Adding a New Translator

1. Create `data/translators/my-translate.rb`
2. Define `Translator` class with `.translate` class method
3. Add entry to `data/build_schema.yaml` for automatic resolution, or reference in PKGBUILD as advanced override: `translate: custom:translators/my-translate.rb`

### Adding a New Platform

1. Add to `data/registry/platforms.yaml`
2. Add platform format profile in `data/platforms/<agent>.yaml`
3. Add agent guide in `docs/agents/platforms/<agent>.md`

---

## See Also

- [Architecture](ARCHITECTURE.md) — System design
- [Reference](REFERENCE.md) — PKGBUILD schema, index format
- [Usage](USAGE.md) — User guide
- [Transforms](TRANSFORMS.md) — Transformer/translator docs
