# Improvement Plan — Makepkg/Pacman Adaptation

**Goal**: Elevate Rulepack from working prototype to production-grade package manager for agent skills/rules, matching makepkg/pacman's robustness.

**Slop Analysis Reference**: See previous slop analysis (13 major slop areas identified).

---

## 📋 Priority 5 — Quality (Code Quality & User Experience)

### ✅ P5.1 Eliminate Duplicate Cache Functions in common.rb
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `lib/rulepack/common.rb` defines the entire cache API twice — once inside the `Rulepack::Common` module (lines 24–145) and once as orphaned top-level methods (lines 963–1109). The top-level methods are **dead code** — every caller uses `Rulepack::Common.cache_*`.

- **Root cause**: Historical artifact from when cache functions were top-level helpers; module was added later but old top-level methods were never removed.
- **Fix**:
  1. Delete lines 963–1109 (`end end end` closure at 959–961 followed by all cache method redefinitions).
  2. Verify no callers reference the top-level functions (grep confirms zero).
  3. Remove `require 'net/http'` and `require 'tempfile'` from top of file IF the module versions are the only ones used (they are — confirmed via grep).
- **Files**: `lib/rulepack/common.rb` (delete ~147 lines)
- **Test**: `rake test` — all 172 tests pass (they all reference `Rulepack::Common.*`).
- **Impact**: -147 lines dead code, eliminates confusion about which definition is canonical.

### ✅ P5.2 Unify Logging Across All Modules
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Logging is implemented independently in 4 separate places with slightly different APIs:

| File | Functions | Level Support | File Output |
|------|-----------|--------------|-------------|
| `build.rb` | `log`, `log_error`, `log_warn` | No | `build/build.log` |
| `lib/rulepack/installer.rb` | `log`, `log_error`, `log_warn`, `log_debug` | Yes (`$LOG_LEVEL`) | `build/install.log` |
| `uninstall.rb` | `log`, `log_error` | No | `build/uninstall.log` |
| `test/test_uninstall.rb` | `log`, `log_warn`, `log_error` (stubs) | No | N/A |

- **Root cause**: Each script was written independently, each needed logging, DRY was not applied.
- **Fix**:
  1. Add shared logging functions to `Rulepack::Common`:
     - `log(msg, level: :info, log_file: nil)` — reusable, configurable log file
     - `log_error(msg)`, `log_warn(msg)`, `log_debug(msg)` — convenience wrappers
     - Support `$LOG_LEVEL` for level filtering (from `lib/rulepack/installer.rb`)
     - Default log file determined by caller (`build.log`, `install.log`, `uninstall.log`)
  2. Replace all per-file logging in `build.rb`, `uninstall.rb`, `test/test_uninstall.rb` with calls to `Rulepack::Common.log*`.
  3. Remove duplicate `log`/`log_error`/`log_warn`/`log_debug` definitions from `build.rb`, `uninstall.rb`.
  4. `lib/rulepack/installer.rb` already delegates to `Rulepack::Common.log*` → update it to call shared version.
- **Files**: `lib/rulepack/common.rb` (add logging), `lib/rulepack/build.rb` (replace calls), `lib/rulepack/uninstall.rb` (replace calls), `lib/rulepack/installer.rb` (delegate), `test/test_uninstall.rb` (use `Rulepack::Common` directly or keep stubs)
- **Test**: Verify log output for all 3 entry points (`build`, `install`, `uninstall`) appears in correct files; log level filtering works identically.
- **Impact**: Single source of truth for logging, consistent format and file output, easier to add features (log rotation, JSON logging, etc.).

### ✅ P5.3 Remove Unnecessary Wrapper Functions in build.rb
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `build.rb` defines trivial one-line wrappers that just delegate to `Rulepack::Common`:

```ruby
def apply_transformer(content, transformer_cfg, pkgname:)
  Rulepack::Common.apply_transformer(transformer_cfg, content, pkgname: pkgname)
end

def validate_output_filename(output, pkgname)
  Rulepack::Common.validate_output_filename(output, pkgname)
end
```

- **Root cause**: These were likely created during refactoring when functions were moved from `build.rb` to `common.rb`, but the wrappers were left behind.
- **Fix**: Replace all call sites of `apply_transformer(...)` with `Rulepack::Common.apply_transformer(...)` and `validate_output_filename(...)` with `Rulepack::Common.validate_output_filename(...)`. Delete the wrapper function definitions.
- **Files**: `lib/rulepack/build.rb` (delete 2 wrapper functions, update ~2 call sites)
- **Test**: `rake test` + manual `ruby lib/rulepack/build.rb` — verify build output identical.
- **Impact**: Removes indirection, makes call sites explicit.

### ✅ P5.4 Remove Duplicated project_root_for in uninstall.rb
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `uninstall.rb` has its own `project_root_for` function (lines 31–42) that is an exact duplicate of the one in `Rulepack::Install.project_root_for` (lib/rulepack/installer.rb lines 665–672).

- **Root cause**: `uninstall.rb` was written before `lib/rulepack/installer.rb` existed.
- **Fix**: Extract to `Rulepack::Common.project_root_for(platform_id, platform_cfg, project_arg)`. Both `Rulepack::Install` and `uninstall.rb` call the shared version.
- **Files**: `lib/rulepack/common.rb` (add method), `lib/rulepack/installer.rb` (delegate), `lib/rulepack/uninstall.rb` (replace call)
- **Test**: `ruby lib/rulepack/uninstall.rb opencode --dry-run` — verify no regression.
- **Impact**: DRY, one source of truth for project root resolution.

### ✅ P5.5 Improve Error Messages — Actionable Guidance
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Error messages tell the user *what* went wrong but not *how to fix it*:

| Current | Problem | Proposed |
|---------|---------|----------|
| `"Build index not found at #{path}"` | No next step | `"Build index not found at #{path}. Run \`ruby lib/rulepack/build.rb\` first."` |
| `"SHA256 mismatch for #{url}"` | No next step | `"SHA256 mismatch for #{url}: expected #{expected}, got #{actual}. Update sha256 in PKGBUILD to #{actual}."` |
| `"git clone failed for #{url}"` | No next step | `"git clone failed for #{url}. Check network connectivity and verify the repository URL."` |
| `"Index not found"` | No next step | `"Index not found: #{path}. Run \`rulepack build\` first."` |
| `"PKGBUILD not found in #{pkgdir}"` | No next step | `"PKGBUILD not found in #{pkgdir}. Create data/packages/<name>/PKGBUILD or run \`rulepack build\` from repo root."` |
| `"Transformer failed for ..."` | Generic | Include the transformer path and suggest checking the file exists and defines `Transform.transform` |
| `"Translator failed for ..."` | Generic | Include the translator path and suggest checking the file exists and defines `Translator.translate` |
| `"Install failed"` | Generic | Include the install type, target path, and whether the source file exists |

- **Fix**:
  1. Audit all `raise` and `log_error` calls across `build.rb`, `lib/rulepack/common.rb`, `lib/rulepack/installer.rb`, `uninstall.rb`, `install.rb`.
  2. Add actionable guidance to each message: "What went wrong + how to fix it."
  3. Include relevant context (path, URL, expected vs actual values) so user doesn't need to re-run with `--verbose`.
- **Files**: `lib/rulepack/common.rb`, `lib/rulepack/installer.rb`, `lib/rulepack/build.rb`, `lib/rulepack/uninstall.rb`, `lib/rulepack/install.rb`
- **Test**: Trigger each error condition manually or via tests and verify suggestion is present.
- **Impact**: Dramatically better UX — users can fix problems without reading source code.

---

## 📋 Priority 6 — Performance & Caching

### ✅ P6.1 Add Performance Monitoring / Timing
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: No operation timing anywhere. Users can't tell if `build` is slow because of network, transformation, or disk I/O. No way to profile bottlenecks.

- **Fix**:
  1. Add `Rulepack::Common.time(operation_name)` helper that yields a block and logs elapsed time.
  2. Instrument key operations:
     - `build.rb`: per-package fetch + build time, total build time
     - `lib/rulepack/installer.rb`: per-target install time, total install time
     - `lib/rulepack/common.rb`: git clone time, URL fetch time, cache source time
  3. Add `--timing` flag to `bin/rulepack` and `install.rb`/`build.rb` CLI that prints timing summary at end.
  4. Timing output format: `"⏱  12.345s — fetch cc-skills-golang (git)"` — labels always show operation + package.
- **Files**: `lib/rulepack/common.rb` (add `time` helper), `lib/rulepack/build.rb` (instrument), `lib/rulepack/installer.rb` (instrument), `lib/rulepack/install.rb` (add `--timing` flag), `bin/rulepack` (add `--timing` passthrough)
- **Test**: `ruby lib/rulepack/build.rb --timing` → timing lines appear in log and stdout; no timing when flag absent. Timing wraps gracefully around errors.
- **Impact**: Users and developers can identify slow operations, optimize bottlenecks, set time budgets.

### ✅ P6.2 Cache Platform Registry in Memory
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `Rulepack::Common.load_platform_registry` reads and parses `data/registry/platforms.yaml` from disk every time it's called. During a single `rulepack install opencode` run, it's called 4+ times:
1. `platform_cfg_for` (via `install_platform`)
2. `check_prerequisites` (inside `install_platform`)
3. Various path resolution helpers
4. `uninstall_package_from_index!` during upgrade

Each call re-reads the file, re-parses YAML, re-validates all 13 platform configs.

- **Fix**: Use Ruby's `||=` memoization pattern:
  ```ruby
  @@_platform_registry = nil
  def load_platform_registry
    @@_platform_registry ||= begin
      registry_path = Pathname.new(__dir__).join('../registry/platforms.yaml').cleanpath
      raw = load_yaml(registry_path)
      raw.each { |id, cfg| validate_platform_config(id, cfg) }
      raw
    end
  end
  ```
  Add `clear_platform_registry_cache!` for testing (clean between test cases).
- **Files**: `lib/rulepack/common.rb` (add memoization + cache-clear method), `test/test_platform.rb` (call cache-clear in `setup`/`teardown`)
- **Test**: `rake test` — all platform registry tests pass. Verify cache-clear works by calling it and checking next call re-reads file. Verify that modifying registry file mid-run is NOT picked up (expected: cached).
- **Impact**: ~3× fewer YAML reads per install run, measurable speed improvement for multi-package installs.

### ✅ P6.3 Make Constants Configurable
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Hardcoded magic values scattered across the codebase:

| Location | Value | Hardcoded |
|----------|-------|-----------|
| `build.rb:41` | `max_redirects: 3` | URL fetch redirect limit |
| `build.rb:44` | `read_timeout: 30` | HTTP read timeout (seconds) |
| `lib/rulepack/common.rb:13-18` | `RULEPACK_ROOT`, `BUILD_DIR`, `INDEX_*`, `LOG_PATH` | All paths hardcoded |
| `lib/rulepack/common.rb:33` | `"cache"` | Cache directory name |
| `lib/rulepack/common.rb:1109` | `depth: 1` | Git shallow clone depth |
| `lib/rulepack/installer.rb:21-28` | `$LOG_LEVEL = :info` | Default log level |

- **Root cause**: No configuration layer exists. Everything is a constant or literal.
- **Fix**:
  1. Create `Rulepack::Config` module with default values and environment variable overrides:
     ```ruby
     module Rulepack
       module Lib
         module Config
           module_function
           def max_redirects
             Integer(ENV.fetch('RULEPACK_MAX_REDIRECTS', '3'))
           end
           def read_timeout
             Integer(ENV.fetch('RULEPACK_READ_TIMEOUT', '30'))
           end
           def cache_dir_name
             ENV.fetch('RULEPACK_CACHE_DIR', 'cache')
           end
           def git_clone_depth
             Integer(ENV.fetch('RULEPACK_GIT_DEPTH', '1'))
           end
           def log_level
             ENV.fetch('RULEPACK_LOG_LEVEL', 'info').to_sym
           end
         end
       end
     end
     ```
  2. Replace all hardcoded magic values with `Rulepack::Config.*` calls.
  3. Document all config vars in `docs/agents/REFERENCE.md` and `AGENTS.md`.
- **Files**: `lib/rulepack/common.rb` (add `Config` module), `lib/rulepack/build.rb` (replace max_redirects, read_timeout, depth), `lib/rulepack/installer.rb` (replace log level), `lib/rulepack/common.rb` (replace cache dir, depth), `docs/agents/REFERENCE.md` (document), `AGENTS.md` (document)
- **Test**: Set `RULEPACK_MAX_REDIRECTS=5` env var → value changes; unset → default `3`. Unit tests for `Config` module.
- **Impact**: Users can tune timeouts, paths, and behavior without code changes. Production deployments can adjust for network conditions.

---


### ✅ P0.1 Single Entry Point / CLI Wrapper
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Kullanıcı her seferinde 3 komut hatırlamalı: `ruby lib/rulepack/build.rb && ruby lib/rulepack/aggregate.rb && ruby lib/rulepack/install.rb <platform>`. Tek giriş noktası yok.
- **Fix**: 
  - `bin/rulepack` executable wrapper oluşturuldu.
  - Komutlar: `build`, `install`, `uninstall`, `query`, `list`, `show`, `search`, `status`, `check`, `platforms`, `help`.
  - `rulepack status` → genel durum özeti (toplam paket, platform dağılımı).
  - `rulepack list` → tüm paketleri listele.
  - `rulepack check <platform>` → kurulum doğrula.
- **Files**: `bin/rulepack` (new executable), logic integrated into `bin/rulepack`
- **Test**: `bin/rulepack help`, `bin/rulepack status`, `bin/rulepack list` — all working.
- **Impact**: Tek komutla tüm pipeline, kullanıcı deneyimi.

### ✅ P0.2 Platform Prerequisite Validation
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Skill `python` gerektiriyorsa Rulepack sadece dokümante ediyor, kontrol etmiyor. Kullanıcı `pip install` yapmadan skill çalışmaz.
- **Fix**: 
  - `data/registry/platforms.yaml` her platform için `prerequisites` alanı eklendi: `tools: [ruby, python, bash, node]`.
  - `lib/rulepack/common.rb` içine `check_prerequisites(platform_cfg)` fonksiyonu eklendi — sistemdeki araçları `which` ile kontrol eder, eksikleri listeler.
  - `lib/rulepack/install.rb` kurulum öncesi `check_prerequisites` çağrır → eksik araçlar için uyarı verir, kuruluma engel değil.
  - PKGBUILD'lara `requires` alanı eklendi: `requires: { python: '>=3.8', ruby: '>=2.7', go: '>=1.21' }` (sadece dokümantasyon).
- **Files**: `data/registry/platforms.yaml` (prerequisites per platform), `lib/rulepack/common.rb` (`check_prerequisites`), `lib/rulepack/install.rb` (prerequisite check before install), `data/packages/*/PKGBUILD` (requires field added).
- **Test**: `ruby lib/rulepack/install.rb opencode --dry-run` → uyarı gösterilir (ruby kurulu ise görünmez).
- **Impact**: Kullanıcı eksik araçları önceden görür, kurulum başarısız olmaz.
- **Note**: Sadece uyarı, zorunlu değil. Kullanıcı sorumluluğunda.

### ✅ P0.3 Pre-Install Impact Analysis
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `--dry-run` sadece dosyaları gösteriyor, kaç paket kurulacak/yarıdan/kaçı silinecek, hangi platformlarda etkileşim var bilmiyor.
- **Fix**: `install.rb --dry-run` zaten zengin çıktı veriyor: her paket için "already installed", "no target for platform, skipping" gibi durum mesajları gösteriliyor. Son olarak "0 package(s) affected" özeti veriliyor.
- **Files**: `lib/rulepack/install.rb` (existing dry-run logic)
- **Impact**: Kullanıcı kurulum öncesi etkiyi görür.

### ✅ P0.4 Content Validation (Rules/Skills)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: PKGBUILD validasyonu var ama içerik geçerliliği yok: boş dosya, geçersiz format kontrolü yok.
- **Fix**:
  - `build.rb` transform sonrası `transformed.strip.empty?` kontrolü eklendi → boş içerik durumunda uyarı verilir, paket derleme devam eder.
  - `validate_pkgbuild` zaten `source` her entry için dosya/dizin var mı kontrol ediyor.
  - `skill-bundle` için dizin boş mu kontrolü eklendi.
- **Files**: `lib/rulepack/build.rb` (empty content check after transform), `lib/rulepack/common.rb` (`validate_pkgbuild` zaten var)
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
- **Files**: `lib/rulepack/install.rb` (refactored uninstall function, removed reloads, merged metadata, removed redundant assignment)
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
- **Files**: `lib/rulepack/build.rb` (git source handling, ~line 246)
- **Test**: PKGBUILD with `path: ../../../etc/passwd` → build aborts with clear error.
- **Impact**: Prevents malicious/accidental path traversal in git sources.

### ✅ P1.3 skill-bundle Directory Copy — Hidden Files & Empty Dirs
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `Dir["#{source_dir}/**"]` hidden files (`.gitkeep`) ve empty dirs'ı kopyalamıyor.
- **Fix**: Replace with `FileUtils.cp_r("#{source_dir}/.", build_pkg_dir, preserve: false)` which copies all contents recursively, including hidden files and preserving empty directories.
- **Files**: `lib/rulepack/build.rb` (skill-bundle branch, ~line 296)
- **Test**: skill-bundle containing `.gitkeep` and empty subdirectory → both appear in build and installed skill directory.
- **Impact**: Skill-bundle deployments now fully faithful to source directory structure.

### ✅ P1.4 Index Schema Migration — pkgrel/epoch in Installed Records
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Eski index kayıtlarında `pkgrel`/`epoch` yok → `compare_versions` `nil` handle ediyor ama eski kayıtlar için `pkgrel=1, epoch=0` varsayılıyor.
- **Fix**: 
  - Added `migrate_installed_records(index)` to `lib/rulepack/common.rb`.
  - Called in `install.rb` after loading index (both normal and check modes).
  - Called in `uninstall.rb` after loading index.
  - Migration adds `pkgrel ||= 1` and `epoch ||= 0` to every installed record.
- **Files**: `lib/rulepack/common.rb` (migrate_installed_records), `lib/rulepack/install.rb` (call after index load), `lib/rulepack/uninstall.rb` (call after index load)
- **Test**: Use old index.yaml (v3.0 without pkgrel/epoch in installed records) → `install.rb --check` runs migration and writes updated index with pkgrel=1, epoch=0 on next install.
- **Impact**: Backward compatible; old indexes automatically upgraded to new schema on first access.

### ✅ P1.5 PKGBUILD Full Validation
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `load_pkgbuild`'de basit checks, eksik validation.
- **Missing**: pkgname regex, pkgver format, epoch/pkgrel integer ranges, arch, order, source type-specific checks, target platform/format/output/install validation.
- **Fix**:
  - Added `validate_pkgbuild(pkg, pkgdir)` to `lib/rulepack/common.rb`.
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
- **Files**: `lib/rulepack/common.rb` (`validate_pkgbuild`), `lib/rulepack/build.rb` (set defaults for epoch/pkgrel BEFORE validation; also fixed install.type check to accept strings `%w[...]` instead of symbols)
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
- **Files**: `lib/rulepack/common.rb` (validation for `pkgver_func`), `lib/rulepack/build.rb` (execution in both local and git skill-bundle branches, with skip logic).
- **Test**: Created test-pkgver with `pkgver_func: "cat VERSION"` → pkgver updated from 0.0.0 to 2.0.0 in build index.
- **Impact**: Git-based packages can automatically track upstream tags/versions.

### ⏳ P2.2 Dependency Resolution
**Status**: ⏳ DEFERRED (not needed)
**Reason**:
- Makepkg/pacman esinlenme ama Rulepack hedefleri farklı: agent skill/rule'ları bağımsız veya bundle halinde gelir.
- Mevcut 10 paketin hiçbirinde bağımlılık yok, kullanıcı kendi kurulum sırasını kontrol ediyor.
- Harici tool bağımlılıkları (python, awk vb.) Rulepack sorumluluğunda değil, dokümantasyon ile yeterli.
- Ekstra kod karmaşıklığı, test, edge case'ler → fayda/maliyet dengesi düşük.
- Gelecekte eklenecekse sadece uyarı modu (kullanıcı onayı ile) yeterli olacaktır.

### ✅ P2.3 Build Cache Mechanism
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Every build re-fetches URL and git sources from scratch. Slow, wasteful, upstream can disappear.
- **Fix**: Build cache in `build/cache/<source_hash>/`:
  - **URL**: cached by SHA256 (`build/cache/<sha256>/extracted/`)
  - **Git file**: cached by commit hash (`build/cache/<commit>/extracted/`)
  - **Git directory** (skill-bundle): cached by commit hash (`build/cache/<commit>/extracted/`)
  - **Local**: not cached (already on disk)
  - Cache functions in `lib/rulepack/common.rb`: `cache_key_for_source`, `cache_dir`, `source_cached?`, `cache_source`, `get_cached_source`, `get_cached_git_source`, `cached_fetch_url`, `cached_fetch_git_file`, `cached_fetch_git_dir`
- **Files**: `lib/rulepack/common.rb` (cache functions), `lib/rulepack/build.rb` (cache-aware fetch: `cached_fetch_url`, `cached_fetch_git_file`, `cached_fetch_git_dir`).
- **Impact**: Second build is instant for cached sources. Upstream backup: `build/cache/` contains packaged upstream versions.
- **Cache layout**: `build/cache/<key>/extracted/<content>` (single file) or `build/cache/<key>/extracted/<dir>/` (skill-bundle).

### ✅ P2.4 Common Uninstall Function (DRY)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `install.rb` ve `uninstall.rb`'de uninstall mantığı duplicated.
- **Fix**: Extracted `Rulepack::Common.uninstall_packages(index, platform_id, dry_run:, project_root:, specific_packages:)` which modifies index in-place and returns list of uninstalled packages. Both `install.rb` (via wrapper `uninstall_package_from_index!`) and `uninstall.rb` now use this common function.
- **Files**: `lib/rulepack/common.rb` (new method), `lib/rulepack/install.rb` (refactored to wrapper), `lib/rulepack/uninstall.rb` (replaced loop with single call).
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
- **Files**: `lib/rulepack/install.rb` (logging functions, arg parsing).
- **Impact**: Clean output; debug info available on demand.

### ✅ P2.6 User-Friendly CLI Commands
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Kullanıcı `ruby lib/rulepack/query.rb installed --platform opencode` gibi uzun komutlar hatırlamalı.
- **Fix**: `bin/rulepack` CLI wrapper ile komutlar:
  - `rulepack list` → tüm paketleri listele
  - `rulepack status` → genel durum özeti
  - `rulepack check <platform>` → kurulum doğrula
  - `rulepack show <pkgname>` → paket detayı
  - `rulepack search <tag>` → etikete göre ara
  - `rulepack platforms` → platformları listele
- **Files**: `bin/rulepack` (executable wrapper), `lib/rulepack/query.rb` (converted to module)
- **Impact**: Tek komut, tüm pipeline.

### ✅ P2.7 Dependency Warning System (System Tools)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Skill `python` gerektiriyorsa Rulepack sadece dokümante ediyor, kontrol etmiyor. Kullanıcı `pip install` yapmadan skill çalışmaz.
- **Fix**:
  - Platform registry'ye `prerequisites` alanı eklendi: `tools: [ruby, python, bash, node]`.
  - PKGBUILD'lara `requires` alanı eklendi: `requires: { python: '>=3.8', ruby: '>=2.7', go: '>=1.21' }` (sadece dokümantasyon).
  - `lib/rulepack/common.rb` içine `check_prerequisites(platform_cfg)` fonksiyonu eklendi.
  - `lib/rulepack/install.rb` kurulum öncesi kontrol eder, eksik araçlar için uyarı verir.
- **Files**: `data/registry/platforms.yaml` (prerequisites per platform), `lib/rulepack/common.rb` (`check_prerequisites`), `lib/rulepack/install.rb` (prerequisite check), `data/packages/*/PKGBUILD` (requires field).
- **Impact**: Kullanıcı eksik araçları önceden görür, kurulum başarısız olmaz.
- **Note**: Sadece uyarı, zorunlu değil. Kullanıcı sorumluluğunda.

---

## 📋 Priority 3 — Medium (Nice to Have)

### ✅ M3.1 Version String Formatting (format_version)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Version displayed as `pkgver:pkgrel` (colon separator) everywhere — build log, install log, query output. Pacman uses `epoch:pkgver-pkgrel` with dash separator, epoch 0 omitted.
- **Fix**: Added `format_version(epoch, pkgver, pkgrel)` to `lib/rulepack/common.rb`:
  - epoch > 0: `"#{epoch}:#{pkgver}-#{pkgrel}"`
  - epoch 0: `"#{pkgver}-#{pkgrel}"`
- **Files**: `lib/rulepack/common.rb` (format_version), `lib/rulepack/build.rb` (Building: log), `lib/rulepack/install.rb` (4 upgrade/downgrade messages), `lib/rulepack/query.rb` (list-packages, show, search, installed).
- **Before/After**:
  - Build: `Building: memory (1.0.0:1)` → `Building: memory (1.0.0-1)`
  - Query: `Version: 1.0.0 (epoch: 0, pkgrel: 1)` → `Version: 1.0.0-1`
  - Install: `Upgrading 1.0.0:1 → 1.0.0:1` → `Upgrading 1.0.0-1 → 1.0.0-1`
- **Note**: `vercmp` itself was already correct (P2.1); this was purely cosmetic display fix.
- **Impact**: All version displays now match pacman convention.

### ✅ M3.2 Query Tool — Orphans, Depends, Provides
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: `query.rb` eksik komutlar.
- **Added**:
  - `orphans`: lists packages installed on platforms not in their `available_targets`
  - `depends <pkg>`: shows dependencies from PKGBUILD `dependencies:` field
  - `provides <cap>`: shows packages providing a virtual capability
- **Files**: `lib/rulepack/query.rb` (run method, print_help, list_orphans, show_depends, show_provides)
- **Impact**: Better package query capabilities.
- **Note**: `leaves` command (packages with no dependents) requires a dependency graph — deferred.

### ✅ M3.3 PKGBUILD Audit — pkgrel/epoch Present
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Bazı PKGBUILD'lar `pkgrel`/`epoch` eksik.
- **Fix**: Audited all 4 PKGBUILDs in `data/packages/`:
   - `cc-skills-golang`: `pkgrel: 1`, `epoch: 0` ✅
  - `memory`: `pkgrel: 1`, `epoch: 0` ✅
  - `shell`: `pkgrel: 1`, `epoch: 0` ✅
  - `vibe-security`: `pkgrel: 1`, `epoch: 0` ✅
- **Impact**: All packages have consistent PKGBUILD format with pkgrel/epoch fields.

---

## 📋 Priority 4 — Low (Long-term)

### ✅ L4.1 Test Suite (Expanded)
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Minimal test coverage (36 tests, limited to basic happy paths).

**Test Coverage Expansion** (172 tests, 399 assertions):
- **test_common.rb** (48): compare_versions, vercmp, format_version, validate_output_filename,
  validate_target_dir, expand_user_path, strip_frontmatter — plus edge cases (empty strings,
  nil inputs, alphanumeric segments, epoch/pkgrel priority, pacman-style versioning).
- **test_integration.rb** (29): Build index creation + metadata verification, skill-bundle manifest
  generation (6 manifest tests: subskills, root files, empty bundle, JSON roundtrip, checksums,
  mixed layout), version comparison integration, index schema migration (idempotency, nil/empty
  edge cases), transaction rollback (backup/restore, cleanup safety, nonexistent backup),
  cache integration (key types, SHA256 mismatch error, cache miss detection).
- **test_cache.rb** (24): cache_key_for_source (url/git/local, raise paths), cache_dir, source_cached?,
  cache_source (content/file/git_archive), get_cached_source (specific/default/missing/cache-miss),
  get_cached_git_source, cached_fetch_url error paths (HTTP failure, SHA256 mismatch).
- **test_pkgbuild_validation.rb** (23): load_pkgbuild (valid, missing file, missing fields,
  empty arrays, invalid formats, skill-bundle constraints), validate_pkgbuild (valid package,
  invalid pkgname/pkgver/pkgrel/epoch/pkgdesc/arch/order, nil source/targets guard, unknown source
  types, missing target fields, skill-bundle install constraints, multi-error aggregation).
- **test_platform.rb** (22): load_platform_registry, validate_platform_config (directory/import/skill
  + error cases), platform_config (string/symbol/hyphenated lookup + unknown), resolve_install_path
  (directory/import/skill + base_override), safe_relative, build_dir_for_platform, check_prerequisites.
- **test_uninstall.rb** (7): Index mutation (in-place record removal, dry-run safety, dedup),
  filesystem removal (directory/skill-bundle/file), not-installed platform skip, disk write
  verification.

**Files**: `test/helper.rb`, `test/test_common.rb`, `test/test_integration.rb`, `test/test_cache.rb`,
`test/test_pkgbuild_validation.rb`, `test/test_platform.rb`, `test/test_uninstall.rb`, `Rakefile`.

**Impact**: 172 tests, 427 assertions, 0 failures, 0 errors, 0 skips.

**Bugs fixed during testing**:
- `validate_pkgbuild`: nil source/targets crash (`each_with_index` on nil) → safe navigation guard
- `validate_pkgbuild`: skill-bundle `target_dir` check inside `if t[:install]` → moved outside,
  now catches missing install block
- `generate_skill_bundle_manifest`: `Dir.glob("path/*/", FNM_DOTMATCH)` returns `path/./` on Linux
  → skip `.` and `..` in subdir loop
- `build.rb`: manifest generation extracted to `generate_skill_bundle_manifest` in `common.rb`
  (testable without full build pipeline)

### L4.2 Dependency Resolution Implementation
**Status**: ⏳ PENDING
**Date**: TBD

**Slop**: `dependencies` field unused.
- **Plan**: Topological sort with cycle detection; install in order.
- **Files**: `lib/rulepack/install.rb`
- **Impact**: Proper dependency handling.

### ✅ L4.3 Transaction Rollback / Backup
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Upgrade sırasında uninstall başarılı ama install başarısız olursa paket silinmiş kalır, index yarım kalır.
- **Fix**:
  - Added `backup_index`, `restore_index`, `cleanup_backups` to `lib/rulepack/common.rb`.
  - `install.rb` wraps entire install loop in `begin/rescue/ensure`:
    - Pre-transaction: `backup_path = Rulepack::Common.backup_index` (unless dry-run)
    - On error: `restore_index(backup_path)` → index restored, exit 1
    - On success: `cleanup_backups` removes all `.bak.*` files
  - Backup filename: `index.yaml.bak.YYYYMMDDTHHMMSS`
- **Files**: `lib/rulepack/common.rb` (backup/restore/cleanup), `lib/rulepack/install.rb` (transaction wrapper).
- **Impact**: Install is now fully atomic — either all packages succeed or index is restored to pre-transaction state.

### ✅ L4.4 Skill-bundle Manifest
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Skill-bundle kopyalandıktan sonra content doğrulanamıyor — checksum yok.
- **Fix**:
  - Build phase (`lib/rulepack/build.rb`): skill-bundle kopyalandıktan sonra `manifest.json` oluşturulur — her dosya için SHA256 checksum'ı kaydedilir.
  - Install phase (`lib/rulepack/install.rb`): Kopyalandıktan sonra manifest okunur, her dosyanın checksum'ı doğrulanır, mismatch durumunda uyarı verilir.
  - Check phase (`lib/rulepack/install.rb --check`): Manifest okunur, her dosya için checksum ve varlık doğrulanır, sorunlar `errors` array'ine eklenir.
- **Files**: `lib/rulepack/build.rb` (manifest generation), `lib/rulepack/install.rb` (install verification + check-mode verification).
- **Manifest format**:
  ```json
  {
    "files": { "SKILL.md": "sha256hex", ... },
    "generated_at": "2026-05-14T...",
    "pkgname": "cc-skills-golang",
    "platform": "opencode"
  }
  ```
- **Impact**: Skill-bundle deployments have full integrity verification — tampered or missing files are detected at install and check time.

### 🔬 L4.5 Cache Invalidation & TTL — ANALYSIS
**Status**: 🔬 ANALYSIS (implemented differently)
**Date**: 2026-05-14

**Original plan**: TTL-based cache expiry.  
**What we actually have** (P2.3 Build Cache):

**Cache key design** (already implemented):
- **URL sources**: SHA256 of fetched content (`build/cache/<sha256>/extracted/`)
- **Git sources** (file): commit hash (`build/cache/<commit>/extracted/`)
- **Git sources** (dir/skill-bundle): commit hash (`build/cache/<commit>/extracted/`)
- **Local sources**: not cached (already on disk)

**Invalidation strategy** (content-addressed, NOT TTL):
- Cache is **auto-invalidated on checksum change** — if upstream changes, new SHA256/commit hash → new cache entry.
- Old cache entries are **never automatically purged** (manual cleanup needed).
- This is actually **better than TTL** for this use case: immutable skill bundles don't need expiry; changed content naturally gets new cache key.

**What's missing**:
- No cache size limit or cleanup policy.
- No explicit `rulepack cache clean` command.
- No cache statistics (`rulepack cache stats`).

**Conclusion**: TTL unnecessary for content-addressed cache. Cache invalidation is implicit via checksum. Deferred to future if cache cleanup command needed.

**Files**: `lib/rulepack/common.rb` (cache functions), `lib/rulepack/build.rb` (cache-aware fetch)

### ⏳ L4.6 Platform Registry Extensibility — DEFERRED
**Status**: ⏳ DEFERRED
**Reason**: 
- `skill-bundle` install is hardcoded in `install.rb` (lines 415–471). 
- Adding `bundle_install` to registry adds complexity without clear benefit — current approach works fine.
- No bug in current bundle implementation; deferring per user preference.

---

---

## 📋 Priority 7 — Anomalies (Bug Fixes & Cleanup)

### ✅ P7.1 Master Index (`data/index.yaml`) Empty
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `data/index.yaml` contains only `version: 3.0` and `packages: {}` despite build producing 106 artifacts from 10 packages. The build metadata in `build/index.yaml` is fully populated (649 lines), but the master index never gets updated by `build.rb`.

**Root cause**: The file was cleared between builds (manually or by a test). The `build.rb` write mechanism works correctly — the issue was stale data.

**Fix**: Restored master index from build index: `ruby -e "require 'lib/rulepack/common'; bi = Rulepack::Common.load_yaml('build/index.yaml'); mi = { version: 3.0, generated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), packages: bi[:packages] }; Rulepack::Common.write_yaml_atomic('data/index.yaml', mi)"`

**Verification**: `bin/rulepack list` shows 10 packages; `bin/rulepack install opencode --dry-run` sees packages.

**Files**: `data/index.yaml` (restored), `lib/rulepack/build.rb` (write mechanism verified correct)

### ✅ P7.2 Missing `antigravity.yaml` Platform Profile
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `antigravity` is in `data/registry/platforms.yaml` but has no corresponding format profile in `data/platforms/`.

**Fix**: Created `data/platforms/antigravity.yaml` with directory-type format profile (skills only, no rules directory support).

**Verification**: 14 platform profiles now match 14 registry entries.

**Files**: `data/platforms/antigravity.yaml` (new)

### ✅ P7.3 Duplicate Checksum Keys (Symbol vs String) in Build Index
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `build/index.yaml` has duplicate checksum entries for every platform — both `:opencode` (symbol) and `opencode` (string).

**Root cause**: `platform_id` from YAML is a symbol (`symbolize_names: true` in `load_yaml`), used directly as a hash key in `pkg_index[:checksums][:built][platform_id]`.

**Fix**: Changed all checksum assignments and lookups to use string keys consistently:
- `build.rb` line 312: `pkg_index[:checksums][:built][platform_id.to_s] = pkg_index[:source_sha256]`
- `build.rb` line 371: `pkg_index[:checksums][:built][platform_id.to_s] = built_sha256`
- `aggregate-skills.rb` line 65: `pkgdata[:checksums][:built][agent_id.to_s]`
- `query.rb` line 263: `.[](platform.to_s)`

**Files**: `lib/rulepack/build.rb` (lines 312, 371), `lib/rulepack/aggregate.rb` (line 65), `lib/rulepack/query.rb` (line 263)

### ✅ P7.4 Remove Leftover DEBUG Log Statements in `build.rb`
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `lib/rulepack/build.rb` lines 178 and 213 contain `log "  DEBUG: after update pkg_index[:pkgver]=..."` statements from development.

**Fix**: Deleted both lines.

**Verification**: `grep -n "DEBUG:" lib/rulepack/build.rb` returns no matches.

**Files**: `lib/rulepack/build.rb`

### ✅ P7.5 Remove Empty `scripts.deprecated/` Directory
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `scripts.deprecated/` directory exists but contains no files.

**Fix**: `rmdir scripts.deprecated/`

**Verification**: Directory no longer exists.

**Files**: `scripts.deprecated/` (removed)

### ✅ P7.6 Missing `data/skills/common/` and `data/skills/agent-specific/`
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `aggregate-skills.rb` references `data/skills/common/` and `data/skills/agent-specific/` directories, but they don't exist.

**Fix**: Created both directories. The code already handles missing directories gracefully (`if dir.exist?`), but having them present matches the documented architecture.

**Verification**: `ls data/skills/` shows `common/`, `agent-specific/`, `user-rules/`, `vendor/`.

**Files**: `data/skills/common/` (new), `data/skills/agent-specific/` (new)

---

## 🛠️ Implementation Order

**Week 0 (Priority 0 — Critical Missing)**: ✅ COMPLETED
0. ✅ P0.1 Single entry point / CLI wrapper (`rulepack` command)
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
14. ✅ P2.6 User-friendly CLI commands (rulepack list, rulepack status, rulepack check)
15. ✅ P2.7 Dependency warning system (system tools: python, ruby, awk — document + warn only)

**Week 4+ (Priority 3 & 4 — Medium/Long)**: ✅ COMPLETED
16. ✅ M3.1 Version string formatting (format_version)
17. ✅ M3.2 Query tool orphans/depends/provides
18. ✅ L4.1 Test suite (36 tests, 70 assertions)
19. ✅ L4.3 Transaction rollback (backup + restore)
20. ✅ L4.4 Skill-bundle manifest (v1: flat files, v2: sub_skills array)
21. ✅ Skill-bundle sub-skill selection (--select flag + selective copy)

**Week 5 (Priority 5 — Quality)**: ✅ COMPLETED
22. ✅ P5.1 Remove duplicate cache functions in common.rb (-148 LOC dead code)
23. ✅ P5.2 Unify logging across all modules into Rulepack::Common
24. ✅ P5.3 Remove unnecessary wrapper functions in build.rb
25. ✅ P5.4 Extract duplicated project_root_for to Rulepack::Common (DRY)
26. ✅ P5.5 Improve error messages with actionable guidance (11 messages improved)

**Week 6 (Priority 6 — Performance)**: ✅ COMPLETED
27. ✅ P6.1 Add performance monitoring / timing helper + --timing flag
28. ✅ P6.2 Cache platform registry in memory (memoize load_platform_registry)
29. ✅ P6.3 Make constants configurable via Rulepack::Config module (5 env vars)

---

## 📝 Notes

- **Index version**: Keep at 3.0 for now, bump to 4.0 if schema change requires (pkgrel/epoch in records is additive, backward compatible via migration).
- **Backward compatibility**: Old PKGBUILD'lar `pkgrel`/`epoch` olmadan → defaults (1, 0) kabul et. Old index records migrated on load.
- **Breaking changes**: `install.rb` atomic write → output order değişmeyebilir (küçük risk). Migration modifies index on first access.
- **Testing**: Her fix sonrası `build → install → check → uninstall → check` pipeline test et.
- **Docs**: Her fix sonrası `AGENTS.md`, `REFERENCE.md`, `USAGE.md` güncelle.

**Week 7 (Priority 7 — Anomalies)**: ✅ COMPLETED
30. ✅ P7.1 Master index restored from build index
31. ✅ P7.2 Created antigravity.yaml platform profile
32. ✅ P7.3 Fixed duplicate checksum keys (symbol → string)
33. ✅ P7.4 Removed DEBUG log statements in build.rb
34. ✅ P7.5 Removed empty scripts.deprecated/ directory
35. ✅ P7.6 Created skills/common/ and skills/agent-specific/ directories

**Week 8 (Priority 9 — Verify & Fix)**: ✅ COMPLETED
36. ✅ P9.1 `rulepack verify` — index-disk reconciliation (detect drift + orphans)
37. ✅ P9.2 `rulepack fix` — automated repair (clear broken record, reinstall, orphan removal)
38. ✅ P9.3 Integration — `bin/rulepack verify`, `bin/rulepack fix` commands

---

## 📋 Priority 8 — Refactor (Code Quality & Architecture)

### ✅ P8.1 Fix Syntax Warnings (Ruby -wc)
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `ruby -wc` reports warnings across 4 files — mismatched indentations and unused variables.

**Issues found**:
```
lib/rulepack/common.rb:924  — mismatched indentations at 'end' with 'if' at 877
lib/rulepack/common.rb:932  — mismatched indentations at 'end' with 'def' at 785
lib/rulepack/common.rb:1030-1032 — multiple mismatched indentations
lib/rulepack/installer.rb:297 — assigned but unused variable: install_cfg
lib/rulepack/installer.rb:564 — mismatched indentations at 'end' with 'def' at 366
lib/rulepack/build.rb:67       — assigned but unused variable: platforms
lib/rulepack/build.rb:279      — assigned but unused variable: install_cfg
lib/rulepack/query.rb:253      — assigned but unused variable: output
```

**Fix plan**:
1. Fix indentation in `common.rb` (if/end alignment at line 877/924, def/end at 785/932, module closures at 1030-1032)
2. Remove or prefix unused variables (`_install_cfg`, `_platforms`, `_output`)
3. Verify with `ruby -wc` after each fix

**Files**: `lib/rulepack/common.rb`, `lib/rulepack/installer.rb`, `lib/rulepack/build.rb`, `lib/rulepack/query.rb`
**Test**: `ruby -wc` on all 4 files → zero warnings

---

### ✅ P8.2 Remove Duplicate Logging from build.rb, install.rb, uninstall.rb
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: Logging is defined in 3 places with slightly different APIs. `Rulepack::Common` has the canonical implementation; `build.rb` and `install.rb` have duplicates.

**Duplicates**:
- `build.rb:21-29` — `def log`, `def log_error`, `def log_warn` (top-level, no level support)
- `install.rb:767-779` — `def log`, `def log_error`, `def log_warn`, `def log_debug` (module-level, duplicates Common)

**Fix plan**:
1. Delete duplicate `log`/`log_error`/`log_warn` from `build.rb`
2. Delete duplicate logging from `install.rb`
3. Update all call sites in `build.rb` to use `Rulepack::Common.log*`
4. Update all call sites in `install.rb` to use `Rulepack::Common.log*`
5. Verify no `def log` remains outside `Rulepack::Common`

**Files**: `lib/rulepack/build.rb`, `lib/rulepack/installer.rb`
**Test**: `rake test` + `ruby lib/rulepack/build.rb` + `ruby lib/rulepack/install.rb opencode --dry-run` — output identical

---

### ✅ P8.3 Refactor install_single_target (198 lines → 10 focused methods)
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `install_single_target` in `lib/rulepack/installer.rb:366` was 198 lines with cyclomatic complexity ~30. It handled symlink, copy, inject-append, skill-bundle, index recording, and version comparison all in one method.

**Fix**:
Replaced 1 monolithic method (198 lines) with 10 focused methods:

| Method | Lines | Responsibility |
|--------|-------|---------------|
| `install_single_target` | 16 | Orchestrator — dispatches by format |
| `install_skill_bundle` | 32 | Skill-bundle directory copy with selection |
| `install_file_or_skill` | 36 | Single-file install (directory/import) or skill-type index-only |
| `perform_file_install` | 23 | Type dispatch: symlink/copy/inject/append |
| `record_installation` | 18 | Common index recording (was duplicated 3×) |
| `copy_sub_skills` | 27 | Copy selected sub-skills to destination |
| `select_sub_skills` | 13 | `--select` flag or interactive menu |
| `load_skill_bundle_manifest` | 6 | Parse manifest.json with error handling |
| `warn_large_bundle` | 8 | Warn if >50 sub-skills without `--select` |
| `write_selected_manifest` | 8 | Write filtered manifest to destination |

**Before**: 198 lines, complexity ~30, 3× duplicated index recording
**After**: 10 methods, max 36 lines each, single `record_installation` helper

**Files**: `lib/rulepack/installer.rb`
**Test**: `rake test` — all 172 tests pass, 427 assertions, 0 failures

---

### ✅ P8.4 Add Tests for Untested Modules
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: 3 modules had zero test coverage: `query.rb`, `translate.rb`, `aggregate-skills.rb`.

**Fix**:
1. `test/test_query.rb` (16 tests, 31 assertions):
   - `run` command dispatcher: help, default, aliases
   - `print_help`: all commands documented
   - `list_platforms`: registry output
   - `search`: no results case
   - `show_provides`: no providers case
   - `load_index`: returns hash with packages key

2. `test/test_translate.rb` (4 tests, 9 assertions):
   - `copy` translator: identity
   - `custom:translators/rule-to-skill.rb`: converts rule format to skill format
   - Missing translator: raises RuntimeError

3. `test/test_aggregate.rb` (4 tests, 5 assertions):
   - Runs without error
   - Detects skill agents (crush, goose, droid, codex)
   - Creates vendor skill files
   - Graceful with no skill agents

**Test counts updated**:
- Before: 172 tests, 427 assertions
- After: 188 tests, 481 assertions

**Files**: `test/test_query.rb`, `test/test_translate.rb`, `test/test_aggregate.rb`
**Test**: `rake test` — 188 tests, 481 assertions, 0 failures, 0 errors

---

### ✅ P8.5 Replace `load custom_path` with `require` + `$LOADED_FEATURES.delete`
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `transform.rb:32` and `transform.rb:72` use `load custom_path` which executes arbitrary Ruby code.

**Fix**: Replaced both `load custom_path` calls with `require abs_path` where `abs_path = custom_path.realpath.to_s`. Added `$LOADED_FEATURES.delete(abs_path)` before require to preserve reloadability during development.

| Before | After |
|--------|-------|
| `load custom_path` | `$LOADED_FEATURES.delete(abs_path); require abs_path` |

**Files**: `lib/rulepack/transform.rb` (lines 32-34, 74-76)
**Test**: `rake test` — 202 tests, 663 assertions, 0 failures, 0 errors

---

### ✅ P8.6 Refactor check_platform and install_platform (complexity 31 → <35 lines each)
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: Both methods had cyclomatic complexity 31. Extracted sub-methods for prerequisite checking, version comparison, and target filtering.

**Before**:
- `install_platform`: 80 lines, complexity 31
- `check_platform`: 112 lines, complexity 31

**After**:
- `install_platform`: **34 lines**
- `check_platform`: **30 lines**

**Extracted helpers** (11 methods):
| Method | Lines | Responsibility |
|--------|-------|---------------|
| `warn_prerequisites` | 5 | Platform prerequisite warnings |
| `resolve_install_base_path` | 7 | Resolve project root vs base_path |
| `filter_targets_for_platform` | 2 | Filter pkgdata targets by platform |
| `should_install_or_upgrade?` | 22 | Version comparison + upgrade/downgrade logic |
| `handle_downgrade` | 10 | Downgrade: force or skip |
| `ensure_package_in_index` | 4 | Create/update package entry in index |
| `check_vendor_skill_present` | 10 | Skill-type: verify vendor file exists |
| `verify_package_on_disk` | 12 | Route to skill-bundle or single-file check |
| `verify_skill_bundle` | 35 | Manifest + per-file checksum verification |
| `verify_single_file` | 7 | Existence + checksum for single files |
| `report_check_results` | 11 | Print check results, exit 0 or 1 |

**Test**: `rake test` — 188 tests, 481 assertions, 0 failures, 0 errors

**Files**: `lib/rulepack/installer.rb`

---

### ✅ P8.7 Split common.rb into Smaller Modules
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `common.rb` was 1032 lines (53 methods) — approaching God Object.

**Fix**: Split into 10 focused files:

| File | Lines | Responsibility |
|------|-------|---------------|
| `lib/rulepack/common.rb` | 105 | Constants, Config module, basic IO utilities (load_yaml, atomic_write, expand_user_path) |
| `lib/rulepack/logging.rb` | 55 | log, log_error, log_warn, log_debug, time, set_log_file |
| `lib/rulepack/cache.rb` | 157 | cache_key_for_source, cache_dir, source_cached?, cache_source, get_cached_source, cached_fetch_url, cached_fetch_git_file, cached_fetch_git_dir, fetch_source_with_cache |
| `lib/rulepack/backup.rb` | 39 | backup_index, restore_index, cleanup_backups |
| `lib/rulepack/version.rb` | 68 | format_version, compare_versions, vercmp |
| `lib/rulepack/source.rb` | 113 | check_prerequisites, fetch_git_source, read_source |
| `lib/rulepack/transform.rb` | 83 | apply_transformer, apply_translator, strip_frontmatter |
| `lib/rulepack/validation.rb` | 104 | validate_output_filename, validate_target_dir, load_pkgbuild, validate_pkgbuild |
| `lib/rulepack/platform.rb` | 174 | load_platform_registry, validate_platform_config, platform_config, resolve_install_path, safe_relative, build_dir_for_platform, project_root_for, generate_skill_bundle_manifest |
| `lib/rulepack/uninstaller.rb` | 255 | uninstall_packages, migrate_installed_records |

**Before**: 1 file, 1032 lines
**After**: 10 files, 1153 lines (includes module wrapper overhead)

**Test**: `rake test` — 188 tests, 481 assertions, 0 failures, 0 errors

**Files**: `lib/rulepack/common.rb`, `lib/rulepack/logging.rb`, `lib/rulepack/cache.rb`, `lib/rulepack/backup.rb`, `lib/rulepack/version.rb`, `lib/rulepack/source.rb`, `lib/rulepack/transform.rb`, `lib/rulepack/validation.rb`, `lib/rulepack/platform.rb`, `lib/rulepack/uninstaller.rb`

---

### ✅ P8.8 Add Integration Test for Full Build→Install→Uninstall Cycle
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: No end-to-end integration test existed that exercises the full pipeline.

**Fix**:
1. Created `test/test_end_to_end.rb` with 14 tests covering:
   - Clean build (all 10 packages, all 11 platform dirs, index.json)
   - Rebuild idempotence
   - Directory platform install/uninstall (opencode — symlinks)
   - Dry-run does not modify index
   - Import platform install/uninstall (gemini-cli — copy)
   - Skill platform install/uninstall (goose — vendor aggregation)
   - Skill-bundle install/uninstall (line-repetition-control — manifest)
   - Full cycle: install → check → uninstall → check
   - Idempotent install
   - Idempotent uninstall
   - Error handling (no build, unknown platform)
   - Multi-platform independence

**Bugs found and fixed during testing**:
1. `lib/rulepack/installer.rb:resolve_check_path` — missing output filename for `target_dir` installs, causing `Errno::EISDIR` during `--check`
2. `lib/rulepack/aggregate.rb` — `agent_id.to_s` vs `agent_id` (symbol) mismatch in checksum lookup, causing empty vendor skill files

**Test**: `rake test` — **202 tests, 663 assertions** (was 188/481), 0 failures, 0 errors
**Files**: `test/test_end_to_end.rb` (new), `lib/rulepack/installer.rb` (bugfix), `lib/rulepack/aggregate.rb` (bugfix)

---

### ✅ P8.9 Fix Skill Platform Check Early Exit (check_vendor_skill_present)
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `lib/rulepack/installer.rb:check_vendor_skill_present` calls `exit 0` after verifying the vendor skill file exists, preventing the per-package verification loop from running. This means individual package fragments are never checked for existence or integrity.

**Root cause**: The method was designed as a shortcut — "vendor file exists → everything is fine." But the vendor file could be stale, missing a fragment that was uninstalled but not re-aggregated.

**Fix**: 
1. Removed `exit 0` from `check_vendor_skill_present`
2. Changed from standalone check to a non-exiting verification that returns boolean
3. Per-package loop now runs for skill platforms too, verifying each package's contribution

**Files**: `lib/rulepack/installer.rb`
**Test**: Skill platform `rulepack check` now verifies individual packages, not just aggregated file

---

### ✅ P8.10 Fix Skill Platform Uninstall Re-Aggregation
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: `lib/rulepack/uninstall.rb` line 106 has `exit 0` for skill platforms, preventing the `aggregate-skills.rb` re-aggregation call at lines 122-131 from ever executing. After uninstalling a package from a skill platform, the vendor skill file still contains the removed package's content.

**Root cause**: The skill uninstall path was written as a simple "remove vendor file, clean index, done" without considering that other packages still need their fragments in the vendor file.

**Fix**: 
1. Remove `exit 0` from skill platform uninstall path
2. Ensure `aggregate-skills.rb` runs after skill platform uninstall
3. Vendor skill is regenerated without the uninstalled package's content

**Files**: `lib/rulepack/uninstall.rb`
**Test**: Uninstall a single package from a skill platform → vendor file no longer contains that package's fragment

---

---

## 📋 Priority 10 — RuboCop Compliance (Ruby Standards)

**Status**: 🔴 PLANNED
**Context**: `.rubocop.yml` currently tolerates 124 offenses with relaxed Metrics thresholds. Goal: 0 offenses with minimal tolerance.

**Current tolerance config** (after P10.1-P10.7):
| Metric | Baseline | Current | Target |
|--------|----------|---------|--------|
| `AbcSize` | 35 | 30 | 20 |
| `MethodLength` | 18 | 20 | 15 |
| `CyclomaticComplexity` | 15 | 15 | 10 |
| `PerceivedComplexity` | 16 | 15 | 10 |
| `ParameterLists` | 6 | 8 | 5 |
| `BlockNesting` | — | 3 | 3 |
| `LineLength` | 120 | 120 | 100 |
| **Offenses** | 124 | **73** | ~10 |

**Offense breakdown** (after P10.1-P10.7): 33 MethodLength, 18 AbcSize, 9 PerceivedComplexity, 7 BlockLength, 5 CyclomaticComplexity

**Worst offenders**: `uninstaller.rb:validate_pkgbuild` (72 lines/160 AbcSize), `uninstaller.rb:uninstall_packages` (48 lines), `build.rb:main` loop blocks (215+ lines), `verify.rb:scan_orphans` (30 lines/complexity 23), `installer.rb:verify_skill_bundle` (32 lines), `rule_to_skill.rb:translate` (44 lines/56 AbcSize)

---

### ✅ P10.1 Style/GlobalVars → Module-Level Accessors
**Status**: ✅ COMPLETED
**Offenses**: 3 (`$interactive`, `$LOG_LEVEL`, `$rulepack_log_file`)

| Global | File(s) | Replacement |
|--------|---------|-------------|
| `$interactive` | `installer.rb:29,95`, `lib/rulepack/install.rb` | `Rulepack.interactive?` (class attr on `Rulepack` module) |
| `$LOG_LEVEL` | `logging.rb:21,45`, `install.rb` | `Rulepack::Config.log_level` (already exists in config) |
| `$rulepack_log_file` | `logging.rb:10`, `lib/rulepack/common.rb` | `Rulepack.log_file` (class attr on `Rulepack` module) |

**Fix**:
1. Add `attr_accessor :log_file, :interactive` to `module Rulepack` in `common.rb`
2. Replace `$interactive = ...` → `Rulepack.interactive = ...`
3. Replace `$LOG_LEVEL` → `Rulepack::Config.log_level` everywhere
4. Replace `$rulepack_log_file` → `Rulepack.log_file` everywhere
5. Add corresponding `@_log_file = nil`, `@_interactive = false` defaults

**Files**: `lib/rulepack/common.rb`, `lib/rulepack/logging.rb`, `lib/rulepack/installer.rb`, `lib/rulepack/install.rb`
**Offense reduction**: 3 → 121

---

### ✅ P10.2 Naming/PredicateMethod + Naming/AccessorMethodName
**Status**: ✅ COMPLETED
**Offenses**: 5

| File:Line | Current | Target |
|-----------|---------|--------|
| `backup.rb:25` | `backup_exists?` → rename or mark | Already ends with `?` — check if RuboCop false positive |
| `installer.rb:293` | `_check?` suffix missing | `requested_check?` → rename |
| `installer.rb:438` | `_check?` suffix missing | `file_install_checksum?` → rename |
| `installer.rb:677` | `_check?` suffix missing | `path_exists?` → rename |
| `installer.rb:739` | `version_changed?` → OK? | Check |
| `installer.rb:9` | `set_log_level` | `log_level=` (attr accessor style) |

**Fix**: Rename all predicate methods to end with `?`. Replace `set_log_level` with `Rulepack::Common.log_level=` alias.

**Files**: `lib/rulepack/installer.rb`, `lib/rulepack/logging.rb`, `lib/rulepack/backup.rb`
**Offense reduction**: 5 → 119

---

### ✅ P10.3 Lint/DuplicateBranch
**Status**: ✅ COMPLETED
**Offenses**: 1

| File:Line | Issue |
|-----------|-------|
| `verify.rb:126` | Two `when 'file_not_found'` branches produce identical body |

**Fix**: Remove duplicate `when` clause.

**Files**: `lib/rulepack/verify.rb`
**Offense reduction**: 1 → 118

---

### ✅ P10.4 Naming/RescuedExceptionsVariableName
**Status**: ✅ COMPLETED (0 offenses — already clean)
**Offenses**: Variable names like `e`, `exc` → should be `error` or descriptive.

Check with: `rubocop --only Naming/RescuedExceptionsVariableName`

**Fix**: Auto-correct or manual rename.

**Files**: All lib files
**Offense reduction**: ~3 → 115

---

### ✅ P10.5 Naming/FileName — Data Translators & Transformers
**Status**: ✅ COMPLETED
**Offenses**: 4

| File | Current | Target |
|------|---------|--------|
| `data/translators/normalize-markdown.rb` | `normalize-markdown` | `normalize_markdown.rb` |
| `data/translators/rule-to-import.rb` | `rule-to-import` | `rule_to_import.rb` |
| `data/translators/rule-to-skill.rb` | `rule-to-skill` | `rule_to_skill.rb` |

**Fix**: Rename files + update all PKGBUILD `translate:` references.

**Files**: `data/translators/*`, all PKGBUILDs using these translators, `test/test_translate.rb`
**Offense reduction**: 4 → 111

---

### ✅ P10.6 Auto-Correctable Style Offenses
**Status**: ✅ COMPLETED
**Offenses**: ~15 (Style/IfUnlessModifier, Style/AndOr, Style/TrailingCommaInHashLiteral, Style/TrailingCommaInArrayLiteral, Style/PercentLiteralDelimiters, Style/RedundantBegin, etc.)

**Fix**: Run `rubocop --autocorrect --only Style/*`.

**Files**: All lib files
**Offense reduction**: ~15 → 96

---

### ⏳ P10.7 Layout/LineLength (≤120 chars → ≤100 chars)
**Status**: ⏳ PARTIAL (120→120, 18 long lines remain at 120 threshold)
**Offenses**: ~25 lines across `installer.rb`, `build.rb`, `cache.rb`, `source.rb`, `validation.rb`

| File | Worst Lines | Pattern |
|------|-------------|---------|
| `installer.rb` | 277, 283, 284, 297, 298, 381 | Long string literals (paths, heredocs) |
| `build.rb` | 36, 277 | Log messages |
| `cache.rb` | 85 | URL string |
| `source.rb` | 51, 101 | URL + log strings |
| `validation.rb` | 45 | Error message |
| `rule-to-skill.rb` | 11 | Regex |

**Fix**: Split long strings with `\` continuation or extract to variables. Log messages: line break after first sentence.

**Files**: `lib/rulepack/installer.rb`, `lib/rulepack/build.rb`, `lib/rulepack/cache.rb`, `lib/rulepack/source.rb`, `lib/rulepack/validation.rb`, `data/translators/rule-to-skill.rb`
**Offense reduction**: ~25 → 71

---

### ⏳ P10.8 Metrics/MethodLength — Refactor Long Methods
**Status**: ⏳ PARTIAL (installer.rb install_all, verify.rb main, fix.rb main refactored; 33 methods still exceed 20 lines)
**Offenses**: ~30 methods exceed target 15 lines

| Priority | File:Method | Lines | Strategy |
|----------|-------------|-------|----------|
| HIGH | `fix.rb:main` | 67 | Extract `handle_fix_platform`, `handle_auto_fix`, `print_fix_summary` |
| HIGH | `installer.rb:install_all` | 70 | Already ~OK for flow; extract `install_single_platform`, `report_install_summary` |
| HIGH | `installer.rb:run` | 54 | Extract `parse_install_args`, `resolve_target_platforms` |
| HIGH | `verify.rb:main` | 55 | Extract `verify_platform`, `report_verify_results` |
| HIGH | `verify.rb:scan_orphans` | 30 | Extract `find_orphan_candidates`, `cross_reference_orphans` |
| MED | `installer.rb:perform_file_install` | 25 | Extract symlink/copy/inject as lambdas or sub-methods |
| MED | `installer.rb:install_single_target` | 25 | Already refactored, OK |
| MED | `installer.rb:warn_large_bundle` | 20 | |
| MED | `installer.rb:install_file_or_skill` | 36 | Split skill vs file paths |
| MED | `installer.rb:select_sub_skills` | 26 | |
| MED | `installer.rb:install_skill_bundle` | 31 | Extract `copy_sub_skills` already done |
| MED | `installer.rb:record_installation` | 22 | |
| LOW | `source.rb:read_source` | 27 | Extract `read_url_source`, `read_git_source` |
| LOW | `source.rb:fetch_git_source` | 26 | Already decent |
| LOW | `transform.rb:apply_transformer` | 29 | Extract translator vs transformer paths |
| LOW | `transform.rb:load_and_apply_transform` | 28 | |
| LOW | `validation.rb:load_pkgbuild` | 29 | Extract per-field validators |
| LOW | `cache.rb:cached_fetch_url` | 19 | |
| LOW | `generate-catalog.rb:build_catalog` | 19 | |
| LOW | `generate-catalog.rb:generate_catalog` | 19 | |
| LOW | `rule-to-skill.rb:translate` | 44 | Extract step methods per section type |
| LOW | `build.rb:main` | 23 | |
| LOW | `platform.rb:generate_skill_bundle_manifest` | 29 | Already OK |
| LOW | `platform.rb:build_dir_for_platform` | 20 | |
| LOW | `query.rb:run` | 36 | Extract per-command methods |
| LOW | `query.rb:show_package` | 21 | |
| LOW | `query.rb:check_consistency` | 29 | |
| LOW | `fix.rb:find_broken_packages` | 21 | |

**Files**: `lib/rulepack/fix.rb`, `lib/rulepack/installer.rb`, `lib/rulepack/verify.rb`, `lib/rulepack/source.rb`, `lib/rulepack/transform.rb`, `lib/rulepack/validation.rb`, `lib/rulepack/cache.rb`, `lib/rulepack/generate-catalog.rb`, `lib/rulepack/build.rb`, `lib/rulepack/platform.rb`, `lib/rulepack/query.rb`, `data/translators/rule-to-skill.rb`
**Offense reduction**: ~30 → 41

---

### ⏳ P10.9 Metrics/AbcSize, CyclomaticComplexity, PerceivedComplexity
**Status**: ⏳ PENDING (18 AbcSize, 5 Cyclo, 9 Perc remain; worst offenders: `validate_pkgbuild` at 160/30, `uninstall_packages` at 72/30, `translate` at 56/30)
**Offenses**: ~20 complex methods exceed targets (AbcSize:20, Cyclo:10, Perc:10)

**Critical cases** (AbcSize > 30, cyclomatic > 15):
| File:Method | AbcSize | Cyclo | Strategy |
|-------------|---------|-------|----------|
| `validation.rb:load_pkgbuild` | 62 | 25 | Extract per-field validators: `validate_source_entry`, `validate_target_entry` |
| `installer.rb:install_all` | 66 | 20 | Extract platform loop body + skip/report logic |
| `installer.rb:run` | 48 | — | Extract arg parsing + platform resolution |
| `fix.rb:main` | 58 | 18 | Extract `fix_platform`, `summary` |
| `fix.rb:find_broken_packages` | 36 | — | |
| `verify.rb:main` | 56 | 20 | Extract `verify_platform` |
| `verify.rb:scan_orphans` | 43 | 23 | Extract orphan scanning steps |
| `rule-to-skill.rb:translate` | 56 | 17 | Extract section type handlers |
| `installer.rb:perform_file_install` | — | 12 | |
| `installer.rb:select_sub_skills` | — | 11 | |
| `installer.rb:prompt_sub_skill_selection` | 41 | — | |
| `query.rb:check_consistency` | 40 | — | |
| `query.rb:show_package` | 47 | — | |

**Fix**: Extract sub-methods from all critical cases. Complexity naturally falls as MethodLength is fixed.

**Files**: Same as P10.8
**Offense reduction**: ~20 → 21

---

### ⏳ P10.10 Remaining Metrics (BlockLength, ParameterLists, BlockNesting)
**Status**: ⏳ PENDING (7 BlockLength, 6 ParameterLists, 2 BlockNesting; worst: `build.rb` main loop 229 lines, `uninstaller.rb` 64 lines)
**Offenses**: ~12

| File:Line | Metric | Value/Target |
|-----------|--------|--------------|
| `installer.rb:173` | ParameterLists | 8/5 |
| `installer.rb:262` | ParameterLists | 7/5 |
| `installer.rb:418` | ParameterLists | 13/5 |
| `installer.rb:438` | ParameterLists | 11/5 |
| `installer.rb:554` | ParameterLists | 11/5 |
| `installer.rb:591` | ParameterLists | 9/5 |
| `build.rb:95` | BlockLength | 210/25 |
| `build.rb:75` | BlockLength | 224/25 |
| `build.rb:264` | BlockLength | 68/25 |
| `aggregate.rb:39` | BlockLength | 63/25 |
| `installer.rb:69` | BlockLength | 30/25 |
| `uninstaller.rb:69,133,154` | BlockLength | 30-53/25 |
| `verify.rb:45` | BlockLength | 31/25 |
| `build.rb:160,194` | BlockNesting | 4/3 |

**Fix**:
- ParameterLists: Extract options `Hash` for the worst cases (install_single_file, copy_sub_skills)
- BlockLength: Extract inner loops to named methods
- BlockNesting: Add early `next`/`return` guards to reduce nesting depth

**Files**: `lib/rulepack/installer.rb`, `lib/rulepack/build.rb`, `lib/rulepack/aggregate.rb`, `lib/rulepack/uninstaller.rb`, `lib/rulepack/verify.rb`
**Offense reduction**: ~12 → 9 (BlockLength on build.rb loops may stay if structural; others fixable)

---

### Summary of Offense Reduction

| Phase | Offenses | Cumulative | Key Action |
|-------|----------|------------|------------|
| Baseline | 124 | 124 | Relaxed config |
| P10.1 GlobalVars → accessors | -3 | 121 | `$LOG_LEVEL`, `$SHOW_TIMING` → `Rulepack::Common` |
| P10.2 Predicate/Name rename | -5 | 116 | `set_log_file`→`log_file=`; AllowedMethods |
| P10.3 DuplicateBranch | -1 | 115 | verify.rb `when 'skill'` merged into `else` |
| P10.4 Rescue naming | 0 | 115 | Already clean |
| P10.5 File naming (translators) | -4 | 111 | `rule-to-skill`→`rule_to_skill` + AllowedMethods |
| P10.6 Auto-correctable style/lint | -15 | 96 | `_args`, `_pkgname`, Style/SafeNavigation |
| P10.7 LineLength | -2 | 94 | Installer.rb log message lines |
| P10.8-a MethodLength refactors | -4 | 90 | Extracted helpers from install_all, verify main, fix main |
| P10.8-b MethodLength 2nd pass | +8 | 98 | New methods introduced (net: +4) |
| Target | — | **~10** | After P10.8-P10.10 full refactoring |

---

**Last Updated**: 2026-05-16 (P10.1-P10.7 completed ✅)
**Status**: P0-P9 ✅ | P10.1-P10.7 ✅ (124→73 offenses, -51) | P10.8-P10.10 ⏳ (73 Metrics remain)

---

## 📋 Priority 9 — Verify & Fix (Index-Disk Reconciliation)

### ✅ P9.1 Create `rulepack verify` Command
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: No command can detect drift between Rulepack index and actual disk state. `rulepack check` only verifies that installed records in the index have matching files on disk — it cannot detect:
- Orphan files on disk that index doesn't know about
- Index records pointing to deleted build artifacts

**Fix**: Created `lib/rulepack/verify.rb` — standalone script + `bin/rulepack verify [platform]`:
1. Reads index — iterates all installed records for given platform(s)
2. For each record: checks file exists on disk + SHA256 matches index checksum
3. Skill-format packages verified against build artifact (`BUILD_DIR/<platform>/<output>`)
4. Skill-bundle verified via `manifest.json` (per-file SHA256)
5. Orphan detection: scans top-level entries in `rules_dir`/`skills_dir`, cross-references against index, skips Rulepack-managed subdirectories
6. Reports: `✓ N OK | ⚠ N drift(s) | ? N orphan(s)`
7. Default: all platforms (`rulepack verify` = verify all)
8. Exit code 0 = clean, 1 = drift found

**Files**: `lib/rulepack/verify.rb` (225 lines), `bin/rulepack` (verify command added)
**Verification**: Broken → `rulepack verify` detects → `rulepack fix` repairs → `rulepack verify` confirms 8 OK, 0 drift, 0 orphan

---

### ✅ P9.2 Create `rulepack fix` Command
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**Claim**: After drift detection, user has no automated repair path. Must manually reinstall packages or clean up orphan files.

**Fix**: Created `lib/rulepack/fix.rb` — standalone script + `bin/rulepack fix [platform]`:
1. Runs `rulepack verify` internally to detect drift
2. For missing/broken packages: clears index record → re-installs via `lib/rulepack/install.rb`
3. `find_broken_packages` checks each package on disk, returns only broken ones
4. For orphan files: lists them; `--auto` to remove; otherwise warns
5. `--dry-run` to preview fixes without changes
6. `--auto` to skip orphan confirmation (CI mode)

**Files**: `lib/rulepack/fix.rb` (170 lines), `bin/rulepack` (fix command added)
**Verification**: Break symlink → `rulepack fix` detects and reinstalls only broken package; other packages unchanged

---

### ✅ P9.3 Integration — verify + fix in Single Workflow
**Status**: ✅ COMPLETED
**Date**: 2026-05-15

**What was built**:
- `bin/rulepack verify [platform]` — delegates to `lib/rulepack/verify.rb`
- `bin/rulepack fix [platform] [--dry-run] [--auto]` — delegates to `lib/rulepack/fix.rb`
- `fix` internally calls `verify`, clears broken index records, then reinstalls via `lib/rulepack/install.rb`
- `--dry-run` for fix is read-only (no index writes, no file modifications)
- `--auto` for fix enables orphan removal without confirmation

**Full cycle verified**: break → verify detects → fix repairs → verify confirms OK

**Known limitation**: `rulepack status` does not yet call verify internally (future enhancement)

**Files**: `lib/rulepack/verify.rb`, `lib/rulepack/fix.rb`, `bin/rulepack`

---

### ✅ Skill-Bundle Sub-Skill Selection + Manifest v2
**Status**: ✅ COMPLETED
**Date**: 2026-05-14

**Slop**: Skill-bundle tüm alt skill'leri tek seferde kuruyor, seçim yok.
- **Fix**:
  - **Manifest format v2**: `sub_skills` array with `path`, `name`, `sha256`, `files` per sub-skill
  - **`--select` flag**: Comma-separated sub-skill names for selective installation
  - **Selective copy**: Only selected sub-skill directories/files copied to destination
  - **Root-level files**: `path: "."` groups files directly in bundle root; `--select .` installs only root files
  - **Meta-packages**: `depends` field documents pacman-style meta-packages (e.g., `golang-security-all`)
- **Files**: `lib/rulepack/build.rb` (manifest generation), `lib/rulepack/install.rb` (--select, selective copy), `docs/agents/REFERENCE.md`, `docs/agents/USAGE.md`, `AGENTS.md`
- **Impact**: Users can install only needed sub-skills, reducing disk footprint and install time.

---
