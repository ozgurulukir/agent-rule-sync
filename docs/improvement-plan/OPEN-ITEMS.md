# Improvement Plan — Post Phase 7

**Goal**: Address structural debt identified during architecture review (2026-05-25).
All items verified against the current HEAD (`37bd68b` — test baseline: 276 runs, 844 assertions, 0 failures, 0 errors, 6 skips).

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

**Test gate**: `rake test` — 287 runs, 865 assertions, 0 failures, 0 errors, 6 skips.

---
