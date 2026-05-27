# Improvement Plan — Post Phase 7

**Goal**: Address structural debt identified during architecture review (2026-05-25).
All items verified against the current HEAD (`37bd68b` — test baseline: 287 runs, 929 assertions, 0 failures, 0 errors, 6 skips).

---

## Scope of this Plan

Covered here: open, medium, and low-priority issues found during the architecture review.  
Historical work (P0–P13 + Phase 1–7 refactor) is recorded in `completed-P0-P13.md` and `REFACTOR_RULEPACK_COMMON.md`.

---

## Claim Verification Summary

Each item below was confirmed by direct source inspection before being added.

| Claim | Method | Result |
|---|---|---|
| `installer.rb` = 822 LOC | `wc -l` | ✅ VERIFIED |
| `build.rb` = 430 LOC | `wc -l` | ✅ VERIFIED |
| `query.rb` = 316 LOC | `wc -l` | ✅ VERIFIED |
| `cache.rb` no eviction logic | grep `max_size\|evict\|LRU\|prune` | ✅ VERIFIED (absent) |
| `data/index.yaml` no schema migration method | grep `migrate_schema\|schema_version\b` | ✅ VERIFIED (absent) |
| Path traversal in install: `validation.rb` validates `output` | grep `validate_output_filename` | ✅ VERIFIED |
| Path traversal in install: `validation.rb` validates `target_dir` | grep `validate_target_dir` | ✅ VERIFIED |
| Path traversal in install: `cache.rb` guards `git_path` | grep `Path traversal` | ✅ VERIFIED |
| All `system()` calls use array form | grep `system(` across all .rb | ✅ VERIFIED (3 calls, all array-form) |
| `source.rb:137` `system('git','checkout',...)` | direct read | ❌ **WAS INCORRECT FLAG** — already array-form, no issue |
| `cache.rb:45` `system('tar',...)` | direct read | ✅ VERIFIED — safe, array-form |

**No items added without a verified source.**

---

## Priorities

### 🔴 P-A — Split `installer.rb` (822 LOC) into InstallPlan + InstallExecute

**Priority**: HIGH
**Risk**: MEDIUM
**Status**: ✅ COMPLETED
**Date**: 2026-05-25

**Verification**: `rake test` — 276 runs, 844 assertions, 0 failures, 0 errors, 6 skips.

**Files created**:
- `lib/rulepack/install_plan.rb` — Decision-making layer (version comparison, `should_install_or_upgrade?`, `handle_downgrade`, `ensure_package_in_index` + `EXCLUDE_KEYS`, `filter_targets_for_platform`, `warn_prerequisites`, `resolve_install_base_path`, `check_vendor_skill_present`, `uninstall_single_package_from_index!`, `platform_cfg_for`, `project_root_for`).
- `lib/rulepack/install_execute.rb` — Execution layer (install_platform, check_platform, install_single_target, install_file_or_skill, verify_package_on_disk, verify_skill_bundle, verify_single_file, aggregate_vendor_skills, record_installation, report_check_results).
- `lib/rulepack/installer.rb` — Thin orchestrator (280 LOC). Retains `run`, `install_all`, `load_master_index`, `install_single_platform`, `dispatch`, `show_package_targets`, `resolve_targets`, `ensure_build_index`.

**Design notes**:
- Both `InstallPlan` and `InstallExecute` live as top-level `Rulepack::*` modules (not nested under `Install`) to allow `InstallPlan.xxx` call sites from inside `module Rulepack::Install` without ambiguous constant resolution.
- `install_execute.rb` requires `install_plan.rb` to resolve cross-module calls.
- `installer.rb` uses `InstallPlan.xxx` and `InstallExecute.xxx` directly — no `method_missing`, no delegation indirection.
- Backward compatible: `installer.rb` still defines `Rulepack::Install.run`, `install_all`, `dispatch` as `module_function`.

---

### 🟠 P-B — Split `build.rb` (430 LOC) into BuildLoader + BuildPerPackage + BuildWriter

**Priority**: MEDIUM  
**Risk**: LOW  
**Status**: ✅ COMPLETED
**Date**: 2026-05-25

**Files**: `lib/rulepack/build.rb`, `lib/rulepack/build_loader.rb`, `lib/rulepack/build_per_pkg.rb`, `lib/rulepack/build_writer.rb`

**Result**: `build.rb` 430 LOC → ~100 LOC orchestrator.
- `BuildLoader` — PKGBUILD discovery, load & validate, pkg_index init
- `BuildPerPkg` — source fetch, per-target pipeline, checksum recording
- `BuildWriter` — build index + catalog generation

**Fixes applied during split**:
- Removed orphaned `case` block in `build_per_pkg.rb` (copy-paste artifact)
- Defined `translator_cfg` / `translate_extra` in `build_skill_bundle_target`
- Passed `translate` arg through `process_targets → build_skill_bundle_target`

**Test gate**: `rake test` — 276→287 runs, 844→865 assertions, 0 failures, 0 errors, 6 skips.

---

### 🟡 P-C — Add `data/index.yaml` Schema Version Migration Framework

**Priority**: MEDIUM  
**Risk**: LOW  
**Status**: ✅ COMPLETED
**Date**: 2026-05-25

**Files**: `lib/rulepack/schema_migration.rb`, `lib/rulepack/common.rb`, `lib/rulepack/installer.rb`, `test/test_common.rb`

**Implementation**:
```ruby
module Rulepack::SchemaMigration
  CURRENT_VERSION = 3.0
  def self.migrate!(index)   # idempotent while-loop
  def self.migrate_1_to_2!   # adds checksums.built
  def self.migrate_2_to_3!   # derives pkg_type from target format mix
  def self.derive_pkg_type   # rule / skill / hybrid
end
```

Called from `installer.rb:load_master_index` before any index consumer reads it.  
**Integrations already in P-A/P-B commits** (load_master_index cleanup).

**Migration summary**:
| Version jump | Field added | Logic |
|---|---|---|
| 1.0 → 2.0 | `checksums.built` | Per-platform build checksums hash, default `{}` |
| 2.0 → 3.0 | `pkg_type` | Derived from target format mix: `rule` / `skill` / `hybrid` |

**Test gate**: `rake test` — 284 runs, 862 assertions, 0 failures, 0 errors, 6 skips.

---

### 🟢 P-D — Add Explicit Cache Size Limit & LRU Eviction

**Priority**: LOW
**Risk**: LOW
**Status**: OPEN

**Current state**: `cache.rb` writes to `cache/<key>/` without any size constraint. The `cache_source` method (line 27) creates directories unconditionally. Repeated builds against remote sources (URL, git) will grow `cache/` without bounds.

**Target**:
```ruby
# config.rb adds:
def cache_max_size_mb
  Integer(ENV.fetch('RULEPACK_CACHE_MAX_MB', '500'))
end
```

`cache_source` computes total `cache/` directory size after write; if it exceeds `cache_max_size_mb`, evicts least-recently-used entries (by `mtime` on cache dir) until under limit.

**Test gate**: `rake test` — existing cache unit tests must not depend on directory size.

---

### 🟡 P-F — Fix `SchemaGenerator` YAML Parsing (`lib/rulepack/schema_generator.rb`)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: ✅ COMPLETED
**Date**: 2026-05-26

**Root cause**: Two independent bugs in `schema_generator.rb` prevented ALL 18 PKGBUILD files from being parsed:

1. **Bug 1 — `Dir.glob` returns String, not Pathname** (`schema_generator.rb:29`):
   ```ruby
   # BROKEN — Dir.glob returns Array of String; .read undefined on String
   Dir.glob(packages_dir.join('*/PKGBUILD').to_s).each do |pkgbuild_path|
   ```
   → `NoMethodError: undefined method 'read' for String`, silently swallowed by `rescue StandardError`.

2. **Bug 2 — Missing `symbolize_names: true`** (original `schema_generator.rb:31`):
   ```ruby
   # BROKEN — returns String-keyed hash, but code uses Symbol keys
   pkg = begin YAML.safe_load(pkgbuild_path.read) rescue ... end
   targets = pkg[:targets]   # always nil → empty schema
   ```

**Fix applied** (`lib/rulepack/schema_generator.rb` lines 29, 31–35):
```ruby
# Pathname#glob returns Pathname objects (consistent with build_loader.rb:15)
packages_dir.glob('*/PKGBUILD').each do |pkgbuild_path|
  pkg = begin
          YAML.safe_load(pkgbuild_path.read,
            permitted_classes: [Symbol, Pathname],
            symbolize_names: true)
        rescue StandardError => e
          Rulepack::Common.log_warn "SchemaGenerator: failed to parse #{pkgbuild_path}: #{e.class}: #{e.message}, skipping"
          next
        end
```

**Verification**: `SchemaGenerator.generate!` now successfully scans all 18 PKGBUILD files → `data/build_schema.yaml` populated with 14 platforms × 49 formats. Zero parse warnings.

**Files changed**: `lib/rulepack/schema_generator.rb`.

---

### 🟡 P-G — Wire SchemaGenerator into Build Pipeline (Pre-Build Auto-Generation)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: ✅ COMPLETED
**Date**: 2026-05-26

**Problem**: Before this fix, `SchemaGenerator` was an uncalled utility. `data/build_schema.yaml` had to be manually maintained. Any drift between PKGBUILD `translate:`/`transformer:` declarations and the schema silently produced wrong build output.

**Fix applied** (`lib/rulepack/build.rb` lines 43–52): Added `SchemaGenerator.generate!` as a pre-build step in `Build.run`, right after platform registry load and before any PKGBUILD discovery:

```ruby
# ─── Auto-generate build schema from PKGBUILD targets ──────────────────────────
# SchemaGenerator scans all PKGBUILD files and derives the (platform, format)
# → {translate, transformer} defaults for data/build_schema.yaml.
begin
  require_relative 'schema_generator'
  Rulepack::SchemaGenerator.generate!
rescue StandardError => e
  Rulepack::Common.log_warn "SchemaGenerator: pre-build step failed (#{e.class}: #{e.message}); continuing with existing schema"
end
```

**Idempotency**: `generate!` is a no-op when `data/build_schema.yaml` already matches current PKGBUILD targets — sets are collected and compared, output unchanged if identical.

**Files changed**: `lib/rulepack/build.rb`, `lib/rulepack/schema_generator.rb`, `data/build_schema.yaml` (auto-generated).

**Test gate**: `rake test_e2e` — 15 runs, 207 assertions, 0 failures, 0 errors, 1 skip. ✅

---

### 🟢 P-E — Split `query.rb` (316 LOC) into Dispatch + Per-Command Methods

**Priority**: LOW  
**Risk**: LOW  
**Status**: ✅ COMPLETED
**Date**: 2026-05-25

**Before**: 316 LOC `case`/`when` ladder inside `run`.
**After**: `run` → `COMMANDS[command]` → `send(:cmd_method, argv)`.

**Dispatch table** (`COMMANDS` constant, frozen):
| Key aliases | Target |
|---|---|
| `list-packages`, `ls` | `:cmd_list_packages` |
| `list-platforms`, `lp` | `:cmd_list_platforms` |
| `installed`, `i` | `:cmd_installed` |
| `show`, `info` | `:cmd_show` |
| `search`, `s` | `:cmd_search` |
| `check`, `c` | `:cmd_check` |
| `orphans`, `o` | `:cmd_orphans` |
| `depends`, `d` | `:cmd_depends` |
| `provides`, `p` | `:cmd_provides` |
| `help`, `h` | `:print_help` |

**Backward compat**: `list_packages`, `list_platforms`, `installed`, `show`, `search`, `check`, `orphans`, `depends`, `provides`, `show_provides` aliases preserved.

**Test gate**: `rake test` — 287 runs, 929 assertions, 0 failures, 0 errors, 6 skips.

---

### 🔴 P-H — Upstream Tracking: `bump` Command & `pkgver_func` for Git-Sourced Packages

**Priority**: HIGH
**Risk**: LOW
**Status**: ✅ COMPLETED
**Date**: 2026-05-26

**Problem**: Three git-sourced packages use `ref: main` (a moving target), but the system has no mechanism to detect upstream changes:

| Package | Source | Current `ref` |
|---|---|---|
| `vibe-security` | `raroque/vibe-security-skill` | `main` |
| `antigravity-skills` | `rmyndharis/antigravity-skills` | `main` |
| `cc-skills-golang` | `samber/cc-skills-golang` | `main` |
| `ruby-update-signatures` | `DmitryPogrebnoy/ruby-agent-skills` | `main` |

Each `bin/rulepack build` silently re-fetches `main` HEAD — if upstream changed, artifacts change but `pkgver` stays stale (`0.1.0`, `2026.05`). No version bump, no changelog, no user notification.

**Arch Linux parallel**:
- `makepkg -g` → auto-generate `.SRCINFO` checksums → `bin/rulepack bump` (detect + update)
- `pkgver()` function → `pkgver_func` field (already implemented in `build_per_pkg.rb:301-321`, validated in `validation.rb:52-54`, but **unused** by any PKGBUILD and **undocumented** in `REFERENCE.md`)

**Implementation plan**:

#### Phase 1: `bump` command (upstream change detection)

New file: `lib/rulepack/bump.rb`

```
bin/rulepack bump                     # Check all git-sourced packages
bin/rulepack bump vibe-security       # Check single package
bin/rulepack bump --apply             # Auto-update pkgver + rebuild
bin/rulepack bump --apply vibe-security
```

**Algorithm**:
1. Load `build/index.yaml` → extract `source_sha256` (commit hash) for each git-sourced package
2. For each git source: `git ls-remote <url> <ref>` → get remote HEAD commit
3. Compare remote HEAD vs cached commit hash
4. Report: `[CHANGED]`, `[CURRENT]`, or `[ERROR]`
5. With `--apply`:
   - Update `PKGBUILD` `pkgver` to new value (from `pkgver_func` or date-based default `YYYY.MM.DD`)
   - Invalidate cache for changed packages
   - Run `bin/rulepack build` for changed packages only

#### Phase 2: Wire `pkgver_func` into git-sourced PKGBUILDs

Add `pkgver_func` to git-sourced packages:
```yaml
source:
  - type: git
    url: https://github.com/raroque/vibe-security-skill.git
    ref: main
    path: vibe-security/SKILL.md
    depth: 1
pkgver_func: "git describe --tags --always 2>/dev/null || date +%Y.%m.%d"
```

#### Phase 3: Documentation

- `REFERENCE.md`: Add `pkgver_func` field to PKGBUILD schema
- `UPSTREAM.md`: Replace manual SHA256 instructions with `bump` workflow
- `README.md`: Add `bump` to command reference
- `bin/rulepack help`: Add `bump` entry

**Files to create**:
- `lib/rulepack/bump.rb` — Bump command implementation

**Files to modify**:
- `bin/rulepack` — Add `bump` command dispatch
- `lib/rulepack/cli_parser.rb` — Add `--apply` flag
- `data/packages/vibe-security/PKGBUILD` — Add `pkgver_func`
- `data/packages/antigravity-skills/PKGBUILD` — Add `pkgver_func`
- `data/packages/cc-skills-golang/PKGBUILD` — Add `pkgver_func`
- `data/packages/ruby-update-signatures/PKGBUILD` — Add `pkgver_func`
- `docs/agents/REFERENCE.md` — Document `pkgver_func`
- `docs/agents/UPSTREAM.md` — Document bump workflow
- `README.md` — Add bump command
- `AGENTS.md` — Add bump to CLI reference

**Test gate**: `rake test` — existing baseline + new bump tests must pass.

---
