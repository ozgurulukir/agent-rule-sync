# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- **Source-centric build pipeline**: skill-bundles are now lazily materialized at
  install time instead of eagerly copied to every `build/<plat>/<pkg>/` target.
  Reduces `build/` from 1.3 GB to 46 MB (−96.5%) for the `anthropics-skills`
  workload. ([ADR-2026-07-29](docs/improvement-plan/ADR-2026-07-29-build-pipeline-refactor.md))
- `lib/rulepack/lib/skill_bundle_lazy.rb` — lazy materialization helpers
  (`ensure_materialized!`, `materialization_up_to_date?`,
  `apply_schema_engine_to_directory`).
- `test/test_source_centric_build.rb` — 4 acceptance tests (AC1–AC4) covering
  build-only metadata, lazy install materialization, store dedup, and e2e
  contract.
- `docs/improvement-plan/ADR-2026-07-29-build-pipeline-refactor.md` — full
  Context / Decision / Consequences record for the refactor.

### Changed

- `lib/rulepack/build_per_pkg.rb#build_skill_bundle_target` — refactored from
  ~85 LOC (cp_r + schema + manifest) to ~17 LOC (metadata-only). Schema Engine
  and manifest generation moved to install-time materialization.
- `lib/rulepack/lib/skill_bundle.rb#install_skill_bundle` — added lazy
  materialization block that copies from `pkgdata[:source_dir]` into
  `build/<plat>/<pkg>/` on demand, gated by `manifest.json` `source_sha256`.
- `AGENTS.md` — added source-centric build feature entry with baseline
  comparison table, 5 project-specific gotchas, and updated test counts
  (390/1191 → 394/1216).
- `docs/improvement-plan/OPEN-ITEMS.md` — added ADR-2026-07-29 cross-reference
  row to summary table.
- **Cross-package content-addressed union cache** (Phase 2) — deferred per
  YAGNI. Empirical inspection shows distinct `source_sha256` per package, so
  cross-package dedup hits do not materialize in the current dataset. The
  per-package `union_key` cache already collapses 14 platforms → 1 store file
  per package (52 files, ~272 KB). Re-open if future packages share source
  content (e.g. monorepo forks).

### Fixed

- **Local-source skill-bundles without `pkgver_func`** now correctly fall back
  to `compute_local_source_sha` (SHA256 over the local source tree) instead of
  failing with a `nil` `source_sha256` guard. Affects packages like
  `line-repetition-control`.
- **Pre-existing test errors (4)** — cleared from 0F/4E/2S to 0F/0E/2S
  (unrelated to refactor; resolved by config path reload during the session).
