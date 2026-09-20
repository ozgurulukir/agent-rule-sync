# Rulepack API Documentation

Developer reference for extending and integrating with Rulepack.

> Entry points and runtime behavior live in [USAGE.md](USAGE.md); this document
> covers the library surface. Architecture and module responsibilities:
> [ARCHITECTURE.md](ARCHITECTURE.md) and the root [AGENTS.md](../../AGENTS.md).

## Table of Contents

- [Library Modules](#library-modules)
- [Common Module](#common-module)
- [Index Store API](#index-store-api)
- [Build API](#build-api)
- [Install API](#install-api)
- [Query API](#query-api)
- [Cache API](#cache-api)
- [Transformers API](#transformers-api)
- [Translators API](#translators-api)
- [Platform Registry](#platform-registry)
- [Results & Rendering](#results--rendering)
- [Version Comparison](#version-comparison)
- [Error Handling](#error-handling)

---

## Library Modules

Rulepack is organized into modular components under `lib/rulepack/`:

| Module | Purpose | Key Classes/Functions |
|--------|---------|----------------------|
| `common.rb` | Explicit composition root: scoped Paths/UI contexts | `Rulepack::Common.with_paths`, `with_ui`, `paths`, `ui` |
| `paths.rb` | Runtime paths value object (the sole layout authority) | `Rulepack::Paths.for_root(root)`, `#merge` |
| `cli/commands.rb` | CLI dispatch table — one fully-declared row per command | `Rulepack::CLI::COMMANDS`, `PACMAN_ALIASES` |
| `cli/runner.rb` | CLI runner: parse → dispatch → render → exit code | `Rulepack::CLI::Runner.run(argv)` |
| `cli/help.rb` | Help text generated from the dispatch table | `Rulepack::CLI::Help.text` |
| `cli_parser.rb` | Unified CLI argument parsing | `Rulepack::CliParser.parse` |
| `installed_index.rb` | Single owner of `data/index.yaml` | `Rulepack::InstalledIndex.load`, `load_or_fresh`, `save`, `backup` |
| `build_index.rb` | Single owner of `build/index.yaml` | `Rulepack::BuildIndex.load`, `load_or_nil`, `write` |
| `installed_state.rb` | "Is this installed record intact?" dispatch | `Rulepack::InstalledState.check` (typed `Verdict`) |
| `models/*.rb` | Immutable `Data.define` value objects | `Package`, `Target`, `BuildRecord`, `InstalledRecord` |
| `logging.rb` | Centralized logging | `Rulepack::Logging.log`, `log_error`, `log_warn` |
| `cache.rb` | HTTP/Git caching with LRU eviction | `cached_fetch_url`, `cached_fetch_git_file`, `cached_fetch_git_dir` |
| `backup.rb` | File-journal session backups (index backups live in `InstalledIndex`) | `Rulepack::Common.backup_file` |
| `version.rb` | Version comparison | `Rulepack::Common.compare_versions` |
| `source.rb` | Source fetching (git + HTTP fallback, hardened tar extraction) | `fetch_git_source`, `fetch_with_redirects`, `read_source` |
| `transform.rb` | Translator/transformer dispatch | `apply_translator`, `apply_transformer` |
| `processor_loader.rb` | Translator/transformer loading | `ProcessorLoader.load_translator`, `load_transformer` |
| `schema_engine.rb` | Centralized Schema Engine | `SchemaEngine.apply` (frontmatter, emoji, bullets, headings) |
| `build_loader.rb` | PKGBUILD discovery, validation, target expansion | `BuildLoader.discover_pkgbuilds` |
| `build_per_pkg.rb` | Per-package pipeline (content passes, store writes) | `BuildPerPkg.run_content_passes` |
| `build_writer.rb` | Build index + catalog output | `BuildWriter.write_build_index`, `generate_catalog` |
| `build_all.rb` | Composite: Build → Aggregate (short-circuit, flat-merge) | `Rulepack::BuildAll.run` |
| `validation.rb` | PKGBUILD validation | `validate_pkgbuild`, `load_pkgbuild` |
| `platform.rb` | Platform path resolution | `resolve_install_path`, `platform_config` |
| `platforms.rb` | Platform registry (per-root memoized) | `Rulepack::Platforms.load(root)`, `clear_cache!` |
| `ui.rb` | Interactive terminal I/O | `Rulepack::UI#spin`, `#confirm`, `#collision_prompt`; `UI::Null` |
| `emitter.rb` | Event substrate — all backend narration | `Rulepack::Emitter.emit`, `subscribe` |
| `result.rb` | Structured backend result | `Rulepack::Result` (`status`, `data`, `errors`, `messages`, `view`) |
| `errors.rb` | Typed error hierarchy | `Rulepack::Error` + subclasses (see [Error Handling](#error-handling)) |
| `installer.rb` | Installation orchestrator | `Rulepack::Install.dispatch`, `Install.run` |
| `install_plan.rb` | Install decision logic | `InstallPlan.should_install_or_upgrade?` |
| `install_execute.rb` | Install execution + check command | `InstallExecute.install_platform`, `check_platform` |
| `uninstaller.rb` | Uninstallation (marker-aware excision) | `Rulepack::Uninstaller.dispatch` |
| `fix.rb` | Drift repair via transactional reinstall | `Rulepack::Fix.run` |
| `verify.rb` | Index vs disk reconciliation | `Rulepack::Verify.check` |
| `outdated.rb` | Installed-vs-build version comparison | `Rulepack::Outdated.run` |
| `bump.rb` | Upstream version tracking | `Rulepack::Bump.run` |
| `audit.rb` | PKGBUILD descriptor auditing | `Rulepack::Audit.run` |
| `build.rb` / `aggregate.rb` | Build orchestration / vendor skill aggregation | `Rulepack::Build.run`, `Aggregate.run` |
| `status.rb` | Installed-index summary (the `status` command) | `Rulepack::Status.run` |
| `build_catalog.rb` | Reads `build/catalog.json` (the `catalog` command) | `Rulepack::BuildCatalog.run` |
| `remote.rb` | Remote registry search/list (the `remote` command) | `Rulepack::Remote.run` |
| `lock.rb` | Lockfile report (the `lock` command) | `Rulepack::Lock.run` |
| `init_hooks.rb` | Pre-commit hook installer (the `init-hooks` command) | `Rulepack::InitHooks.run` |
| `query.rb` | Package database queries | `Rulepack::Query.run`, data methods (`packages`, `show`, …) |
| `lockfile.rb` | Lockfile store (pin/verify tuples) | `Rulepack::Lockfile#add`, `#enforce!` |
| `catalog/` | Source-repository abstraction | `LocalCatalog`, `RemoteCatalog` |

**Sub-modules** under `lib/rulepack/lib/`:

| Module | Purpose |
|--------|---------|
| `transaction.rb` | Journal + filesystem rollback (install records ops; uninstall runs inside the index-restore safety net) |
| `install_handlers.rb` | symlink / copy / inject / append / json_merge / yaml_merge / structured_inject (marker-aware) |
| `skill_bundle.rb` | Directory skill-bundle install with lazy materialization |
| `skill_bundle_lazy.rb` | Install-time materialization gated by `source_sha256` |
| `tui_selector.rb` | Terminal keyboard UI for interactive sub-skill selection |

---

## Common Module

`lib/rulepack/common.rb` — composition root: owns `RULEPACK_ROOT` and the
scoped Paths/UI contexts. Deep layers read `Common.paths` / `Common.ui`;
only entry points open a scope.

### Scoped Contexts

```ruby
# Entry points accept paths:/ui: keywords and open the scope internally.
# Internal backend-to-backend calls pass the options hash POSITIONALLY —
# Ruby 4 does not convert positional hashes to keyword arguments, so
# keyword-style options would collide with the paths:/ui: keywords.
Rulepack::Fix.run({ target: 'opencode' }, paths: sandbox_paths)
Rulepack::Uninstaller.dispatch(opts, ui: Rulepack::UI::Null.new)

# Tests open partial scopes directly (merged onto the current Paths):
Rulepack::Common.with_paths(build_index_path: tmp.join('index.yaml')) { ... }
```

### Configuration

```ruby
module Rulepack
  module Config
    module_function

    def max_redirects   # RULEPACK_MAX_REDIRECTS (default 3)
    def read_timeout    # RULEPACK_READ_TIMEOUT (default 30s)
    def cache_dir_name  # RULEPACK_CACHE_DIR (default 'cache')
    def git_clone_depth # RULEPACK_GIT_DEPTH (default 1)
    def cache_max_size_mb # RULEPACK_CACHE_MAX_MB (default 500)
    def log_level       # RULEPACK_LOG_LEVEL (default :info)
  end
end
```

### Logging

```ruby
Rulepack::Logging.log_file = Rulepack::Common.build_dir.join('install.log')

Rulepack::Logging.log("Processing #{pkgname}...", level: :info)
Rulepack::Logging.log_error("Failed to fetch #{url}: #{e.message}")
Rulepack::Logging.log_warn("Cache miss for #{key}")
```

Backend narration is Emitter events (`:progress`, `:info`, `:warn`, `:error`,
`:stage_start`, `:stage_done`, `:package_built`, `:target_built`) — never raw
`puts`. `Logging.log` is for operation logs.

### YAML/JSON I/O

```ruby
data = Rulepack::IO.load_yaml(path)            # safe_load, symbolize_names
Rulepack::IO.write_yaml_atomic(path, data)     # temp file + rename
Rulepack::IO.deep_merge(base, override)        # hash deep merge (arrays union)
Rulepack::IO.update_marked_content(path, pkgname, content)  # marker blocks
Rulepack::IO.remove_marked_content(path, pkgname)           # surgical excision
```

### File Utilities

```ruby
# Validate output filename (no directory separators, no ..)
Rulepack::Validation.validate_output_filename("00-memory.md", :memory)

# Expand ~ in paths
expanded = Rulepack::Path.expand_user_path("~/.config/opencode/")
```

---

## Index Store API

`installed_index.rb` / `build_index.rb` — the only readers/writers of the two
YAML stores. Both resolve the scoped `Paths` and never memoize (callers mutate
the returned hash in place, then save).

```ruby
# Installed index — data/index.yaml
Rulepack::InstalledIndex.exist?
index = Rulepack::InstalledIndex.load           # raises IndexNotFound / IndexCorrupt
index = Rulepack::InstalledIndex.load_or_fresh  # missing → { version: 3.0, packages: {} }
# load ALWAYS migrates: SchemaMigration + InstalledRecord.migrate_legacy!
Rulepack::InstalledIndex.save(index)            # stamps :generated, atomic write
backup_path = Rulepack::InstalledIndex.backup   # nil when nothing to back up
Rulepack::InstalledIndex.restore(backup_path)
Rulepack::InstalledIndex.cleanup_backups

# Build index — build/index.yaml
Rulepack::BuildIndex.load                       # raises BuildIndexNotFound / BuildIndexCorrupt
index = Rulepack::BuildIndex.load_or_nil
Rulepack::BuildIndex.write(packages: pkg_map)   # the single writer (BuildWriter)
Rulepack::BuildIndex.remove                     # bump's pre-rebuild primer
```

Schema ownership: record shape lives in `InstalledRecord`
(`models/installed_record.rb`, `from_h`/`to_h`/`migrate_legacy!`); build-entry
shape in `BuildRecord`; schema versions in `SchemaMigration.migrate!` (refuses
future or non-numeric versions). Disk-state verdicts: `InstalledState.check`.

---

## Build API

`bin/rulepack build` runs the `BuildAll` composite: `Build.run` →
`Aggregate.run`, short-circuiting on failure and flat-merging Results.

### Build Flow

1. **Discover PKGBUILDs**: `BuildLoader.discover_pkgbuilds` (flat + `upstream/` namespaces; `local/` overrides by name)
2. **Load registry**: `Rulepack::Common.load_platform_registry`
3. **Per package** (`BuildPerPkg`): fetch source (content-addressed cache, SHA256 verify) → per-target content passes
4. **Write build index**: `BuildIndex.write` via `BuildWriter.write_build_index`
5. **Generate catalog**: `build/catalog.json` via `BuildWriter.generate_catalog`

### Content Passes

`BuildPerPkg.run_content_passes` (translate → Schema Engine → transform).
Targets sharing identical translators/rulesets/transformers are collapsed by
`union_key` and reuse cached output. Skill-bundle/agent targets are
**materializable**: build records metadata (`source_sha256`), and
`build/<plat>/<pkg>/` is materialized lazily at install/verify time
(`skill_bundle_lazy.rb`).

### Schema Engine

`lib/rulepack/schema_engine.rb` — formatting driven by
`data/platforms/<agent>.yaml` profiles: `frontmatter`, `emoji_policy`,
`heading_style`, `bullet_style`. Profiles are validated on registry load
(unknown keys warn).

---

## Install API

`lib/rulepack/installer.rb` — `Install.dispatch` (CLI row) →
`Install.run(platform, options, paths:, ui:)` per platform.

### Install Flow

1. `BuildIndex.load` + `InstalledIndex.load_or_fresh` (both scoped)
2. `InstalledIndex.backup` before mutating; one transactional scope
3. Per package: `InstallPlan.should_install_or_upgrade?` decision (version
   compare, `--needed`, forced reinstall) → `install_single_target`
4. Handlers (`install_handlers.rb`): symlink / copy / inject / append /
   json_merge / yaml_merge / structured_inject — each journals into
   `Transaction` for rollback
5. `InstalledIndex.save` at exit; on any raise,
   `Transaction.transaction_rollback` restores the index and replays the
   journal in reverse

`Fix.run` reuses this exact path (`Install.run` with `force_packages:`),
passed positionally per the Ruby 4 rule.

---

## Query API

`lib/rulepack/query.rb` — two layers:

```ruby
# Data API (used by the CLI rows and as library):
result = Rulepack::Query.packages        # view: :packages
result = Rulepack::Query.platforms       # view: :platform_registry
result = Rulepack::Query.show('memory')  # raises ArgumentError without a name
result = Rulepack::Query.search('sec')
result = Rulepack::Query.installed('opencode')
result = Rulepack::Query.orphans         # status: :partial when orphans exist
result = Rulepack::Query.depends('memory')
result = Rulepack::Query.provides('capability')
result = Rulepack::Query.check           # consistency; failure on issues

# Subcommand dispatch (the `query` CLI row):
Rulepack::Query.run(['show', 'memory'], paths:, ui:)
Rulepack::Query.run_subcommand(options)  # positional → internal COMMANDS table
```

All data methods return `Rulepack::Result` with a declared `view:`. The
internal `COMMANDS` table maps names/aliases (`ls`, `info`, `s`, …) to
`cmd_*` wrappers; unknown subcommands return a failure Result whose messages
carry the query help text.

---

## Cache API

`lib/rulepack/cache.rb` — content-addressed source cache with LRU eviction
(`RULEPACK_CACHE_MAX_MB`, default 500).

- `cached_fetch_url(url, expected_sha256)` — HTTP with redirect following
- `cached_fetch_git_file(url, ref, git_path, depth:)` — single-file git fetch
- `cached_fetch_git_dir(url, ref, git_path, depth:, on_clone:)` — directory fetch
- `cache_source(key, content_or_path, source_type:)` / `get_cached_source(key)`
- Cache location: `<build>/cache` (naming via `Config.cache_dir_name`)

Git is optional: when the `git` binary is unavailable, tarball fallback via
`source.rb` (`translate_git_to_tarball`, hardened against path traversal).

---

## Transformers API

`lib/rulepack/transform.rb` — content transformation.

```ruby
# data/transformers/example.rb
module RulepackTransformer
  module Example
    def self.transform(content, pkgname:)
      content
    end
  end
end
```

Loaded by `ProcessorLoader.load_transformer('custom:transformers/example.rb')`;
the path must resolve inside the repository (`SecurityError` otherwise).

---

## Translators API

`lib/rulepack/transform.rb` (`apply_translator`) — content translation (runs
before transform and the Schema Engine).

```ruby
# data/translators/example.rb
module RulepackTranslator
  module Example
    def self.translate(content, args: {})
      pkgname = args[:pkgname]
      extra_args = args[:extra_args] || {}  # e.g. pkgdesc, tags, agent_config
      content
    end
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

`data/registry/platforms.yaml` — platform definitions.

```ruby
# Merge order: data/registry/platforms.yaml <- <root>/.rulepack.local.yaml
#              <- ~/.config/rulepack/config.yaml
registry = Rulepack::Platforms.load(root)   # memoized per root
Rulepack::Platforms.clear_cache!            # drop one or all cached roots

# Common.load_platform_registry resolves the SCOPED root (paths.root);
# a scoped root without registry files inherits the repo registry:
registry = Rulepack::Common.load_platform_registry
```

Platform configs are validated on load (required keys per `type`);
`format_profile` (from `data/platforms/<id>.yaml`) unknown keys warn.

---

## Results & Rendering

Every backend returns a `Rulepack::Result`:

```ruby
Result.new(status:, data:, errors:, messages:, view:)
# status: :success | :partial | :failure  (CLI exit rule: success → 0, else 1)
# view:   declares the TextRenderer route for text mode; nil = messages-only.
#         Excluded from to_h — json/yaml/jsonl stay {status, data, errors, messages}.
```

The CLI (`cli/runner.rb`) parses once, dispatches the table row, renders once.
Text rendering dispatches on `result.view` — nothing is inferred from data
shape. Narration streams via Emitter events to ConsoleRenderer (default) or,
under `--format jsonl`, JsonlRenderer plus a final `{"event":"result",...}`
line.

Adding a command is one row in `cli/commands.rb`
(`backend:`/`method:`, optional `call: :args`, `defaults:`/`positional:`,
`max_positional:`, and `group:`/`synopsis:`/`description:` for the generated
help).

---

## Version Comparison

`lib/rulepack/version.rb` — Pacman-style `epoch:pkgver-pkgrel`.

```ruby
Rulepack::Common.compare_versions('1:2.0-1', '1:1.9-1')  # => 1
Rulepack::Common.format_version(0, '1.0.0', 1)            # => '1.0.0-1'
```

---

## Error Handling

All library errors derive from `Rulepack::Error` (`errors.rb`); the CLI
rescues it, warns, and exits 1.

```ruby
Rulepack::Error
├── ConfigError            # CliError, MissingOptionValue, InvalidOptionValue
├── PkgbuildError          # PkgbuildNotFound, InvalidPkgbuild
├── SecurityError          # PathTraversalError
└── StateError             # IndexNotFound, IndexCorrupt,
                           # BuildIndexNotFound, BuildIndexCorrupt,
                           # UnknownPlatform
```

`SchemaMigration.migrate!` raises `StateError` for future/non-numeric index
versions instead of rewriting them. `Psych::SyntaxError` from a corrupt store
is wrapped as the typed corrupt error by the stores.

---

## Testing

```bash
bundle exec rake test      # full suite
bundle exec rake summary   # dynamic test/assertion count (scans test files)
```

### Test Seams

- **In-process backend tests**: build a `Rulepack::Paths` sandbox and pass
  `paths:` (see `test/test_outdated.rb`, `test/test_fix.rb`).
- **In-process runner tests**: `Rulepack::Common.with_paths(paths) { Rulepack::CLI::Runner.run(argv) }`
  returns the exit code; clear the Emitter first (the helper wires a global
  renderer) — see `test/test_cli_runner.rb`.
- **E2E**: `test/helper.rb#mock_git_packages` creates local git repos and
  rewrites PKGBUILDs to `file://` URLs for offline subprocess runs.
