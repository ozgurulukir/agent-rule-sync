# ADR-2026-07-29: Build Pipeline Refactor — Source-Centric with Cross-Package Union Cache

> **Status**: Accepted (in-progress, Aşama 1+2)
> **Date**: 2026-07-29
> **Deciders**: Maintainer

## Context

Empirical inspection of `build/` revealed structural waste (2026-07-29):

| Observation | Method | Value |
|---|---|---|
| Total `build/` size | `du -sh build/` | **1.3 GB** |
| Per-platform skill-bundle size | `du -sh build/<plat>/` | **~85 MB × 14 platforms ≈ 1.19 GB** |
| `memory` package — distinct built SHA values | read `build/index.yaml` | **2** (out of 14 platforms) |
| Same-source-same-translator store hits | hand-verify | 11 of 14 platforms share SHA `5cf17063…` |
| Distinct store files | `ls build/store/ | wc -l` | ~200+ (one per platform×package) |
| Distinct source content + unique transforms | theoretical lower bound | ~50 |

Root causes (verified by direct source read):

1. `build_per_pkg.rb:163-244` `build_skill_bundle_target` performs `cp_r` of every skill-bundle source into `build/<plat>/<pkg>/` for **every** target platform, producing 14 identical 85 MB directories.
2. `build_per_pkg.rb:143` `transform_cache` (the **Schema Profile Union** feature already in code) is **per-package** — `process_targets` allocates it inside its loop. The same `(source_sha, target_format, translator, ruleset, transformer)` tuple evaluated for `memory` is re-evaluated for `shell`, `task-management`, etc., producing identical store files under different SHA-keyed names.
3. `BuildPipeline` runs even for skill-bundle targets where schema engine work is duplicated per platform.

`build/index.yaml` already records the source SHA and built SHA per platform; the install path (`install_execute.rb:107-191`) reads from `build/<plat>/<pkg>/<output>` and symlink/copies. Skill-bundle install (`install_execute.rb:99`) calls `Rulepack::SkillBundle.install_skill_bundle` (lib/rulepack/lib/skill_bundle.rb).

## Status

**Phase 1 (source-centric skill-bundle)** — implemented and validated. 4 new tests, 0 new failures, full suite green at 394 runs / 1215 assertions. `build/` size 1.3 GB → 46 MB (−96.5%).

**Phase 2 (cross-package union cache)** — DEFERRED (YAGNI). Empirical inspection of `build/index.yaml` showed that distinct packages have distinct `source_sha256` values, so cross-package cache hits are not currently realized. The per-package union cache already in `build_per_pkg.rb:269-275` (existing code) collapses 14 platforms per package to 1 store file. Total store size: 52 files, 272 KB. If future packages share source content (e.g. monorepo forks), Phase 2 can be re-opened by lifting `transform_cache` from `process_targets` to module scope.

## Decision

Adopt a **source-centric** build pipeline:

1. **Source-centric for skill-bundle/agent format**: build phase records `source_dir` and `source_sha` in `build/index.yaml` (already done), but does **not** copy files to `build/<plat>/<pkg>/`. Install phase materializes the bundle from `source_dir` on first access, applies Schema Engine, and writes `manifest.json` derived from the source SHA (so verify's checksum contract is preserved).
2. **(Deferred)** Global union cache for single-file targets: lift `transform_cache` from `process_targets` (per-package) to a module-level memoization keyed by `(source_sha, target_format, translator, ruleset, transformer)`.
3. **Backward compat**: `build/<plat>/<pkg>/<output>` symlinks remain functional (lazy-created on first install access). `verify_package_on_disk` continues to read from `build/<plat>/<pkg>/` and tolerates lazy materialization (creates it if missing, then verifies). Old build trees are not migrated — a rebuild is required.

Scope boundaries (YAGNI — explicitly out of scope):

- No runtime Schema Engine at install time. Single-file targets still build artifacts at build phase (transformer+translator can be expensive; keep this on the build path).
- No build artifact GC. `build/store/` and `build/git-sources/` remain the cache.
- No change to `build/index.yaml` schema. New fields are additive.

## Consequences

**Positive**:

- `build/` size drops from ~1.3 GB to ~80 MB (skill-bundle directories no longer copied ×14).
- `bin/rulepack build` skips skill-bundle `cp_r` for platforms that will not be installed (still records `available_targets` and `source_dir`).
- Content store dedupe across packages (Schema Profile Union, already partially implemented per-package, becomes global).
- No new transitive dependency. No public API change for end users.

**Negative / Risks**:

- Skill-bundle install becomes slightly slower on first run (cp_r + schema engine on demand). Subsequent runs use existing install paths (idempotent if manifests match).
- `verify_package_on_disk` must tolerate lazy materialization; if `build/<plat>/<pkg>` is missing, it materializes from `source_dir`. Tests that depend on `build/<plat>/<pkg>/<output>` existing after build need updating.
- Cross-package union cache invalidation: if a package's source changes but the union tuple stays the same, the cache would serve stale content. Mitigated by including `source_sha` in the union key (already done — see `build_per_pkg.rb:269-275`).

**Test impact**:

- `test_end_to_end.rb:test_skill_bundle_install_then_uninstall` (line 300): expects `manifest.json` after install — must still pass.
- `test_symlink_hardening.rb` (95 lines): skill-bundle `strip_symlinks_in_tree` runs in `build_skill_bundle_target` AND `install_file_or_skill`. After refactor, only install-side strip remains; test must continue to pass.
- `test_build_pipeline.rb:test_schema_profile_union_caching` (line 139): still passes (cache behavior preserved, just elevated to global scope).

**Validation**:

- Baseline (HEAD): 390 runs, 1186 assertions, 0 fail, 4 error (cache.rb pre-existing regression, unrelated), 2 skip.
- Post-refactor: same numbers, plus 3 new tests for cross-package union, skill-bundle lazy, source-tarball dedupe.
- Empirical: `du -sh build/` before/after; `ls build/store/ | wc -l` before/after.

## Alternatives Considered

- **Keep cp_r, only fix transform_cache globally**: ~30% disk reduction, ~80% file reduction in `build/store/`, but `build/<plat>/<pkg>/` for skill-bundles still bloats 1.19 GB. Rejected — the bigger waste is the per-platform copy.
- **Move all Schema Engine to install time**: maximum laziness, but each `install` invocation would re-run schema rules for every package. Transform/translator code is Ruby-evaluated per call. Rejected — it would slow install by seconds and remove the build→install contract.
- **Hardlink / reflink instead of cp_r**: requires filesystem support (Btrfs, XFS, APFS). Linux-only, fragile. Rejected — portability matters.
