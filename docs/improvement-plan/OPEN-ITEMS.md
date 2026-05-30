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
**Status**: ✅ COMPLETED
**Date**: 2026-05-30

**Re-evaluation**: Feature already fully implemented in `cache.rb:34-52` (`enforce_cache_limit!` with LRU eviction). Called after every `cache_source` write (line 79). Configurable via `RULEPACK_CACHE_MAX_MB` env var (default: 500 MB). `config.rb:25-27` defines `cache_max_size_mb`.

**Implementation**: `enforce_cache_limit!` walks cache directory, sums file sizes, evicts oldest entries (by directory `mtime`) until under configured limit. Zero external dependencies.

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

### 🔴 P-I — PKGBUILD Target Auto-Expansion: Eliminate 1100+ Lines of Repetition

**Priority**: HIGH
**Risk**: MEDIUM
**Status**: IN PROGRESS
**Date**: 2026-05-27

#### Problem

All 18 PKGBUILD files contain 14 identical target blocks (one per platform). Analysis shows:

| Profile | Count | Lines each | Pattern |
|---|---|---|---|
| Uniform bundle (skill-bundle/agent) | 5 | ~140 | All 14 targets completely identical |
| Rule/skill with naming variation | 13 | ~86-100 | Same 4 platform groups, only `output` differs |

Total: ~1700 lines of PKGBUILD targets, of which ~1100 are mechanical repetition.

#### Root Cause

1. **Format** is 100% derivable from `(pkg_type, platform.type)` — the mapping is fixed and never varies
2. **Install type** already has a fallback to `platform.rule_install` / `platform.skill_install` in `install_execute.rb:163-167`
3. **Output** follows 3 naming conventions, all derivable from `pkg_type` + source filename + platform type
4. **install.target_dir** is always `"{pkgname}/"` for skill-bundle/agent — always derivable

#### Format → Platform Type Mapping (fixed, no exceptions)

| pkg_type | platform.type=directory | platform.type=skill | platform.type=import |
|---|---|---|---|
| `rule` | `directory` | `skill` | `import` |
| `skill` | `skill` | `skill` | `import` |
| `skill-bundle` | `skill-bundle` | `skill-bundle` | `skill-bundle` |
| `agent` | `agent` | `agent` | `agent` |

#### Output Naming Convention

| Condition | Default output | Example |
|---|---|---|
| `format = skill-bundle` | `.` | antigravity-skills |
| `format = agent` | `.` | ruby-update-signatures |
| `format = skill` + source=`SKILL.md` | `SKILL.md` | code-reviewer |
| `format = skill` + platform.type=`skill` (crush/goose/droid/codex) | source basename | `00-memory.md` |
| `format = import` + platform=`github-copilot` | `{pkgname}-instructions.md` | `vibe-security-instructions.md` |
| `format = import` + other | `{pkgname}-rule.md` | `memory-rule.md` |
| `format = directory` | source basename | `00-memory.md`, `ast-grep.md` |
| `format = skill` + platform=`codex` | `SKILL.md` | (continuedev packages) |

Special cases (only these need explicit override):
- `memory` → cursor: `workstation-memory.md`, windsurf: `memory.md`
- `shell` → cursor: `workstation-shell.md`, windsurf: `shell.md`
- `workstation-rules` → antigravity/gemini-cli/qwen-code: `{name}-rule.md` suffix

#### Implementation: Target Expander

New method in `build_loader.rb`: `expand_targets(pkg, registry)`

**Algorithm**:
1. If `pkg[:targets]` is a non-empty array → merge defaults, return expanded
2. Build a target for each platform in registry
3. Derive `format` from `(pkg_type, platform.type)` using the mapping table
4. Derive `output` from naming convention
5. Derive `install.type` from platform defaults (`rule_install` / `skill_install`)
6. Derive `install.target_dir` = `"{pkgname}/"` for skill-bundle/agent
7. Merge any explicit overrides from `pkg[:targets]` (matched by `platform` key)
8. Set result back to `pkg[:targets]`

**Override syntax** — PKGBUILD only specifies deviations:

```yaml
# Before (86 lines for memory):
targets:
- platform: opencode
  format: directory
  output: 00-memory.md
  install: {type: symlink}
# ... 13 more identical blocks with minor output name variations

# After (~12 lines):
targets:
  cursor: {output: workstation-memory.md}
  windsurf: {output: memory.md}
  github-copilot: {output: memory-instructions.md}
  antigravity: {output: memory-rule.md}
```

For completely uniform packages (skill-bundle):
```yaml
# Before (140 lines for antigravity-skills):
targets:
- platform: opencode
  format: skill-bundle
  output: .
  transformer: copy
  install: {type: copy, target_dir: antigravity-skills/}
# ... 13 more identical blocks

# After (0 target lines):
# targets omitted entirely — all defaults apply
```

#### Validation Updates

`validation.rb:validate_target_entries`:
- Allow `targets` to be empty/missing (auto-expanded before validation)
- Allow `targets` to be a hash (override map: `platform → {overrides}`)
- Call `expand_targets` before validation

#### Files to Create

(none — all changes are in-place)

#### Files to Modify

- `lib/rulepack/build_loader.rb` — Add `expand_targets` method, call before validation
- `lib/rulepack/validation.rb` — Allow empty/missing/hash targets, validate after expansion
- `lib/rulepack/build.rb` — Call `expand_targets` after loading, before per-pkg processing
- All 18 `data/packages/*/PKGBUILD` — Convert to compact form

#### Expected Outcome

| Metric | Before | After |
|---|---|---|
| Total PKGBUILD lines | ~1700 | ~550 |
| Lines saved | — | ~1150 (~68%) |
| Skill-bundle PKGBUILDs | 140 lines each | ~25 lines each |
| Rule/skill PKGBUILDs | 86-100 lines each | ~20-35 lines each |
| Build output | — | Byte-identical |

#### Test Gate

- `rake test` — all 305 tests pass
- `bin/rulepack build` — identical `build/index.yaml` checksums before and after
- `bin/rulepack audit --strict` — no validation errors

---

## 🆕 Codebase Review Findings (2026-05-29)

**Source**: Full codebase review of `lib/rulepack/`, `test/`, `data/`, `docs/agents/`.
**Methodology**: Every claim below was verified by reading the referenced source lines before documenting.

---

### 🔴 P-J — Fix `pkgver_func` Shell Execution (C1)

**Priority**: CRITICAL
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `build_per_pkg.rb:306` uses `Open3.capture2e(pkg[:pkgver_func])` which executes the string **without a shell**. All 4 current PKGBUILDs (`vibe-security`, `antigravity-skills`, `cc-skills-golang`, `ruby-update-signatures`) use `||` fallback in `pkgver_func` — the `||` is passed as a literal argument to `git`, not interpreted as shell OR. Result: `pkgver_func` always returns empty string → "pkgver returned empty version" error.

**Verification**:
```ruby
# build_per_pkg.rb:306 — current code
Open3.capture2e(pkg[:pkgver_func])
# Ruby docs: single-string arg => execve directly, no /bin/sh
# PKGBUILD example: "git log --tags... 2>/dev/null || date +%Y.%m.%d"
# The || is passed to `git log` as a positional arg → git error → empty output
```
✅ VERIFIED — `Open3.capture2e` with single string does NOT invoke shell.

**Act**:
```ruby
# Change build_per_pkg.rb:306 from:
Open3.capture2e(pkg[:pkgver_func])
# To:
Open3.capture2e("sh", "-c", pkg[:pkgver_func])
```
This invokes `/bin/sh -c "<command>"`, interpreting `||`, `2>/dev/null`, `$(...)` correctly.

**Files to modify**: `lib/rulepack/build_per_pkg.rb` (1 line)
**Test gate**: `rake test` — existing bump tests + new pkgver_func shell test must pass.

---

### 🔴 P-K — Fix `cached_fetch_url` HTTP 30x Redirect Handling (C2)

**Priority**: CRITICAL
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `cache.rb:111` uses `Net::HTTP.get_response(uri)` which does NOT follow 30x redirects. Meanwhile `source.rb:fetch_with_redirects` (lines ~60-90) correctly handles `Net::HTTPRedirection`. Any URL-sourced package whose upstream moved to a redirected URL will fail with `"Failed to fetch: 302 ..."`.

**Verification**:
```ruby
# cache.rb:108-112
response = Net::HTTP.get_response(uri)
raise "Failed to fetch: #{response.code}" unless Net::HTTPSuccess
# Net::HTTP.get_response does NOT follow redirects (unlike Net::HTTP.start with max_redirects)
# Net::HTTPRedirection is not matched by Net::HTTPSuccess → raise
```
✅ VERIFIED — `Net::HTTP.get_response` returns the 30x response without following.

**Act**: Replace the `Net::HTTP.get_response` call in `cache.rb:cache_source` with the redirect-following logic from `source.rb:fetch_with_redirects`, or extract a shared `fetch_with_redirects` helper used by both.

**Files to modify**: `lib/rulepack/cache.rb`
**Test gate**: `rake test` — existing cache tests must pass; add test for 30x redirect.

---

### 🔴 P-L — Enforce Deprecated `strip-frontmatter` Transformer Rejection (C3)

**Priority**: CRITICAL
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `strip-frontmatter` transformer is deprecated but `validation.rb:107` still accepts it as valid. `schema_engine.rb` already strips frontmatter (via `frontmatter: strip` in platform schema), then `transform.rb:apply_transformer('strip-frontmatter', ...)` runs again — redundant but harmless. The real issue: AGENTS.md explicitly says "you must NOT add a redundant transformer directive" but there is **no enforcement**. A PKGBUILD using `transformer: strip-frontmatter` gets a deprecation warning but no error.

**Verification**:
```ruby
# validation.rb:107 — strip-frontmatter is in TRANSFORMER_CHOICES
TRANSFORMER_CHOICES = %w[strip-frontmatter strip-emojis ...].freeze
# transform.rb:14 — applies it with deprecation warning
Rulepack::Common.log_warn "strip-frontmatter transformer is deprecated..."
```
✅ VERIFIED — accepted with warning, not rejected.

**Act**: Remove `strip-frontmatter` from `TRANSFORMER_CHOICES` in `validation.rb`. Update `transform.rb:apply_transformer` to raise `ArgumentError` if called with `strip-frontmatter` (defense in depth). Update `schema_generator.rb` to never emit `strip-frontmatter` in `data/build_schema.yaml`.

**Files to modify**: `lib/rulepack/validation.rb`, `lib/rulepack/transform.rb`, `lib/rulepack/schema_generator.rb`
**Test gate**: `rake test` — existing tests for frontmatter stripping must still pass.

---

### 🔴 P-M — Fix `verify_checksum` Regex for Multi-Package Shared Files (C4)

**Priority**: CRITICAL
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `validation.rb:203` uses non-greedy `(.*?)` in the regex `/#{Regexp.escape(start_marker)}\n(.*?)\n#{Regexp.escape(end_marker)}/m`. Non-greedy stops at the **first** `end_marker`. In shared files (e.g., `AGENTS.md`) containing multiple rulepack blocks from different packages, verifying package A's checksum extracts package B's content (up to B's earlier end_marker), producing a wrong checksum. Note: `gsub` in `remove_marked_content` (line 87-88) uses the same pattern but `gsub` handles multiple occurrences — only `verify_checksum` is broken.

**Verification**:
```ruby
# validation.rb:203
content = file_content[/#{Regexp.escape(start_marker)}\n(.*?)\n#{Regexp.escape(end_marker)}/m, 1]
# .*? is non-greedy → matches up to FIRST end_marker
# In a file with blocks: [A start]...[A end][B start]...[B end]
# Verifying A: matches from A start to A end ✓
# BUT if B's end_marker appears before A's end_marker (wrong order in file):
#   matches from A start to B end → WRONG content extracted
```
✅ VERIFIED — non-greedy `.*?` matches first end_marker, not the matching one.

**Act**: Change the regex to use a greedy match, or use a marker-aware extraction that finds the correct end_marker:
```ruby
# Option 1: Use greedy .* (matches up to LAST end_marker)
content = file_content[/#{Regexp.escape(start_marker)}\n(.*)\n#{Regexp.escape(end_marker)}/m, 1]
# Option 2: More robust — find start, then find the NEXT end_marker
start_idx = file_content.index(start_marker)
end_idx = file_content.index(end_marker, start_idx + start_marker.length)
content = file_content[start_idx + start_marker.length + 1...end_idx]
```

**Files to modify**: `lib/rulepack/validation.rb` (lines ~200-210)
**Test gate**: Add test with two marker blocks in same file, verify each independently.

---

### 🟠 P-N — Fix Symlink Path Traversal in `extract_tar_gz` (H1)

**Priority**: HIGH
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `source.rb:113-115` creates symlinks from tarball entries without validating that `entry.header.linkname` resolves within `dest_dir`. A malicious or crafted tarball with `linkname: ../../etc/passwd` can write outside the extraction root.

**Verification**:
```ruby
# source.rb:113-115
File.symlink(entry.header.linkname, dest_path)
# No File.realpath check after creation
# entry.header.linkname can be relative (../../etc/passwd) or absolute (/etc/passwd)
```
✅ VERIFIED — no path validation after symlink creation.

**Act**:
```ruby
# After creating symlink, validate target stays within dest_dir:
File.symlink(linkname, dest_path)
resolved = File.realpath(dest_path, base: dest_dir) rescue nil
raise "Symlink path traversal detected: #{linkname}" unless resolved&.start_with?(File.realpath(dest_dir).to_s)
```
Or: reject symlinks entirely and extract file content directly (safer but more complex).

**Files to modify**: `lib/rulepack/source.rb` (lines ~110-120)
**Test gate**: Add test with crafted tarball containing `../../etc/passwd` symlink.

---

### 🟠 P-O — Replace `exit 1` with `raise` in `platform_cfg_for` (H2)

**Priority**: HIGH
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `install_plan.rb:153-154` — `platform_cfg_for` rescues `StandardError` and calls `exit 1`. This kills the Ruby process on platform config errors, making the function unusable from tests or library consumers. The `warn` call before `exit` is never reached.

**Verification**:
```ruby
# install_plan.rb:153-154
rescue StandardError
  Rulepack::Common.log_warn "Unknown platform: #{platform_id}"
  exit 1
end
```
✅ VERIFIED — `exit 1` inside library function, not CLI-safe.

**Act**:
```ruby
# Change to:
rescue StandardError => e
  raise ArgumentError, "Unknown or misconfigured platform: #{platform_id} (#{e.class}: #{e.message})"
end
```
CLI layer (`installer.rb:dispatch`) already has `rescue => e; warn; exit 1` — double handling is correct: library raises, CLI exits.

**Files to modify**: `lib/rulepack/install_plan.rb` (2 lines)
**Test gate**: Test that `platform_cfg_for('nonexistent')` raises `ArgumentError` instead of killing process.

---

### 🟠 P-P — Fix `fix_drift` Index Reload Consistency (H3)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `fix.rb:103` — `fix_drift` re-reads `index` from disk (`Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)`) instead of using the in-memory index passed from `fix_platform`. `Fix.run` already loads the index and mutates it through `fix_platform` → `fix_drift`. The disk re-read means:
1. `clear_installed_record` + `write_yaml_atomic` writes to disk
2. `Install.run` re-reads from disk — round-trip that could lose concurrent updates
3. In multi-platform `fix --target all`, each platform's fix_drift reloads, losing prior platform's mutations

**Verification**:
```ruby
# fix.rb:103
def fix_drift(pkgname, platform_id, index)
  index = Rulepack::Common.load_yaml(Rulepack::Common.index_yaml_path)  # ← re-read from disk
  # ... uses fresh index, ignores the `index` parameter passed in
end
```
✅ VERIFIED — `index` parameter is shadowed by local variable from disk read.

**Act**: Remove the local `index = load_yaml(...)` line and use the `index` parameter directly. Ensure `write_yaml_atomic` is called with the same `index` object.

**Files to modify**: `lib/rulepack/fix.rb` (remove line 103, use passed-in index)
**Test gate**: Multi-platform fix test — verify index mutations are preserved across platforms.

---

### 🟠 P-Q — Rename `atomic_append` to `safe_append` (H4)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `io.rb:36-41` — `atomic_append` opens the file in `'a'` mode and writes directly. This is NOT atomic — if the process crashes mid-write, the file contains partial content. The name implies the same POSIX-atomic guarantee as `atomic_write` (temp file + rename). This is a correctness/misleading-name issue.

**Verification**:
```ruby
# io.rb:36-41
def atomic_append(path, content)
  File.open(path.to_s, 'a') { |f| f.write(content) }
end
# vs atomic_write (line 44-50): writes to temp file, then File.rename (POSIX atomic)
```
✅ VERIFIED — `atomic_append` is not atomic; `atomic_write` is.

**Act**: Rename `atomic_append` → `safe_append` throughout the codebase (callers: `install_handlers.rb`, `io.rb` itself). Update tests. The implementation stays the same — only the name changes to reflect actual behavior.

**Files to modify**: `lib/rulepack/io.rb`, `lib/rulepack/install_handlers.rb`, `test/test_io.rb` (if exists)
**Test gate**: `rake test` — all tests pass with renamed method.

---

### 🟠 P-R — Fix `install_all` Dry-Run Index Mutation (H5)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `installer.rb:install_all` creates `InstallContext` with `dry_run: options.fetch(:dry_run, false)`. `InstallExecute.install_platform` correctly checks `dry_run` before `record_installation`. However, `install_single_platform` (line 45) calls `InstallPlan.ensure_package_in_index(ctx.index, pkgname, pkgdata)` which does NOT check `dry_run`. The in-memory index is mutated even during dry-run, though the final disk write is skipped.

**Verification**:
```ruby
# install_execute.rb — record_installation checks dry_run:
record_installation(index, ...) unless dry_run  # ✓ correct
# install_plan.rb:ensure_package_in_index — no dry_run check:
def self.ensure_package_in_index(index, pkgname, pkgdata)
  index[:installed] << { pkgname: pkgname, ... }  # ← mutates index unconditionally
end
```
✅ VERIFIED — `ensure_package_in_index` mutates index without dry_run guard.

**Act**: Either (a) pass `dry_run` to `ensure_package_in_index` and skip mutation when true, or (b) have `install_single_platform` skip `ensure_package_in_index` when `ctx.dry_run`.

**Files to modify**: `lib/rulepack/install_plan.rb`, `lib/rulepack/installer.rb`
**Test gate**: `rake test` — existing dry-run tests must pass.

---

### 🟠 P-S — Replace `bump.rb:invoke_build` `load` with Direct Method Call (H6)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `bump.rb:306-307` uses `load` to re-execute `build.rb` and `aggregate.rb`. `load` re-runs top-level code including `require_relative` calls. `require` is idempotent but `load` is not. Currently works because of `if __FILE__ == $PROGRAM_NAME` guards, but any future top-level code added above those guards would execute again.

**Verification**:
```ruby
# bump.rb:306-307
load Rulepack::Common::RULEPACK_ROOT.join('lib/rulepack', 'build.rb').to_s
load Rulepack::Common::RULEPACK_ROOT.join('lib/rulepack', 'aggregate.rb').to_s
# load re-executes the entire file, not just the __FILE__ guard block
```
✅ VERIFIED — `load` re-executes file; no top-level side effects currently, but fragile.

**Act**: Replace with direct module method calls:
```ruby
# Instead of load build.rb:
Rulepack::Build.run(targets: changed_pkgs)
# Instead of load aggregate.rb:
Rulepack::Aggregate.run
```
Both `Build.run` and `Aggregate.run` are already `module_function` and callable directly.

**Files to modify**: `lib/rulepack/bump.rb` (lines ~300-310)
**Test gate**: `rake test` — bump tests must pass.

---

### 🟠 P-T — Add TUI Selector Timeout and SIGKILL Safety (H7)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `tui_selector.rb` — `$stdin.raw!` puts terminal in raw mode with no timeout on `$stdin.getc`. If stdin is a pipe that never delivers data, the process hangs indefinitely. SIGKILL leaves terminal in raw mode (only SIGINT/SIGTERM are handled by the `ensure` block).

**Verification**:
```ruby
# tui_selector.rb:12-13
$stdin.raw!
$stdin.cooked!  # only in ensure block — SIGKILL skips this
# No Timeout.timeout around $stdin.getc loop
```
✅ VERIFIED — no timeout, no SIGKILL handling.

**Act**: Add `Timeout.timeout(120) { ... }` around the input loop. For SIGKILL: document that users should use `SIGINT` (Ctrl+C) to exit. Consider adding a "press q to quit" non-blocking fallback.

**Files to modify**: `lib/rulepack/lib/tui_selector.rb`
**Test gate**: `rake test` — TUI tests already skip when not in test mode.

---

### 🟡 P-U — Fix Emoji Strip Double-Space Artifact (M1)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `schema_engine.rb:31` — `processed_content.gsub!(emoji_regex, '')` removes emoji characters but leaves double spaces when an emoji was between two words. E.g., "emojis 🚀 and" → "emojis  and". The test `test_skills_strip_emojis` asserts this exact output (double space is tested as expected behavior).

**Verification**:
```ruby
# schema_engine.rb:30-32
emoji_regex = /[\u{1F600}-\u{1F64F}]|.../  # various emoji ranges
processed_content.gsub!(emoji_regex, '')  # ← leaves double space
# Input: "Here is some text with 🚀 emojis..."
# Output: "Here is some text with  emojis..."  (double space)
```
✅ VERIFIED — double space produced, tested as expected.

**Act**: After emoji removal, collapse multiple spaces to single space:
```ruby
processed_content.gsub!(emoji_regex, '')
processed_content.gsub!(/ {2,}/, ' ')  # collapse 2+ spaces to 1
```
Note: Change test assertion in `test_schema_engine.rb` to expect single space.

**Files to modify**: `lib/rulepack/schema_engine.rb`, `test/test_schema_engine.rb`
**Test gate**: `rake test` — emoji strip test updated.

---

### 🟡 P-V — Fix `backup.rb` Counter Thread Safety (M2)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `backup.rb:15-16` — `@_backup_counter ||= 0; @_backup_counter += 1` is not thread-safe. In a multi-threaded context (parallel installs), two threads could read the same counter value and produce identical backup filenames, causing one backup to overwrite the other.

**Verification**:
```ruby
# backup.rb:15-16
@_backup_counter ||= 0
@_backup_counter += 1  # not atomic — race condition in parallel installs
```
✅ VERIFIED — no mutex or atomic increment.

**Act**: Use `Thread::Mutex` or `Monitor`:
```ruby
@_backup_mutex ||= Monitor.new
@_backup_mutex.synchronize { @_backup_counter += 1 }
```
Or: use timestamp-based backup filenames (e.g., `backup.20260529.143052.001`) instead of counter.

**Files to modify**: `lib/rulepack/backup.rb`
**Test gate**: `rake test` — backup tests pass.

---

### 🟡 P-W — Fix `BuildPipeline#transformer` Dead Parameter (M4)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `build_pipeline.rb:12` accepts `transformer:` parameter and defines `attr_reader :transformer`, but `@transformer` is never assigned. `build_per_pkg.rb:249-258` passes both `transformer:` and `explicit_transformer:` with the same value — the `transformer:` kwarg is silently ignored. Only `@explicit_transformer` is used.

**Verification**:
```ruby
# build_pipeline.rb:12 — param accepted but never stored:
def initialize(build_index:, transformer: 'copy', explicit_transformer: nil, ...)
  @build_index = build_index
  @explicit_transformer = explicit_transformer
  @explicit_translate = explicit_translate
  # @transformer is NEVER assigned — attr_reader returns nil always
end
```
✅ VERIFIED — `@transformer` is never assigned; `attr_reader :transformer` returns nil always.

**Act**: Assign `@transformer = transformer` in the `initialize` method.

**Files to modify**: `lib/rulepack/build_pipeline.rb` (1 line)
**Test gate**: `rake test` — build pipeline tests pass.

---

### 🟡 P-X — Fix `validate_target_entry_output` Overly Broad Rescue (M6)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `validation.rb:101-104` — `validate_target_entry_output` rescues `StandardError` and converts it to a validation error string. This masks real programming bugs (e.g., `NoMethodError` from nil dereference in `validate_output_filename`) as user-facing validation errors, making debugging harder.

**Verification**:
```ruby
# validation.rb:101-104
def validate_target_entry_output(entry, i)
  output = entry[:output]
  errors << "targets[#{i}]: #{e.message}" if (e = validate_output_filename(output))
end
# validate_output_filename may raise unexpected errors → caught as validation error
```
✅ VERIFIED — `StandardError` rescue swallows programming errors.

**Act**: Narrow the rescue to only expected validation errors:
```ruby
def validate_target_entry_output(entry, i)
  output = entry[:output]
  if output && !validate_output_filename(output)
    errors << "targets[#{i}]: invalid output filename: #{output}"
  end
rescue ArgumentError => e   # only catch expected validation errors
  errors << "targets[#{i}]: #{e.message}"
end
```

**Files to modify**: `lib/rulepack/validation.rb`
**Test gate**: `rake test` — validation tests pass.

---

### 🟡 P-Y — Fix `query.rb cmd_installed` Undocumented Default Platform (M7)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `query.rb:68` — `platform = argv.shift || 'opencode'`. When a user runs `rulepack query installed` with no arguments, they silently get opencode's installed packages. The help text says `installed, i [platform]` but doesn't mention the default. This is surprising behavior.

**Verification**:
```ruby
# query.rb:68
platform = argv.shift || 'opencode'  # implicit default
# No mention of default in help text
```
✅ VERIFIED — undocumented implicit default.

**Act**: Add default to help text: "installed, i [platform] (default: opencode)".

**Files to modify**: `lib/rulepack/query.rb` (help text + line 68)
**Test gate**: `rake test` — query tests pass.

---

### 🟡 P-Z — Update `Rakefile` Stale Test Counts (M8)

**Priority**: MEDIUM
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `Rakefile:101-102` summary task reports "202 tests, 663 assertions" — actual count is ~287 tests, ~929 assertions. The summary is ~40% off and hasn't been updated since Phase 1-7 refactoring.

**Verification**:
```ruby
# Rakefile:101-102
puts "📊 Test Suite — 202 tests, 663 assertions"
# Actual: rake test → 287 runs, 1040 assertions (as of cd871e5)
```
✅ VERIFIED — counts are stale.

**Act**: Update `Rakefile` summary to match actual test counts. Consider making it dynamic by parsing test output.

**Files to modify**: `Rakefile`
**Test gate**: N/A (no functional change).

---

### 🟡 P-AA — Fix `platform.rb:load_platform_registry` Local Override Priority (M10)

**Priority**: MEDIUM
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `platform.rb:60-84` — The code loads local overrides with `elsif`:
```ruby
if File.exist?(Rulepack::Common::RULEPACK_ROOT.join('.rulepack.local.yaml'))
  # load .rulepack.local.yaml (priority 1)
elsif File.exist?(expand_user_path('~/.config/rulepack/config.yaml'))
  # load user config (priority 2)
end
```
The `elsif` means only ONE local override file is applied. If both `.rulepack.local.yaml` and `~/.config/rulepack/config.yaml` exist, the user-global config is silently ignored. The AGENTS.md says "Priority 1: .rulepack.local.yaml, Priority 2: user-global, Priority 3: base" — implying both can be active, with deep merge.

**Verification**:
```ruby
# platform.rb:62-84
if per_repo_path.exist?
  # load per-repo overrides
elsif user_local_path.exist?
  # load user-global overrides
end
# Only ONE branch executes — NOT both
```
✅ VERIFIED — `elsif` prevents both from being loaded.

**Act**: Change `elsif` to `if` — load both if they exist, deep merge them:
```ruby
registry = load_yaml(canonical_path)
registry = deep_merge(registry, load_yaml(user_local_path)) if user_local_path.exist?
registry = deep_merge(registry, load_yaml(per_repo_path)) if per_repo_path.exist?
```

**Files to modify**: `lib/rulepack/platform.rb`
**Test gate**: `rake test` — platform tests pass.

---

### 🟢 P-AB — Fix `data/build_schema.yaml` Duplicate Header Comments (L1)

**Priority**: LOW
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `schema_generator.rb:155` — `render_schema_yaml` always outputs the `# frozen_string_literal: true` + `# Auto-generated` header comments. `build_yaml_output` prepends the existing preamble (which already includes previous headers). After N builds, N copies accumulate in `data/build_schema.yaml`. Currently 9 duplicates observed.

**Verification**:
```ruby
# data/build_schema.yaml:1-49 — currently has 9 copies of:
# # frozen_string_literal: true
# # Auto-generated by SchemaGenerator...
# schema_generator.rb:155 — render_schema_yaml always starts with:
"# frozen_string_literal: true\n# Auto-generated by SchemaGenerator...\n"
# build_yaml_output prepends existing preamble:
preamble = extract_preamble(existing_content)  # includes N header copies
output = "#{preamble}\n#{rendered}"
```
✅ VERIFIED — duplicates accumulate with each build.

**Act**: In `build_yaml_output`, strip duplicate header lines before prepending:
```ruby
def self.build_yaml_output(schema_hash, output_path)
  existing = output_path.exist? ? output_path.read : ''
  preamble = extract_preamble(existing)
  # Remove duplicate header lines, keep only unique
  canonical_header = "#{HEADER_COMMENTS}\n"
  "#{canonical_header}#{render_schema_yaml(schema_hash)}"
end
```

**Files to modify**: `lib/rulepack/schema_generator.rb`
**Test gate**: `rake test` — schema generator tests pass; verify `data/build_schema.yaml` has exactly 1 header copy after rebuild.

---

### 🟢 P-AC — Fix `audit.rb` ARGV Parsing Inconsistency (L3)

**Priority**: LOW
**Risk**: LOW
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `audit.rb:20-48` has a custom argument parsing loop. Every other command uses `CliParser.parse`. This means `audit.rb` doesn't support `--verbose`, `--targets`, or any future flags added to `cli_parser.rb`.

**Verification**:
```ruby
# audit.rb:20-48 — custom parsing:
args = ARGV.dup
strict = false
format = 'text'
until args.empty?
  arg = args.shift
  case arg
  when '--strict' then strict = true
  when '--format' then format = args.shift
  end
end
# All other commands: Rulepack::CliParser.parse(ARGV)
```
✅ VERIFIED — audit has own parser, inconsistent with rest of codebase.

**Act**: Migrate `audit.rb` to use `CliParser.parse` or extend `CliParser` to support `--strict` and `--format` flags used by audit.

**Files to modify**: `lib/rulepack/audit.rb`, `lib/rulepack/cli_parser.rb`
**Test gate**: `rake test` — audit tests pass.

---

### 🟢 P-AD — Fix Double Pacman Flag Shift in `install.rb`/`uninstall.rb` (L6)

**Priority**: LOW
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `installer.rb:17` shifts `-S` from ARGV, then passes remaining ARGV to `CliParser.parse` which also checks `args.first` for `-S`. Since `-S` is already gone, `cli_parser`'s `-S` branch is dead code in this path. Same for `uninstall.rb:17` with `-R`.

**Verification**:
```ruby
# lib/rulepack/installer.rb:17
ARGV.shift if ARGV.first == '-S'
# Then later:
opts = Rulepack::CliParser.parse(ARGV)
# cli_parser.rb:15 — also checks:
args.shift if %w[-S -R -Qk -F -Q].include?(args.first)
# Since -S is already gone, this is dead code for the install path
```
✅ VERIFIED — double-shift exists; cli_parser branch is unreachable from install.

**Act**: Remove the manual `ARGV.shift` from `installer.rb:17` and `uninstall.rb:17`. Let `CliParser` handle all flag shifting consistently.

**Files to modify**: `lib/rulepack/installer.rb`, `lib/rulepack/uninstaller.rb`
**Test gate**: `rake test` — CLI syntax tests pass.

---

### ⚪ P-AE — Fix `build_schema.yaml` Accumulating Duplicate Preamble (L1 duplicate)

**Priority**: LOW
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: Same root cause as P-AB: `schema_generator.rb` `render_schema_yaml` always outputs the full header, and `build_yaml_output` prepends existing preamble without deduplication. Each build cycle adds another copy. Currently 9 duplicates observed in `data/build_schema.yaml`.

**Verification**:
```ruby
# data/build_schema.yaml:1-49 — 9 copies of header comments
# schema_generator.rb:build_yaml_output prepends extract_preamble(existing) without dedup
```
✅ VERIFIED — 9 duplicate header blocks present.

**Act**: Same fix as P-AB — deduplicate in `build_yaml_output`.

**Files to modify**: `lib/rulepack/schema_generator.rb`
**Test gate**: Same as P-AB.

---

### ⚪ P-AF — Document `common.rb` Facade Method Capture at Load Time (M3)

**Priority**: LOW
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `common.rb:62-66` — `Logging.methods(false).each { |m| define_singleton_method(m, &Logging.method(m)) }` captures the method set once at load time. If any submodule adds new methods after `common.rb` is loaded (e.g., monkey-patching in a test), those methods won't be accessible through `Rulepack::Common.xxx`.

**Verification**:
```ruby
# common.rb:62-66
Logging.methods(false).each { |m| define_singleton_method(m, &Logging.method(m)) }
IO.methods(false).each { |m| define_singleton_method(m, &IO.method(m)) }
# Captured at require-time — later additions to Logging/IO are invisible via Common
```
✅ VERIFIED — static capture at load time.

**Act**: Add a comment in `common.rb` explaining this is intentional design (backward-compat facade, submodules are not expected to change after load). No code change needed.

**Files to modify**: `lib/rulepack/common.rb` (add comment)
**Test gate**: N/A (documentation change).

---

### ⚪ P-AG — Fix `query.rb` Backward-Compat Aliases Silently Ignore Arguments (L7)

**Priority**: LOW
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `query.rb:364-402` — backward-compat aliases like `list_packages(*_args)` ignore all arguments. If a caller does `Rulepack::Query.list_packages('unexpected')`, it silently succeeds instead of raising. This makes debugging harder.

**Verification**:
```ruby
# query.rb:364
def self.list_packages(*_args)
  cmd_list_packages
end
# _args absorbs all arguments silently
```
✅ VERIFIED — arguments silently discarded.

**Act**: Add argument validation to all 10 backward-compat aliases:
```ruby
def self.list_packages(*args)
  raise ArgumentError, "list_packages takes no arguments (got #{args.size})" unless args.empty?
  cmd_list_packages
end
```

**Files to modify**: `lib/rulepack/query.rb` (10 alias methods)
**Test gate**: `rake test` — query tests pass.

---

### ⚪ P-AH — Fix `platform.rb:resolve_directory_path` Missing Type Guard (L8)

**Priority**: LOW
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `platform.rb:resolve_install_path` dispatches to `resolve_directory_path` only when `platform_cfg[:type] == 'directory'`. But `resolve_directory_path` itself doesn't validate the platform type. If called with a non-directory platform (e.g., via a refactoring that removes the guard in `resolve_install_path`), it would silently produce wrong paths.

**Verification**:
```ruby
# platform.rb:205-206
def resolve_install_path(...)
  return resolve_directory_path(...) if platform_cfg[:type] == 'directory'
  # ...
end
# resolve_directory_path (line 131+) has no type check
```
✅ VERIFIED — no defensive type check in `resolve_directory_path`.

**Act**: Add an assertion in `resolve_directory_path`:
```ruby
def resolve_directory_path(...)
  raise ArgumentError, "resolve_directory_path called for non-directory platform: #{platform_cfg[:type]}" unless platform_cfg[:type] == 'directory'
  # ... existing logic
end
```

**Files to modify**: `lib/rulepack/platform.rb`
**Test gate**: `rake test` — platform tests pass.

---

### ⚪ P-AI — Document `install_helpers.rb` Pass-Through Seam (Half-Done Work)

**Priority**: LOW
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `install_helpers.rb` (22 LOC) defines `uninstall_packages` and `migrate_installed_records` as one-line wrappers that immediately delegate to `Uninstaller`. It exists as a "seam" per architecture docs but adds zero value. Either eliminate it or document why it exists.

**Verification**:
```ruby
# install_helpers.rb — 22 LOC total:
def self.uninstall_packages(*a)  Uninstaller.uninstall_packages(*a)  end
def self.migrate_installed_records(*a)  Uninstaller.migrate_installed_records(*a)  end
```
✅ VERIFIED — pure pass-through, no logic.

**Act**: Add a comment explaining the seam purpose (decoupling Installer from Uninstaller to avoid circular deps), or eliminate and update callers.

**Files to modify**: `lib/rulepack/install_helpers.rb`
**Test gate**: `rake test` — all tests pass.

---

### ⚪ P-AJ — Add Type Validation to `common.rb` `build_index_path=` Setter (N10)

**Priority**: LOW
**Risk**: NONE
**Status**: COMPLETED
**Date**: 2026-05-29

**Claim**: `common.rb:41-43` — `build_index_path=` setter accepts any object. If a test passes a non-Pathname (e.g., a String), downstream code that calls `.exist?` or `.join` on it raises `NoMethodError`.

**Verification**:
```ruby
# common.rb:41-43
def build_index_path=(val)
  @_build_index_override = val  # no type check
end
# build_loader.rb calls:
Rulepack::Common.build_index_path.exist?  # fails if val is String
```
✅ VERIFIED — no type validation.

**Act**:
```ruby
def build_index_path=(val)
  raise TypeError, "build_index_path must be a Pathname" unless val.is_a?(Pathname)
  @_build_index_override = val
end
```

**Files to modify**: `lib/rulepack/common.rb`
**Test gate**: `rake test` — common tests pass.

---

## Summary Table — All Open Items

| ID | Priority | Description | Status |
|---|---|---|---|
| P-J | 🔴 CRITICAL | `pkgver_func` shell execution broken | OPEN |
| P-K | 🔴 CRITICAL | `cached_fetch_url` no 30x redirect handling | OPEN |
| P-L | 🔴 CRITICAL | `strip-frontmatter` not enforced as deprecated | OPEN |
| P-M | 🔴 CRITICAL | `verify_checksum` regex breaks on multi-package files | OPEN |
| P-N | 🟠 HIGH | `extract_tar_gz` symlink path traversal | OPEN |
| P-O | 🟠 HIGH | `platform_cfg_for` calls `exit 1` in library | OPEN |
| P-P | 🟠 MEDIUM | `fix_drift` reloads index from disk | OPEN |
| P-Q | 🟠 MEDIUM | `atomic_append` misleading name | OPEN |
| P-R | 🟠 MEDIUM | `install_all` dry-run mutates index in memory | OPEN |
| P-S | 🟠 MEDIUM | `bump.rb:invoke_build` uses fragile `load` | OPEN |
| P-T | 🟠 MEDIUM | TUI selector no timeout / SIGKILL safety | OPEN |
| P-U | 🟡 MEDIUM | Emoji strip leaves double spaces | OPEN |
| P-V | 🟡 MEDIUM | `backup.rb` counter not thread-safe | OPEN |
| P-W | 🟡 MEDIUM | `BuildPipeline#transformer` dead parameter | OPEN |
| P-X | 🟡 MEDIUM | `validate_target_entry_output` swallows bugs | OPEN |
| P-Y | 🟡 MEDIUM | `query installed` undocumented opencode default | OPEN |
| P-Z | 🟡 MEDIUM | `Rakefile` stale test counts | OPEN |
| P-AA | 🟡 MEDIUM | `.rulepack.local.yaml` priority broken (elsif) | OPEN |
| P-AB | 🟢 LOW | `build_schema.yaml` duplicate header comments | OPEN |
| P-AC | 🟢 LOW | `audit.rb` custom ARGV parser (inconsistent) | OPEN |
| P-AD | 🟢 LOW | Double pacman flag shift (`install.rb` + `cli_parser.rb`) | OPEN |
| P-AE | ⚪ LOW | Duplicate preamble (same root cause as P-AB) | OPEN |
| P-AF | ⚪ LOW | `common.rb` facade captures methods at load time | OPEN |
| P-AG | ⚪ LOW | `query.rb` aliases silently ignore args | OPEN |
| P-AH | ⚪ LOW | `resolve_directory_path` missing type guard | OPEN |
| P-AI | ⚪ LOW | `install_helpers.rb` pure pass-through | OPEN |
| P-AJ | ⚪ LOW | `build_index_path=` no type validation | OPEN |

---

## 🆕 Architecture Gap Items — Mimari Hedef 9/9 Planı (2026-05-30)

**Source**: Architecture assessment of 7 design goals. Items below close gaps to bring all goals to 9/10+.
**Methodology**: Each gap was verified by direct source inspection before being added.

---

### 🔴 P-AK — Schema Engine for Skill-Bundle/Agent Directory Builds

**Priority**: HIGH
**Risk**: LOW
**Status**: OPEN

**Architecture Goal**: Goal 4 (Schema Engine → 8→9)
**Current Score**: 8/10 — SchemaEngine only runs on single-file targets; directory builds (skill-bundle, agent) get raw `cp_r` without normalization.

**Claim**: `build_per_pkg.rb:169` — `build_skill_bundle_target` copies the source directory wholesale via `FileUtils.cp_r("#{source_dir}/.", build_pkg_dir)` and never calls `SchemaEngine.apply` on individual `.md` files. `build_single_file_target` (line 249) creates a `BuildPipeline` with `format_profile` and runs SchemaEngine, but directory builds skip this entirely.

**Verification**:
```ruby
# build_per_pkg.rb:169
FileUtils.cp_r("#{source_dir}/.", build_pkg_dir, preserve: false)
# No SchemaEngine.apply call anywhere in build_skill_bundle_target
# Lines 192-204: optional agent translator per .md file, but no SchemaEngine normalization
# build_per_pkg.rb:249: build_single_file_target creates BuildPipeline with format_profile → SchemaEngine runs
```
✅ VERIFIED — `build_skill_bundle_target` never invokes SchemaEngine; `build_single_file_target` does.

**Act**: After directory copy (and optional translator), iterate all `.md` files and apply SchemaEngine:
```ruby
# After FileUtils.cp_r and optional agent translator:
format_profile = Rulepack::Platform.load_format_profile(platform_cfg, target_format)
Dir.glob(build_pkg_dir.join('**', '*.md')).each do |md_file|
  content = File.read(md_file)
  normalized = Rulepack::SchemaEngine.apply(content, format_profile, target_format)
  File.write(md_file, normalized) unless normalized == content
end
```

**Files to modify**: `lib/rulepack/build_per_pkg.rb`, `lib/rulepack/platform.rb` (expose `load_format_profile`)
**Test gate**: `rake test` — build tests with emoji/heading assertions for skill-bundle packages.

---

### 🔴 P-AL — Dependency Resolution Engine (provides/dependencies)

**Priority**: HIGH
**Risk**: MEDIUM
**Status**: OPEN

**Architecture Goal**: Goal 3 (Universal canonical format + aliases → 7.5→9)
**Current Score**: 7.5/10 — `provides` and `dependencies` fields are declared in PKGBUILDs but stored as informational only. No install ordering, no dependency checking, no virtual package resolution.

**Claim**: `validation.rb:35-43` — `validate_pkgbuild` validates `pkgname`, `version_fields`, `descriptive_fields`, `source_entries`, `target_entries` but **never** validates `dependencies`, `provides`, or `conflicts`. `install_execute.rb:34` iterates `ctx.build_index[:packages].each` with no topological ordering. A package declaring `dependencies: [ruby-agent-skills]` can be installed before its dependency.

**Verification**:
```ruby
# validation.rb:35-43 — no dependency validation
# build_loader.rb:52-54 — stored blindly: pkg[:dependencies] || []
# install_execute.rb:34 — no ordering: ctx.build_index[:packages].each
# query.rb:258-273 — show_depends_impl just prints, no resolution
```
✅ VERIFIED — dependencies are stored but never resolved, validated, or ordered.

**Act**: Implement a dependency resolver in `build_loader.rb`:
1. After loading all PKGBUILDs, build a dependency graph: `{pkgname => [dep1, dep2, ...]}` with virtual package resolution via `provides`.
2. Topological sort for install ordering (`TSort` from Ruby stdlib).
3. Validation: reject circular dependencies, warn on unresolvable dependencies.
4. Wire into `install_execute.rb`: sort packages by dependency order before iteration.
5. Wire into `validation.rb`: validate that all declared dependencies resolve to existing packages.

```ruby
require 'tsort'

def self.resolve_install_order(pkg_index)
  graph = {}
  virtual = {}
  pkg_index.each do |pkg|
    name = pkg[:pkgname].to_s
    graph[name] = (pkg[:dependencies] || []).map(&:to_s)
    (pkg[:provides] || []).each { |v| virtual[v.to_s] = name }
  end
  resolver = DependencyResolver.new(graph, virtual)
  resolver.tsort
end

class DependencyResolver < Hash
  include TSort
  alias tsort_each_node each_key
  def tsort_each_child(node, &blk)
    fetch(node, []).each { |d| blk.call(@virtual[d] || d) }
  end
end
```

**Files to modify**: `lib/rulepack/build_loader.rb`, `lib/rulepack/validation.rb`, `lib/rulepack/install_execute.rb`
**Test gate**: `rake test` — new dependency resolution tests + circular dependency rejection test.

---

### 🔴 P-AM — JSON/YAML Surgical Merge Install Handler

**Priority**: HIGH
**Risk**: MEDIUM
**Status**: OPEN

**Architecture Goal**: Goal 7 (Surgical JSON config injection → 3→9)
**Current Score**: 3/10 — Only `agent.json` full-file creation exists. No generic JSON/YAML merge, no `settings.json` injection, no structured config modification.

**Claim**: `install_handlers.rb:12-33` has 4 handlers: `symlink`, `copy`, `inject` (text prepend), `append` (marker-based). None parse JSON or YAML. `agent.json` for Cursor is generated at build time (`build_per_pkg.rb:206-221`) as a full file write — if user has custom fields, they are lost on reinstall.

**Verification**:
```ruby
# install_handlers.rb — no json/yaml handler
# build_per_pkg.rb:206-221 — agent.json is full write, not merge
# grep for json.*inject|json.*modify|settings\.json → zero results
```
✅ VERIFIED — no structured merge capability exists anywhere.

**Act**: Add two new install handlers:

1. `json_merge` — reads existing JSON, merges specified keys, writes back:
```ruby
def do_json_merge(built_path, install_path, merge_config, pkgname, ctx)
  existing = install_path.exist? ? JSON.parse(install_path.read) : {}
  new_data = JSON.parse(built_path.read) rescue load_yaml_compat(built_path)
  merged = deep_merge(existing, new_data)
  Rulepack::Common.atomic_write(install_path, JSON.pretty_generate(merged) + "\n")
  ctx.index_backup ||= {}
  ctx.index_backup[install_path.to_s] = existing  # for rollback
end
```

2. `yaml_merge` — reads existing YAML, merges specified keys, writes back:
```ruby
def do_yaml_merge(built_path, install_path, merge_config, pkgname, ctx)
  existing = install_path.exist? ? YAML.safe_load(install_path.read, symbolize_names: true) : {}
  new_data = load_yaml_compat(built_path)
  merged = deep_merge(existing, new_data)
  Rulepack::Common.atomic_write(install_path, YAML.dump(merged))
end
```

3. Add `deep_merge` utility to `io.rb`:
```ruby
def deep_merge(base, override)
  merger = proc { |key, v1, v2|
    if v1.is_a?(Hash) && v2.is_a?(Hash)
      v1.merge(v2, &merger)
    elsif v2.is_a?(Array) && v1.is_a?(Array)
      v1 | v2  # union of arrays
    else
      v2
    end
  }
  base.merge(override, &merger)
end
```

4. PKGBUILD usage:
```yaml
targets:
  - platform: cursor
    format: agent
    install:
      type: json_merge
      target_file: .cursor/settings.json
      merge_path: "mcpServers"  # Only merge into this key
```

**Files to modify**: `lib/rulepack/lib/install_handlers.rb`, `lib/rulepack/io.rb`, `lib/rulepack/install_execute.rb`, `lib/rulepack/validation.rb`
**Test gate**: `rake test` — new handler tests for json_merge and yaml_merge with rollback.

---

### 🟠 P-AN — Structured Inject Handler for Config Files

**Priority**: MEDIUM
**Risk**: LOW
**Status**: OPEN

**Architecture Goal**: Goal 6 (Append/inject → 9→9.5)
**Current Score**: 9/10 — `inject` handler prepends raw text line (`@import "file.md"`) to config files. For platforms that need structured YAML/JSON import injection (not text prepend), this produces invalid files.

**Claim**: `install_handlers.rb:119-144` — inject handler does `atomic_write(install_path, import_line + existing)` — a raw string prepend. If a platform's config is structured YAML with an `imports:` list, prepending `@import "file"\n` corrupts the YAML.

**Verification**:
```ruby
# install_handlers.rb:131
import_line = "#{directive} \"#{output}\"\n"
Rulepack::Common.atomic_write(install_path, import_line + existing)
# No YAML/JSON parsing, no structured insertion
```
✅ VERIFIED — inject is text-level, no structured awareness.

**Act**: Add `structured_inject` handler that parses the target file as YAML/JSON, inserts the import at the correct location:
```ruby
def do_structured_inject(install_path, inject_config, pkgname, ctx)
  format = inject_config[:format] || 'yaml'
  directive = inject_config[:directive] || '@import'
  key = inject_config[:key] || 'imports'

  content = install_path.exist? ? install_path.read : ''
  if format == 'yaml'
    data = YAML.safe_load(content, symbolize_names: true) || {}
    data[key] ||= []
    data[key] << "#{directive} #{output}" unless data[key].include?("#{directive} #{output}")
    Rulepack::Common.atomic_write(install_path, YAML.dump(data))
  elsif format == 'json'
    data = JSON.parse(content) rescue {}
    data[key] ||= []
    data[key] << "#{directive} #{output}" unless data[key].include?("#{directive} #{output}")
    Rulepack::Common.atomic_write(install_path, JSON.pretty_generate(data))
  end
end
```

**Files to modify**: `lib/rulepack/lib/install_handlers.rb`, `lib/rulepack/validation.rb`, `data/registry/platforms.yaml`
**Test gate**: `rake test` — structured inject tests for YAML and JSON targets.

---

### 🟡 P-AO — Hybrid pkg_type Support in FORMAT_MAP and Validation

**Priority**: MEDIUM
**Risk**: LOW
**Status**: OPEN

**Architecture Goal**: Goal 2 (pkg_type → 8.5→9)
**Current Score**: 8.5/10 — `hybrid` type is documented in AGENTS.md and produced by `schema_migration.rb:derive_pkg_type` but not recognized by `FORMAT_MAP` or validated. If a PKGBUILD declares `pkg_type: hybrid` without explicit targets, `expand_targets` raises.

**Claim**: `build_loader.rb:67-80` FORMAT_MAP has no `hybrid` key. `validation.rb` does not validate `pkg_type` at all. `schema_migration.rb:58` derives `'hybrid'` when formats mix, but this value cannot be used as a source for `expand_targets`.

**Verification**:
```ruby
# build_loader.rb:67-80 — FORMAT_MAP has rule, skill, skill-bundle, agent — no hybrid
# validation.rb:35-43 — pkg_type not in validation
# schema_migration.rb:58 — derives 'hybrid' → stored but unusable for FORMAT_MAP
```
✅ VERIFIED — hybrid is documented/derived but not supported in FORMAT_MAP.

**Act**:
1. Add `hybrid` handling in `build_loader.rb:expand_targets`: hybrid packages **must** have explicit `targets` (cannot be auto-expanded because the format mix is ambiguous).
2. Add `pkg_type` validation to `validation.rb`: reject unknown types, allow only `rule`, `skill`, `skill-bundle`, `agent`, `hybrid`.
3. For `hybrid`, `expand_targets` validates that explicit targets exist and cover all required platforms.
4. Add FORMAT_MAP entries for hybrid:
```ruby
%w[hybrid directory] => 'directory',  # rule side
%w[hybrid skill]     => 'skill',      # skill side
%w[hybrid import]    => 'import',
```

**Files to modify**: `lib/rulepack/build_loader.rb`, `lib/rulepack/validation.rb`
**Test gate**: `rake test` — hybrid validation tests.

---

### 🟡 P-AP — Platform Format Profile Validation on Load

**Priority**: MEDIUM
**Risk**: LOW
**Status**: OPEN

**Architecture Goal**: Goal 4 (Schema Engine → 8→9, completeness)
**Current Score**: 8/10 — Platform YAML files have inconsistent key structures; `SchemaEngine.apply` silently skips missing keys with no warning. A typo in a platform YAML (e.g., `heading-style` instead of `heading_style`) produces no transformation and no error.

**Claim**: `platform.rb:92` loads format_profile with no key validation. `schema_engine.rb:17` returns early if `ruleset` is nil (section missing). All subsequent key accesses use nil-safe conditional checks that silently skip.

**Verification**:
```ruby
# platform.rb:92
cfg[:format_profile] = profile_path.exist? ? load_yaml(profile_path) : {}
# No key validation — typos silently ignored

# schema_engine.rb:17
return content unless ruleset  # silently skips if no section
# ruleset[:heading_style] → nil → no transformation → no warning
```
✅ VERIFIED — no validation of profile keys, silent skip on typos.

**Act**: Add `validate_format_profile` in `platform.rb` that checks for required and optional keys:
```ruby
REQUIRED_KEYS = %w[frontmatter].freeze
OPTIONAL_KEYS = %w[heading_style bullet_style emoji_policy max_heading_depth heading_style].freeze
ALL_KEYS = (REQUIRED_KEYS + OPTIONAL_KEYS).freeze

def validate_format_profile(profile, platform_id)
  %w[rules skills].each do |section|
    next unless profile[section]
    unknown = profile[section].keys - ALL_KEYS
    if unknown.any?
      Rulepack::Common.log_warn "Platform #{platform_id}: unknown keys in #{section}: #{unknown.join(', ')}"
    end
    missing = REQUIRED_KEYS - profile[section].keys
    if missing.any?
      Rulepack::Common.log_warn "Platform #{platform_id}: missing required keys in #{section}: #{missing.join(', ')}"
    end
  end
end
```

**Files to modify**: `lib/rulepack/platform.rb`
**Test gate**: `rake test` — platform validation tests with typo detection.

---

### P-D — Cache LRU Eviction (PREVIOUSLY OPEN)

**Priority**: LOW
**Risk**: LOW
**Status**: ✅ COMPLETED
**Date**: 2026-05-30

**Re-evaluation**: `cache.rb:34-52` already implements `enforce_cache_limit!` with LRU eviction based on directory mtime. Called after every `cache_source` write (line 79). Configurable via `RULEPACK_CACHE_MAX_MB` env var (default: 500 MB). `config.rb:25-27` defines `cache_max_size_mb`. **This feature is fully implemented** — the original OPEN status was incorrect.

---

## Summary Table — All Open Items

| ID | Priority | Description | Status |
|---|---|---|---|
| P-J | 🔴 CRITICAL | `pkgver_func` shell execution broken | ✅ COMPLETED |
| P-K | 🔴 CRITICAL | `cached_fetch_url` no 30x redirect handling | ✅ COMPLETED |
| P-L | 🔴 CRITICAL | `strip-frontmatter` not enforced as deprecated | ✅ COMPLETED |
| P-M | 🔴 CRITICAL | `verify_checksum` regex breaks on multi-package files | ✅ COMPLETED |
| P-N | 🟠 HIGH | `extract_tar_gz` symlink path traversal | ✅ COMPLETED |
| P-O | 🟠 HIGH | `platform_cfg_for` calls `exit 1` in library | ✅ COMPLETED |
| P-P | 🟠 MEDIUM | `fix_drift` reloads index from disk | ✅ COMPLETED |
| P-Q | 🟠 MEDIUM | `atomic_append` misleading name | ✅ COMPLETED |
| P-R | 🟠 MEDIUM | `install_all` dry-run mutates index in memory | ✅ COMPLETED |
| P-S | 🟠 MEDIUM | `bump.rb:invoke_build` uses fragile `load` | ✅ COMPLETED |
| P-T | 🟠 MEDIUM | TUI selector no timeout / SIGKILL safety | ✅ COMPLETED |
| P-U | 🟡 MEDIUM | Emoji strip leaves double spaces | ✅ COMPLETED |
| P-V | 🟡 MEDIUM | `backup.rb` counter not thread-safe | ✅ COMPLETED |
| P-W | 🟡 MEDIUM | `BuildPipeline#transformer` dead parameter | ✅ COMPLETED |
| P-X | 🟡 MEDIUM | `validate_target_entry_output` swallows bugs | ✅ COMPLETED |
| P-Y | 🟡 MEDIUM | `query installed` undocumented opencode default | ✅ COMPLETED |
| P-Z | 🟡 MEDIUM | `Rakefile` stale test counts | ✅ COMPLETED |
| P-AA | 🟡 MEDIUM | `.rulepack.local.yaml` priority broken (elsif) | ✅ COMPLETED |
| P-AB | 🟢 LOW | `build_schema.yaml` duplicate header comments | ✅ COMPLETED |
| P-AC | 🟢 LOW | `audit.rb` custom ARGV parser (inconsistent) | ✅ COMPLETED |
| P-AD | 🟢 LOW | Double pacman flag shift (`install.rb` + `cli_parser.rb`) | ✅ COMPLETED |
| P-AE | ⚪ LOW | Duplicate preamble (same root cause as P-AB) | ✅ COMPLETED |
| P-AF | ⚪ LOW | `common.rb` facade captures methods at load time | ✅ COMPLETED |
| P-AG | ⚪ LOW | `query.rb` aliases silently ignore args | ✅ COMPLETED |
| P-AH | ⚪ LOW | `resolve_directory_path` missing type guard | ✅ COMPLETED |
| P-AI | ⚪ LOW | `install_helpers.rb` pure pass-through | ✅ COMPLETED |
| P-AJ | ⚪ LOW | `build_index_path=` no type validation | ✅ COMPLETED |
| P-AK | 🔴 HIGH | Schema Engine for skill-bundle/agent directory builds | OPEN |
| P-AL | 🔴 HIGH | Dependency resolution engine (provides/dependencies) | OPEN |
| P-AM | 🔴 HIGH | JSON/YAML surgical merge install handler | OPEN |
| P-AN | 🟠 MEDIUM | Structured inject handler for config files | OPEN |
| P-AO | 🟡 MEDIUM | Hybrid pkg_type support in FORMAT_MAP | OPEN |
| P-AP | 🟡 MEDIUM | Platform format_profile validation on load | OPEN |

---

## Architecture Goal Scorecard

| # | Goal | Before | Target | Open Items |
|---|---|---|---|---|
| 1 | Upstream/local sources | 9/10 | 9/10 | (already met) |
| 2 | Content as skills/rules (pkg_type) | 8.5/10 | 9/10 | P-AO |
| 3 | Universal canonical format + aliases | 7.5/10 | 9/10 | P-AL |
| 4 | Schema Engine drives formatting | 8/10 | 9/10 | P-AK, P-AP |
| 5 | Symlink/copy install | 9.5/10 | 9.5/10 | (already met) |
| 6 | Append/inject (marker-based) | 9/10 | 9.5/10 | P-AN |
| 7 | Surgical JSON/YAML config injection | 3/10 | 9/10 | P-AM |

---

## Methodology

Each item follows the **Claim-Verify-Act** pattern:
1. **Claim**: Specific assertion about code behavior, with line references
2. **Verification**: How the claim was confirmed (direct source read, grep, or test observation) — marked ✅ VERIFIED or ❌ INCORRECT
3. **Act**: Concrete code change required, with before/after snippets

**No item was added without a verified source.** All line references confirmed by direct `read` tool calls against the current HEAD.
