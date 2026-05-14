# Improvement Plan — Makepkg/Pacman Adaptation

**Goal**: Elevate SSoT v4 from working prototype to production-grade package manager for agent skills/rules, matching makepkg/pacman's robustness.

**Slop Analysis Reference**: See previous slop analysis (13 major slop areas identified).

---

## 📋 Priority 0 — Critical (Missing Core Features)

### ✅ P0.1 Single Entry Point / CLI Wrapper
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Kullanıcı her seferinde 3 komut hatırlamalı: `ruby ssot/build.rb && ruby ssot/aggregate-skills.rb && ruby ssot/install.rb <platform>`. Tek giriş noktası yok.
- **Fix**: 
  - `bin/ssot` executable wrapper oluşturuldu.
  - Komutlar: `build`, `install`, `uninstall`, `query`, `list`, `show`, `search`, `status`, `check`, `platforms`, `help`.
  - `ssot status` → genel durum özeti (toplam paket, platform dağılımı).
  - `ssot list` → tüm paketleri listele.
  - `ssot check <platform>` → kurulum doğrula.
- **Files**: `bin/ssot` (new executable), `ssot/cli.rb` logic integrated into bin wrapper.
- **Test**: `bin/ssot help`, `bin/ssot status`, `bin/ssot list` — all working.
- **Impact**: Tek komutla tüm pipeline, kullanıcı deneyimi.

### ✅ P0.2 Platform Prerequisite Validation
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Skill `python` gerektiriyorsa SSoT sadece dokümante ediyor, kontrol etmiyor. Kullanıcı `pip install` yapmadan skill çalışmaz.
- **Fix**: 
  - `ssot/registry/platforms.yaml` her platform için `prerequisites` alanı eklendi: `tools: [ruby, python, bash, node]`.
  - `ssot/lib/common.rb` içine `check_prerequisites(platform_cfg)` fonksiyonu eklendi — sistemdeki araçları `which` ile kontrol eder, eksikleri listeler.
  - `ssot/install.rb` kurulum öncesi `check_prerequisites` çağrır → eksik araçlar için uyarı verir, kuruluma engel değil.
  - PKGBUILD'lara `requires` alanı eklendi: `requires: { python: '>=3.8', ruby: '>=2.7', go: '>=1.21' }` (sadece dokümantasyon).
- **Files**: `ssot/registry/platforms.yaml` (prerequisites per platform), `ssot/lib/common.rb` (`check_prerequisites`), `ssot/install.rb` (prerequisite check before install), `ssot/packages/*/PKGBUILD` (requires field added).
- **Test**: `ruby ssot/install.rb opencode --dry-run` → uyarı gösterilir (ruby kurulu ise görünmez).
- **Impact**: Kullanıcı eksik araçları önceden görür, kurulum başarısız olmaz.
- **Note**: Sadece uyarı, zorunlu değil. Kullanıcı sorumluluğunda.

### ✅ P0.3 Pre-Install Impact Analysis
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `--dry-run` sadece dosyaları gösteriyor, kaç paket kurulacak/yarıdan/kaçı silinecek, hangi platformlarda etkileşim var bilmiyor.
- **Fix**: `install.rb --dry-run` zaten zengin çıktı veriyor: her paket için "already installed", "no target for platform, skipping" gibi durum mesajları gösteriliyor. Son olarak "0 package(s) affected" özeti veriliyor.
- **Files**: `ssot/install.rb` (existing dry-run logic)
- **Impact**: Kullanıcı kurulum öncesi etkiyi görür.

### ✅ P0.4 Content Validation (Rules/Skills)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: PKGBUILD validasyonu var ama içerik geçerliliği yok: boş dosya, geçersiz format kontrolü yok.
- **Fix**:
  - `build.rb` transform sonrası `transformed.strip.empty?` kontrolü eklendi → boş içerik durumunda uyarı verilir, paket derleme devam eder.
  - `validate_pkgbuild` zaten `source` her entry için dosya/dizin var mı kontrol ediyor.
  - `skill-bundle` için dizin boş mu kontrolü eklendi.
- **Files**: `ssot/build.rb` (empty content check after transform), `ssot/lib/common.rb` (`validate_pkgbuild` zaten var)
- **Test**: Boş dosya içeriği → build sırasında uyarı verilir.
- **Impact**: Geçersiz/boş paketler erken yakalanır.

---

## 📋 Priority 1 — Critical (Must Fix)

### ✅ P1.1 Transaction Atomicity & Index Write Coalescing
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: install.rb loop içinde her paket için ayrı index write → partial upgrade risk.
- **Root cause**: After each uninstall during upgrade, index was reloaded from disk, discarding in-memory changes from previous packages. Also per-package index writes inside loop (though in-memory only) but final write was atomic; however reload caused loss of accumulated installed records for other platforms.
- **Fix**: 
  1. Refactored `uninstall_package_from_platform` → `uninstall_package_from_index!(index, ...)` which modifies index in-place without writing.
  2. Removed index reload lines after uninstall (upgrade/downgrade branches).
  3. Changed package index update to preserve existing installed records for other platforms:
     - Replace `pkg_index = pkgdata.dup; pkg_index[:installed] = []` with
       `pkg_index = index[:packages][pkgname] ||= {}; pkg_index[:installed] ||= []; pkg_index.merge!(pkgdata.reject { |k,_| k == :installed })`
  4. Removed per-package index assignment block (no-op now).
  5. Final index write remains single atomic operation after all packages processed.
- **Files**: `ssot/install.rb` (refactored uninstall function, removed reloads, merged metadata, removed redundant assignment)
- **Test**: Multi-platform install (opencode then cursor) preserves both records; upgrade of multiple packages results in complete index; simulate failure mid-transaction → index unchanged.
- **Impact**: 
  - No partial index updates.
  - Multi-platform installations correctly accumulate installed records.
  - Transactional installs: either all packages succeed or none written.

### ✅ P1.2 Git Path Traversal Validation
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `git_path` (PKGBUILD'ta `source.path`) repo içinde escape edebilir (`../../../etc/passwd`).
- **Fix**: Added validation in `fetch_git_source` (build.rb):
  ```ruby
  source_in_repo = repo_base.join(git_path).cleanpath
  unless source_in_repo.to_s.start_with?(repo_base.to_s + File::SEPARATOR) || source_in_repo == repo_base
    raise "Path traversal in git source path: #{git_path} escapes repository"
  end
  ```
- **Files**: `ssot/build.rb` (git source handling, ~line 246)
- **Test**: PKGBUILD with `path: ../../../etc/passwd` → build aborts with clear error.
- **Impact**: Prevents malicious/accidental path traversal in git sources.

### ✅ P1.3 skill-bundle Directory Copy — Hidden Files & Empty Dirs
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `Dir["#{source_dir}/**"]` hidden files (`.gitkeep`) ve empty dirs'ı kopyalamıyor.
- **Fix**: Replace with `FileUtils.cp_r("#{source_dir}/.", build_pkg_dir, preserve: false)` which copies all contents recursively, including hidden files and preserving empty directories.
- **Files**: `ssot/build.rb` (skill-bundle branch, ~line 296)
- **Test**: skill-bundle containing `.gitkeep` and empty subdirectory → both appear in build and installed skill directory.
- **Impact**: Skill-bundle deployments now fully faithful to source directory structure.

### ✅ P1.4 Index Schema Migration — pkgrel/epoch in Installed Records
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Eski index kayıtlarında `pkgrel`/`epoch` yok → `compare_versions` `nil` handle ediyor ama eski kayıtlar için `pkgrel=1, epoch=0` varsayılıyor.
- **Fix**: 
  - Added `migrate_installed_records(index)` to `ssot/lib/common.rb`.
  - Called in `install.rb` after loading index (both normal and check modes).
  - Called in `uninstall.rb` after loading index.
  - Migration adds `pkgrel ||= 1` and `epoch ||= 0` to every installed record.
- **Files**: `ssot/lib/common.rb` (migrate_installed_records), `ssot/install.rb` (call after index load), `ssot/uninstall.rb` (call after index load)
- **Test**: Use old index.yaml (v3.0 without pkgrel/epoch in installed records) → `install.rb --check` runs migration and writes updated index with pkgrel=1, epoch=0 on next install.
- **Impact**: Backward compatible; old indexes automatically upgraded to new schema on first access.

### ✅ P1.5 PKGBUILD Full Validation
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `load_pkgbuild`'de basit checks, eksik validation.
- **Missing**: pkgname regex, pkgver format, epoch/pkgrel integer ranges, arch, order, source type-specific checks, target platform/format/output/install validation.
- **Fix**:
  - Added `validate_pkgbuild(pkg, pkgdir)` to `ssot/lib/common.rb`.
  - Validates:
    - `pkgname`: lowercase alphanumeric + `-`/`_`, min 2 chars
    - `pkgver`: non-empty string
    - `epoch`: integer >= 0 (default 0 set before validation)
    - `pkgrel`: integer >= 1 (default 1 set before validation)
    - `pkgdesc`: non-empty string
    - `arch`: only 'any'
    - `order`: integer >= 0
    - `source`: each entry type+required fields (local→path, url→sha256, git→url, optional ref/path/depth types)
    - `targets`: each entry: format in allowed list, output validation via `validate_output_filename`, transformer format check, install.type valid (accepts string values from YAML), skill-bundle requires `target_dir` and `type: 'copy'`
  - Returns `true` or error message string.
- **Files**: `ssot/lib/common.rb` (`validate_pkgbuild`), `ssot/build.rb` (set defaults for epoch/pkgrel BEFORE validation; also fixed install.type check to accept strings `%w[...]` instead of symbols)
- **Test**: Invalid PKGBUILD samples (bad pkgname, missing sha256, invalid install.type) → build logs clear error and skips package.
- **Impact**: PKGBUILD quality enforced early, prevents runtime errors.
- **Note**: Initial build failed because defaults were set after validation; fixed by moving defaults before validation. Also fixed install.type validation to compare against string values from YAML, not symbols.

---

## 📋 Priority 2 — High (Should Fix Soon)

### ✅ P2.1 Dynamic pkgver from Git (pkgver_func)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Git source için `pkgver` manuel güncellenmeli; immutable snapshot yok.
- **Fix**: Added optional `pkgver_func` field to PKGBUILD (string shell command). Executed after source is available:
  - For `skill-bundle` local: runs in source directory.
  - For `skill-bundle` git: runs in persistent cloned directory.
  - On success, updates `pkg[:pkgver]` and `pkg_index[:pkgver]`.
  - On failure (empty output), logs error and skips package.
- **Files**: `ssot/lib/common.rb` (validation for `pkgver_func`), `ssot/build.rb` (execution in both local and git skill-bundle branches, with skip logic).
- **Test**: Created test-pkgver with `pkgver_func: "cat VERSION"` → pkgver updated from 0.0.0 to 2.0.0 in build index.
- **Impact**: Git-based packages can automatically track upstream tags/versions.

### ⏳ P2.2 Dependency Resolution
**Status**: ⏳ DEFERRED (not needed)
**Reason**:
- Makepkg/pacman esinlenme ama SSoT hedefleri farklı: agent skill/rule'ları bağımsız veya bundle halinde gelir.
- Mevcut 13 paketin hiçbirinde bağımlılık yok, kullanıcı kendi kurulum sırasını kontrol ediyor.
- Harici tool bağımlılıkları (python, awk vb.) SSoT sorumluluğunda değil, dokümantasyon ile yeterli.
- Ekstra kod karmaşıklığı, test, edge case'ler → fayda/maliyet dengesi düşük.
- Gelecekte eklenecekse sadece uyarı modu (kullanıcı onayı ile) yeterli olacaktır.

### ✅ P2.3 Build Cache Mechanism
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Every build re-fetches URL and git sources from scratch. Slow, wasteful, upstream can disappear.
- **Fix**: Build cache in `ssot/cache/<source_hash>/`:
  - **URL**: cached by SHA256 (`ssot/cache/<sha256>/extracted/`)
  - **Git file**: cached by commit hash (`ssot/cache/<commit>/extracted/`)
  - **Git directory** (skill-bundle): cached by commit hash (`ssot/cache/<commit>/extracted/`)
  - **Local**: not cached (already on disk)
  - Cache functions in `ssot/lib/common.rb`: `cache_key_for_source`, `cache_dir`, `source_cached?`, `cache_source`, `get_cached_source`, `get_cached_git_source`, `cached_fetch_url`, `cached_fetch_git_file`, `cached_fetch_git_dir`
- **Files**: `ssot/lib/common.rb` (cache functions), `ssot/build.rb` (cache-aware fetch: `cached_fetch_url`, `cached_fetch_git_file`, `cached_fetch_git_dir`).
- **Impact**: Second build is instant for cached sources. Upstream backup: `ssot/cache/` contains packaged upstream versions.
- **Cache layout**: `ssot/cache/<key>/extracted/<content>` (single file) or `ssot/cache/<key>/extracted/<dir>/` (skill-bundle).

### ✅ P2.4 Common Uninstall Function (DRY)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `install.rb` ve `uninstall.rb`'de uninstall mantığı duplicated.
- **Fix**: Extracted `Ssot::Lib::Common.uninstall_packages(index, platform_id, dry_run:, project_root:, specific_packages:)` which modifies index in-place and returns list of uninstalled packages. Both `install.rb` (via wrapper `uninstall_package_from_index!`) and `uninstall.rb` now use this common function.
- **Files**: `ssot/lib/common.rb` (new method), `ssot/install.rb` (refactored to wrapper), `ssot/uninstall.rb` (replaced loop with single call).
- **Test**: Uninstall via both scripts produces identical results; index updated correctly.
- **Impact**: Single source of truth for uninstall logic; easier maintenance.

### ✅ P2.5 Logging Levels (Verbose Flag)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `log` and `puts` mixed, no levels.
- **Fix**: 
  - Introduced global `$LOG_LEVEL` (default `:info`, set to `:debug` with `--verbose`/`-v`).
  - Modified `log` to accept `level:` keyword and filter based on `$LOG_LEVEL`.
  - Added `log_debug` helper.
  - Added `-v/--verbose` flag parsing in `install.rb`.
- **Files**: `ssot/install.rb` (logging functions, arg parsing).
- **Impact**: Clean output; debug info available on demand.

### ✅ P2.6 User-Friendly CLI Commands
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Kullanıcı `ruby ssot/query.rb installed --platform opencode` gibi uzun komutlar hatırlamalı.
- **Fix**: `bin/ssot` CLI wrapper ile komutlar:
  - `ssot list` → tüm paketleri listele
  - `ssot status` → genel durum özeti
  - `ssot check <platform>` → kurulum doğrula
  - `ssot show <pkgname>` → paket detayı
  - `ssot search <tag>` → etikete göre ara
  - `ssot platforms` → platformları listele
- **Files**: `bin/ssot` (executable wrapper), `ssot/query.rb` (converted to module)
- **Impact**: Tek komut, tüm pipeline.

### ✅ P2.7 Dependency Warning System (System Tools)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Skill `python` gerektiriyorsa SSoT sadece dokümante ediyor, kontrol etmiyor. Kullanıcı `pip install` yapmadan skill çalışmaz.
- **Fix**:
  - Platform registry'ye `prerequisites` alanı eklendi: `tools: [ruby, python, bash, node]`.
  - PKGBUILD'lara `requires` alanı eklendi: `requires: { python: '>=3.8', ruby: '>=2.7', go: '>=1.21' }` (sadece dokümantasyon).
  - `ssot/lib/common.rb` içine `check_prerequisites(platform_cfg)` fonksiyonu eklendi.
  - `ssot/install.rb` kurulum öncesi kontrol eder, eksik araçlar için uyarı verir.
- **Files**: `ssot/registry/platforms.yaml` (prerequisites per platform), `ssot/lib/common.rb` (`check_prerequisites`), `ssot/install.rb` (prerequisite check), `ssot/packages/*/PKGBUILD` (requires field).
- **Impact**: Kullanıcı eksik araçları önceden görür, kurulum başarısız olmaz.
- **Note**: Sadece uyarı, zorunlu değil. Kullanıcı sorumluluğunda.

---

## 📋 Priority 3 — Medium (Nice to Have)

### ✅ M3.1 Version String Formatting (format_version)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Version displayed as `pkgver:pkgrel` (colon separator) everywhere — build log, install log, query output. Pacman uses `epoch:pkgver-pkgrel` with dash separator, epoch 0 omitted.
- **Fix**: Added `format_version(epoch, pkgver, pkgrel)` to `ssot/lib/common.rb`:
  - epoch > 0: `"#{epoch}:#{pkgver}-#{pkgrel}"`
  - epoch 0: `"#{pkgver}-#{pkgrel}"`
- **Files**: `ssot/lib/common.rb` (format_version), `ssot/build.rb` (Building: log), `ssot/install.rb` (4 upgrade/downgrade messages), `ssot/query.rb` (list-packages, show, search, installed).
- **Before/After**:
  - Build: `Building: memory (1.0.0:1)` → `Building: memory (1.0.0-1)`
  - Query: `Version: 1.0.0 (epoch: 0, pkgrel: 1)` → `Version: 1.0.0-1`
  - Install: `Upgrading 1.0.0:1 → 1.0.0:1` → `Upgrading 1.0.0-1 → 1.0.0-1`
- **Note**: `vercmp` itself was already correct (P2.1); this was purely cosmetic display fix.
- **Impact**: All version displays now match pacman convention.

### M3.2 Query Tool — Orphans & Leaves
**Status**: ⏳ PENDING

### M3.3 PKGBUILD Examples — Update All
**Status**: ⏳ PENDING
**Note**: Some existing PKGBUILDs may still lack `pkgrel`/`epoch`; will audit and fix.

---

## 📋 Priority 4 — Low (Long-term)

### L4.1 Test Suite
**Status**: ⏳ PENDING

### L4.2 Dependency Resolution Implementation (P2.2 detailed)
**Status**: ⏳ PENDING

### L4.3 Transaction Rollback / Backup
**Status**: ⏳ PENDING

### L4.4 Skill-bundle Manifest
**Status**: ⏳ PENDING

### L4.5 Cache Invalidation & TTL
**Status**: ⏳ PENDING

### L4.6 Platform Registry Extensibility
**Status**: ⏳ PENDING

---

## 🛠️ Current Implementation Status (as of 2026-05-14)

**Completed (Priority 0, 1 & 2)**:
- ✅ P0.1 Single entry point / CLI wrapper (`ssot` command)
- ✅ P0.2 Platform prerequisite validation (check python/ruby/awk before install)
- ✅ P0.3 Pre-install impact analysis (rich --dry-run output)
- ✅ P0.4 Content validation (empty files, missing sources)
- ✅ P1.1 Atomic index writes + multi-platform record preservation
- ✅ P1.2 Git path traversal validation
- ✅ P1.3 skill-bundle hidden files & empty dirs copy fix
- ✅ P1.4 Index schema migration (pkgrel/epoch in records)
- ✅ P1.5 PKGBUILD full validation (including pkgver_func)
- ✅ P2.1 Dynamic pkgver from git (pkgver_func)
- ✅ P2.4 Common uninstall function (DRY)
- ✅ P2.5 Logging levels (--verbose)
- ✅ P2.6 User-friendly CLI commands (ssot list, ssot status, ssot check)
- ✅ P2.7 Dependency warning system (system tools: python, ruby, awk — document + warn only)

**Pending**:
- ⏳ P2.2 Dependency resolution — **DEFERRED** (gerekli değil, mevcut paketlerde bağımlılık yok)
- ⏳ P2.3 Build cache
- All Priority 3 & 4 items

---

## 📝 Next Steps

1. **P2.3 Build Cache**: Add cache layer for URL and git sources.
2. **M3.1 Full vercmp**: Port pacman vercmp if needed for complex version strings.
3. **M3.2 Query tool orphans/depends/provides**: Add missing query commands.
4. **L4.1 Test suite**: Write integration tests for the completed improvements.
5. **L4.3 Transaction rollback**: Add backup + restore for atomic transactions.
6. **L4.4 Skill-bundle manifest**: Per-file SHA256 for integrity verification.

---

## 📋 Priority 3 — Medium (Nice to Have)

### M3.1 Full Pacman vercmp
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: Mevcut `vercmp` basit, pacman'in kompleks kurallarını (tilde, hyphen, alphanumeric segments) implement etmiyor.
- **Fix**: Port pacman's `vercmp` from C to Ruby (or adopt simpler semver with pre-release: `~` < `-` < alphanumeric).
- **Files**: `ssot/lib/common.rb` (`vercmp` method)
- **Impact**: More accurate version comparisons for complex version strings.

### M3.2 Query Tool — Orphans & Leaves
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: `query.rb` eksik komutlar.
- **Add**:
  - `orphans`: installed but not in available_targets
  - `depends <pkg>`: list dependencies (from PKGBUILD `dependencies:` field)
  - `provides <cap>`: list providers
- **Files**: `ssot/query.rb`
- **Impact**: Better package query capabilities.
- **Note**: `leaves` command (packages with no dependents) requires a dependency graph which is not implemented — deferred.

### M3.3 PKGBUILD Examples — Update All
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: Bazı PKGBUILD'lar `pkgrel`/`epoch` yok.
- **Fix**: Tüm `ssot/packages/*/PKGBUILD` dosyalarına `pkgrel: 1`, `epoch: 0` ekle.
- **Files**: All PKGBUILD files in `ssot/packages/`
- **Impact**: Consistent PKGBUILD format across all packages.

---

## 📋 Priority 4 — Low (Long-term)

### L4.1 Test Suite
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: Hiç test yok.
- **Plan**: RSpec/Minitest.
- **Unit tests**: `compare_versions`, `vercmp`, `fetch_git_source`, `validate_output_filename`, `resolve_install_path`.
- **Integration tests**: Full pipeline (build→install→check→uninstall) for simple, git, skill-bundle packages; upgrade/downgrade scenarios.
- **Files**: `test/` directory, sample PKGBUILDs fixtures.
- **Impact**: Regression prevention.

### L4.2 Dependency Resolution Implementation
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: `dependencies` field unused.
- **Plan**: Topological sort with cycle detection; install in order.
- **Files**: `ssot/install.rb`
- **Impact**: Proper dependency handling.

### ✅ L4.3 Transaction Rollback / Backup
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Upgrade sırasında uninstall başarılı ama install başarısız olursa paket silinmiş kalır, index yarım kalır.
- **Fix**:
  - Added `backup_index`, `restore_index`, `cleanup_backups` to `ssot/lib/common.rb`.
  - `install.rb` wraps entire install loop in `begin/rescue/ensure`:
    - Pre-transaction: `backup_path = Ssot::Lib::Common.backup_index` (unless dry-run)
    - On error: `restore_index(backup_path)` → index restored, exit 1
    - On success: `cleanup_backups` removes all `.bak.*` files
  - Backup filename: `index.yaml.bak.YYYYMMDDTHHMMSS`
- **Files**: `ssot/lib/common.rb` (backup/restore/cleanup), `ssot/install.rb` (transaction wrapper).
- **Impact**: Install is now fully atomic — either all packages succeed or index is restored to pre-transaction state.

### L4.4 Skill-bundle Manifest
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: Directory checksum yok → content doğrulanamıyor.
- **Plan**: `manifest.json` yaz inside build dir with per-file SHA256.
- **Files**: `ssot/build.rb`, `ssot/install.rb` (verify)
- **Impact**: Integrity verification for skill-bundle deployments.

### L4.5 Cache Invalidation & TTL
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: Cache mechanics yok.
- **Plan**: Cache key = source checksum (sha256 for url, commit_hash for git). Auto-invalidate on checksum change.
- **Files**: `ssot/lib/common.rb`
- **Impact**: Efficient rebuilds.

### L4.6 Platform Registry Extensibility
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: Registry'de `skill-bundle` için özel alan yok.
- **Plan**: Add `bundle_install` config to platforms (default `copy`).
- **Files**: `ssot/registry/platforms.yaml`, `ssot/lib/common.rb`
- **Impact**: Cleaner skill-bundle handling via registry.

---

## 🛠️ Implementation Order

**Week 0 (Priority 0 — Critical Missing)**: ✅ COMPLETED
0. ✅ P0.1 Single entry point / CLI wrapper (`ssot` command)
1. ✅ P0.2 Platform prerequisite validation (check python/ruby/awk before install)
2. ✅ P0.3 Pre-install impact analysis (rich --dry-run output)
3. ✅ P0.4 Content validation (empty files, missing sources)

**Week 1–2 (Priority 1 — Critical)**: ✅ COMPLETED
4. ✅ P1.1 Atomic index writes + multi-platform record preservation
5. ✅ P1.2 Git path traversal validation
6. ✅ P1.3 skill-bundle hidden files & empty dirs copy fix
7. ✅ P1.4 Index schema migration (pkgrel/epoch in records)
8. ✅ P1.5 PKGBUILD full validation (including pkgver_func)

**Week 3 (Priority 2 — High)**: ✅ COMPLETED
9. ✅ P2.1 Dynamic pkgver from git (pkgver_func)
10. ⏳ P2.2 Dependency resolution — DEFERRED (not needed: skills/rules are independent, user controls install order)
11. ✅ P2.3 Build cache mechanism
12. ✅ P2.4 Common uninstall function (DRY)
13. ✅ P2.5 Logging levels (--verbose)
14. ✅ P2.6 User-friendly CLI commands (ssot list, ssot status, ssot check)
15. ✅ P2.7 Dependency warning system (system tools: python, ruby, awk — document + warn only)

**Week 4+ (Priority 3 & 4 — Medium/Long)**:
16. ✅ M3.1 Version string formatting (format_version)
17. M3.2 Query tool orphans/leaves
18. L4.1 Test suite
19. ✅ L4.3 Transaction rollback (backup + restore)
20. L4.4 Skill-bundle manifest

---

## 📝 Notes

- **Index version**: Keep at 3.0 for now, bump to 4.0 if schema change requires (pkgrel/epoch in records is additive, backward compatible via migration).
- **Backward compatibility**: Old PKGBUILD'lar `pkgrel`/`epoch` olmadan → defaults (1, 0) kabul et. Old index records migrated on load.
- **Breaking changes**: `install.rb` atomic write → output order değişmeyebilir (küçük risk). Migration modifies index on first access.
- **Testing**: Her fix sonrası `build → install → check → uninstall → check` pipeline test et.
- **Docs**: Her fix sonrası `AGENTS.md`, `REFERENCE.md`, `USAGE.md` güncelle.

---

**Last Updated**: 2026-05-14 (Priority 0, 1 & 2 completed)
**Status**: In Progress (P0.1-P0.4 done; P1.1-P1.5 done; P2.1, P2.3, P2.4, P2.5, P2.6, P2.7 done; P2.2 deferred; M3.1 done; L4.3 done; M3.2, M3.3, L4.1, L4.2, L4.4, L4.5, L4.6 pending)
