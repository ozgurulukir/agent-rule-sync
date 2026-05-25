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
**Status**: OPEN

**Current state** (`build.rb` 430 LOC):
- Lines 1–80: PKGBUILD discovery, loading, migration
- Lines 80–200: `build_package` method — per-package transformation loop (fetch → pipeline → write)
- Lines 200–430: `write_build_artifacts`, `record_checksum`, `write_build_index`, `write_catalog` — output plumbing

**Target**: Extract:
```
lib/rulepack/build_loader.rb    # load_all_pkgbuilds, migrate_index_fields, PKGBUILD discovery
lib/rulepack/build_per_pkg.rb    # build_single_package, transform_per_target, checksum computation
lib/rulepack/build_writer.rb     # write_build_index, write_catalog, record_built_checksum
```

`build.rb` becomes the top-level `Rulepack::Build.run` orchestrator.

**Test gate**: `rake test`.

---

### 🟡 P-C — Add `data/index.yaml` Schema Version Migration Framework

**Priority**: MEDIUM  
**Risk**: LOW  
**Status**: OPEN

**Current state**: `data/index.yaml` declares `version: 3.0`. There is no `migrate_index_schema!(index)` method. If the schema changes, every tool that reads `index.yaml` must handle every historical schema version manually.

**Target**:
```ruby
# lib/rulepack/schema_migration.rb
module Rulepack
  module SchemaMigration
    CURRENT_VERSION = 3.0

    def self.migrate!(index)
      v = index[:version] || 1.0
      while v < CURRENT_VERSION
        case v
        when 1.0 then migrate_1_to_2!(index); v = 2.0
        when 2.0 then migrate_2_to_3!(index); v = 3.0
        else raise "Unknown schema version: #{v}"
        end
      end
      index[:version] = CURRENT_VERSION
    end

    def self.migrate_1_to_2!(index); ...; end  # e.g. add checksums.built field
    def self.migrate_2_to_3!(index); ...; end  # e.g. add pkg_type field
  end
end
```

Called from `installer.rb:load_master_index` and `build.rb` before any read of `index[:packages]`. Idempotent — safe to call on already-migrated data.

**Test gate**: Add unit test for `migrate_1_to_2!` with pre-2.0 fixture data → correct shape post-migration. `rake test`.

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
**Status**: OPEN

**Current state**: `query.rb` handles 7 subcommands (`list-packages`, `list-platforms`, `installed`, `show`, `search`, `check`, `orphans`) with mode-branching inside `run`.

**Target**: Replace the mode-switch with a dispatch table:
```ruby
COMMANDS = {
  'list-packages'  => method(:cmd_list_packages),
  'list-platforms' => method(:cmd_list_platforms),
  'installed'      => method(:cmd_installed),
  'show'           => method(:cmd_show),
  'search'         => method(:cmd_search),
  'check'          => method(:cmd_check),
  'orphans'        => method(:cmd_orphans),
  'provides'       => method(:cmd_provides),
}
```

Each `cmd_*` method is a small private method with a single `--platform` or `--json` concern.

**Test gate**: `rake test`.

---
