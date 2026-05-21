# Improvement Plan — Active Items

> **Completed work**: See [docs/improvement-plan/completed-P0-P13.md](docs/improvement-plan/completed-P0-P13.md) for P0-P13 (all completed).
>
> **Test status**: 277 tests, 855 assertions, 0 failures, 0 errors, 6 network skips.

---

## 📋 Priority 14 — True Pacman, Mock Git & Rollbacks

### ⏳ P14.1 True Pacman CLI Routing
**Status**: ⏳ PLANNED
**Severity**: CLI Compliance
**Date**: 2026-05-20

**Slop**: Top-level pacman flags (`-S`, `-R`, `-Qk`, `-F`, `-Q`) are parsed by `lib/rulepack/cli_parser.rb` and the sub-CLI scripts, but they are not routed correctly at the main `bin/rulepack` entry point. Running `rulepack -S <package>` fails with `Unknown command: -S`.

- **Fix**:
  1. In `bin/rulepack`, detect if the first argument (command) is a pacman-style flag: `-S`, `-R`, `-Qk`, `-F`, or `-Q`.
  2. Map them as follows:
     - `-S` ➡️ `install`
     - `-R` ➡️ `uninstall`
     - `-Qk` ➡️ `verify`
     - `-F` ➡️ `fix`
     - `-Q` ➡️ `query`
  3. Re-prepend the flag back to the `argv` array passed to the script so that sub-scripts can parse it as expected (e.g. `install.rb` shifts `-S`).
- **Files**: `bin/rulepack`
- **Test**: `bin/rulepack -S memory -t opencode --dry-run` runs successfully.

---

### ⏳ P14.2 Query CLI `-Q` Flag Support
**Status**: ⏳ PLANNED
**Severity**: CLI Compliance
**Date**: 2026-05-20

**Slop**: `lib/rulepack/query.rb` parses `ARGV` manually instead of using `CliParser.parse`, and does not support the `-Q` flag, resulting in failure when running `rulepack -Q ls`.

- **Fix**:
  1. Update `lib/rulepack/query.rb`'s `run` method to check if `argv.first` is `'-Q'`.
  2. If present, shift it out of the array.
- **Files**: `lib/rulepack/query.rb`
- **Test**: `bin/rulepack -Q ls` displays the package list correctly.

---

### ⏳ P14.3 E2E Test Network Isolation (Mock Git Repositories)
**Status**: ⏳ PLANNED
**Severity**: Test Reliability & Speed
**Date**: 2026-05-20

**Slop**: Even though full network E2E tests are gated behind `RULEPACK_RUN_NETWORK_E2E=1`, running `rake test` still executes `build.rb` which clones real remote Git repositories from GitHub during `test_build_creates_local_packages_fast`. If run offline, tests hang or fail due to network timeouts.

- **Fix**:
  1. Set up mock local Git repositories inside the test's temporary directory for all packages that declare a `git` source.
  2. Copy/initialize basic structural files in each mock repository and run `git init`, `git config user.name "Test"`, `git config user.email "test@test.com"`, `git add .`, and `git commit` to create a valid HEAD.
  3. Dynamically rewrite the copy of the `PKGBUILD` files in the temp directory to replace the remote `https://` URLs with local `file://` URLs pointing to the mock repositories.
  4. This allows the E2E tests to run 100% offline, isolation-safe, and instantly!
- **Files**: `test/test_end_to_end.rb`
- **Test**: `rake test` runs completely offline with no network skips or hangs.

---

### ⏳ P14.4 Automatic Transaction Rollbacks on Installation Failure
**Status**: ⏳ PLANNED
**Severity**: Correctness & Reliability
**Date**: 2026-05-20

**Slop**: If an installation of a package fails halfway through (e.g. format validation error, folder permission collision, custom transformer crash), the index might be rolled back but previously created/modified files on disk are left in a dirty, partially-installed state.

- **Fix**:
  1. The transaction manager in `lib/rulepack/lib/transaction.rb` already implements `rollback_journal` (which processes created/modified files and directories in reverse order).
  2. Verify and ensure that all file operations (symlinks, file copies, folder creations, appends) consistently record their journal entries via `Rulepack::Transaction.record_journal(ctx, ...)`.
  3. Wrap the main platform installation loops in robust `rescue` blocks that automatically execute `Rulepack::Transaction.transaction_rollback(e, backup_path, journal)` on failure.
- **Files**: `lib/rulepack/installer.rb`, `lib/rulepack/lib/transaction.rb`
- **Test**: Run installation that triggers a collision or mock error mid-way, and verify that all modified/created files are cleanly restored/deleted.

---

### ⏳ P14.5 TUI Selector Pagination (Sliding Window Viewport)
**Status**: ⏳ PLANNED
**Severity**: User Experience
**Date**: 2026-05-20

**Slop**: When using `rulepack install --select`, the TUI selector prints all sub-skills to the screen at once. For packages like `antigravity-skills` (305 sub-skills) or `cc-skills-golang` (42 sub-skills), this scrolls completely off the terminal viewport, corrupting the terminal lines and making navigation impossible.

- **Fix**:
  1. Implement a sliding window viewport of size 10 in `lib/rulepack/lib/tui_selector.rb`.
  2. Only render the current 10 items containing the active cursor index.
  3. Cleanly clear only the 10 printed lines (plus header/footer) during each refresh loop.
  4. Add a footer showing: `(Showing 1-10 of 42 sub-skills, [Space] to toggle, [Enter] to confirm)`.
- **Files**: `lib/rulepack/lib/tui_selector.rb`
- **Test**: Run interactive selection with a large number of options and verify viewport is locked to 10 lines and scrolls smoothly.

---

## 🛠️ Priority 14 Implementation Summary

| # | Item | Severity | Effort | Files | Status |
|---|------|----------|--------|-------|--------|
| 1 | P14.1 True Pacman CLI Routing | 🔴 CLI Compliance | 15 min | bin/rulepack | ⏳ PLANNED |
| 2 | P14.2 Query CLI -Q Support | 🔴 CLI Compliance | 10 min | query.rb | ⏳ PLANNED |
| 3 | P14.3 Mock Git E2E Isolation | 🟡 Test Hygiene | 60 min | test_end_to_end.rb | ⏳ PLANNED |
| 4 | P14.4 Transaction Rollbacks | 🟡 Correctness | 30 min | installer.rb | ⏳ PLANNED |
| 5 | P14.5 TUI Pagination | 🟡 User Experience | 40 min | tui_selector.rb | ⏳ PLANNED |

**Total Estimated Effort**: ~2.5 hours


---

## 📋 Priority 15 — Slop & Gap Remediation (2026-05-20)

**Context**: Full codebase analysis identified 7 slop items and 5 gaps. 277 tests passing, 855 assertions, 0 failures. Items ordered by impact: DRY violations first, then test hygiene, then minor code smells.

**Summary**: 5 refactoring tasks. All are safe, incremental improvements with no behavioral changes.

---

### 🔴 P15.1 Eliminate Inline CLI Parsers in install.rb and uninstall.rb
**Status**: ✅ COMPLETED
**Severity**: DRY — ~95 lines of duplicated parsing
**Date**: 2026-05-20

**Slop**: `lib/rulepack/install.rb` (lines 26-97) contains ~70 lines of inline ARGV parsing that duplicates `CliParser.parse`. `lib/rulepack/uninstall.rb` (lines 27-50) contains ~25 lines of the same.

`CliParser.parse` already handles all required flags: `--target`, `--project`, `--dry-run`, `--force`, `--needed`, `--select`, `--verbose`, `--on-collision`. The inline parsers add only:
- `--check` (install.rb) — install check mode
- `--targets` (install.rb) — show package targets
- `--on-collision` with enum validation (install.rb)
- `--select` with comma-separated or interactive mode (install.rb)

Additionally, `install.rb` maps `--dry-run` to `-p` (confusing; `-p` is `--project` everywhere else).

**Root cause**: CliParser was created later but never replaced the inline parsers.

**Fix**:
1. Extend `CliParser.parse` to handle `--check`, `--targets`, and validate `--on-collision` enum.
2. Replace inline parsers in `install.rb` and `uninstall.rb` with `CliParser.parse(ARGV)` calls.
3. Map parsed options to the local variables expected by each script's dispatch logic.
4. Unify `-p` to mean `--project` everywhere (currently `--dry-run` in install.rb).

**Files**: `lib/rulepack/cli_parser.rb`, `lib/rulepack/install.rb`, `lib/rulepack/uninstall.rb`
**Test**: `rake test` — all 277 tests pass. Manual: `bin/rulepack install --dry-run -t opencode` and `bin/rulepack uninstall --dry-run -t opencode` behave identically.
**Impact**: -95 lines duplicated parsing, single source of truth for CLI argument handling.

---

### 🔴 P15.2 Complete `validate_targets_and_packages` in common.rb
**Status**: ✅ COMPLETED
**Severity**: DRY — validation logic duplicated 3× across fix.rb, verify.rb, install.rb
**Date**: 2026-05-20

**Slop**: `common.rb` has `validate_targets_and_packages` (lines 192-243) but it's incomplete. `fix.rb` (lines 36-120), `verify.rb` (lines 20-85), and `install.rb` (lines 100-145) all contain their own inline validation blocks with additional logic:

| Feature | common.rb | fix.rb | verify.rb | install.rb |
|---------|-----------|--------|-----------|------------|
| Target arg required | ✅ | ✅ | ✅ | ✅ |
| "all" expansion | ✅ | ✅ | ✅ | ✅ (different: uses build_idx targets) |
| Registry validation | ✅ | ✅ | ✅ | ✅ |
| Package existence check | ❌ | ✅ (vs index) | ✅ (vs index) | ✅ (vs build_idx) |
| Project-scope enforcement | ❌ | ✅ | ❌ | ✅ |
| Return target_package | ❌ | ✅ | ✅ | ✅ |

**Root cause**: The shared method was extracted incompletely during P8.7 split.

**Fix**:
1. Add `package_existence_check` option (validate against index or build_idx).
2. Add `project_scope_check` option (enforce `--project` for `scope: project` platforms).
3. Return `[targets, target_package]` tuple.
4. Replace inline validation blocks in `fix.rb`, `verify.rb`, and `install.rb` with the completed shared method.

**Files**: `lib/rulepack/common.rb`, `lib/rulepack/fix.rb`, `lib/rulepack/verify.rb`, `lib/rulepack/install.rb`
**Test**: `rake test` — all 277 tests pass.
**Impact**: -120 lines duplicated validation, single enforcement point for target/package rules.

---

### 🟡 P15.3 Add `index_yaml_path` and `build_dir` Accessors to common.rb
**Status**: ✅ COMPLETED
**Severity**: Test hygiene — `const_set` with `$VERBOSE = nil` in test_fix.rb
**Date**: 2026-05-20

**Slop**: `test/test_fix.rb` lines 18-19:
```ruby
Rulepack::Common.const_set(:INDEX_YAML_PATH, @install_dir.join('index.yaml'))
Rulepack::Common.const_set(:BUILD_DIR, @build_dir)
```

`build_index_path` was properly migrated to an overrideable accessor (P13.3), but `INDEX_YAML_PATH` and `BUILD_DIR` remain as constants. Tests override them via `const_set` with `$VERBOSE = nil` to suppress warnings.

**Fix**:
1. Add `index_yaml_path`/`index_yaml_path=` and `build_dir`/`build_dir=` accessors to `Rulepack::Common`.
2. Update all references from `Common::INDEX_YAML_PATH` to `Common.index_yaml_path` and `Common::BUILD_DIR` to `Common.build_dir`.
3. Update `test/test_fix.rb` to use accessors instead of `const_set`.
4. Remove `$VERBOSE = nil` hack.

**Files**: `lib/rulepack/common.rb`, `test/test_fix.rb`, all consumers of `INDEX_YAML_PATH` and `BUILD_DIR`
**Test**: `ruby -W -Ilib -Itest test/test_fix.rb` — zero constant redefinition warnings.
**Impact**: Eliminates test warning pollution, consistent accessor pattern.

---

### 🟡 P15.4 Fix `test_transaction_rollback.rb` `record_journal` Delegation
**Status**: ✅ COMPLETED (already done in prior session)
**Severity**: Test correctness — implicit delegation through Install module
**Date**: 2026-05-20

**Slop**: `test/test_transaction_rollback.rb` calls `Rulepack::Install.record_journal(ctx, ...)` in 5 test methods. But `record_journal` is defined on `Rulepack::Transaction`, not `Rulepack::Install`. The call works through implicit module resolution — fragile.

**Fix**: Update all 5 calls from `Rulepack::Install.record_journal(ctx, ...)` to `Rulepack::Transaction.record_journal(ctx, ...)`.

**Files**: `test/test_transaction_rollback.rb` (5 call sites)
**Test**: `ruby -Ilib -Itest test/test_transaction_rollback.rb` — 7 runs, 0 failures.
**Impact**: Tests call the correct module directly.

---

### 🟢 P15.5 Fix `$stdout` Capture in `fix.rb` `run_verify`
**Status**: ✅ COMPLETED
**Severity**: Code smell — global stdout mutation
**Date**: 2026-05-20

**Slop**: `fix.rb` `run_verify` reassigns `$stdout` globally to capture `Verify.run` output. Fragile in threaded environments.

**Fix**: Modify `Verify.run` to accept optional `output:` IO parameter (default `$stdout`). In `fix.rb`, pass a `StringIO` instead of reassigning the global.

**Files**: `lib/rulepack/verify.rb` (add `output:` param), `lib/rulepack/fix.rb` (use StringIO param)
**Test**: `rake test` — all tests pass.
**Impact**: Eliminates global mutation.

---

## 🛠️ Priority 15 Implementation Summary

| # | Item | Severity | Effort | Files | Status |
|---|------|----------|--------|-------|--------|
| 1 | P15.1 Inline CLI parsers | 🔴 DRY | 30 min | cli_parser.rb, install.rb, uninstall.rb | ✅ COMPLETED |
| 2 | P15.2 validate_targets_and_packages | 🔴 DRY | 45 min | common.rb, fix.rb, verify.rb | ✅ COMPLETED (install.rb excluded — different data source) |
| 3 | P15.3 INDEX_YAML_PATH/BUILD_DIR accessors | 🟡 Test hygiene | 30 min | common.rb, test_fix.rb, ~10 consumers | ✅ COMPLETED |
| 4 | P15.4 record_journal delegation | 🟡 Correctness | 5 min | test_transaction_rollback.rb | ✅ COMPLETED |
| 5 | P15.5 $stdout capture in fix.rb | 🟢 Code smell | 20 min | verify.rb, fix.rb | ✅ COMPLETED |

**Total Estimated Effort**: ~2 hours


## 📋 Priority 16 — Custom Agent Destegi (2026-05-21)

### Arka Plan

Bazi paketler (ornegin `ruby-update-signatures`) skill degil, **custom agent** tanimi iceriyor.
Skill'ler "nasil yapilir" bilgisi verirken, agent'ler "su gorevi su araclarla yap" tanimidir -- farkli bir hedef dizine kurulmasi gerekir.

Mevcut durumda `ruby-update-signatures`'in `agents/` alt klasoru skill dizinine yanlis yere kuruluyor.

### Platform Agent Mekanizmalari

| Platform | Agent Dizini | Format | Kapsam |
|---|---|---|---|
| OpenCode | `~/.config/opencode/agents/` | Markdown (frontmatter + prompt) | user + project |
| Oh My Pi | `~/.omp/agents/` | YAML (`agent.yml` veya `config.yml`) | user |
| Claude Code | `.claude/agents/` | Markdown (prompt + description) | project |
| Cursor | `.cursor/agents/` | Manifest JSON + prompt dosyalari | project |
| Windsurf | `.windsurf/agents/` | Markdown (Cursor benzeri) | project |
| Crush / Goose / Droid / Codex | Desteklenmiyor | - | - |

### Tasarim

#### P16.1 — PKGBUILD'e `pkg_type: agent` ve `format: agent` ekleme

- `pkg_type: agent` tanitimi (mevcut: `rule`, `skill`, `hybrid`)
- `format: agent` tanitimi -- installer'a platformun `agents_dir` dizinine kopyalama yaptigini soyler
- `ruby-update-signatures` PKGBUILD'i `pkg_type: skill` yerine `pkg_type: agent` olarak guncellenir

#### P16.2 — Platform registry'ye `agents_dir` ekleme

Destekleyen platformlara `agents_dir` alani eklenir:

```yaml
opencode:
  agents_dir: agents/          # ~/.config/opencode/agents/
oh-my-pi:
  agents_dir: agents/          # ~/.omp/agents/
claude-code:
  agents_dir: .claude/agents/  # (project scope)
cursor:
  agents_dir: .cursor/agents/  # (project scope)
windsurf:
  agents_dir: .windsurf/agents/ # (project scope)
```

Agent desteklemeyen platformlar (crush, goose, droid, codex, gemini-cli, qwen-code, github-copilot, antigravity) icin `agents_dir` tanimlanmaz -- bu platformlarda `format: agent` hedefleri skip edilir.

#### P16.3 — Installer'da `format: agent` hedef yolu cozumleme

`install_file_or_skill` metodunda `format: agent` icin yeni dal:
- `platform_cfg[:agents_dir]` varsa -> `base_path.join(agents_dir).join(target_dir or pkgname)`
- `platform_cfg[:agents_dir]` yoksa -> "no agent support" log'u ile skip

Install davranisi: **copy** (symlink degil -- agent dosyalari platform tarafindan okunur, referans degil)

#### P16.4 — `ruby-update-signatures` paketini duzeltme

- `pkg_type: skill` -> `pkg_type: agent`
- Agent desteklemeyen platformlar icin hedefler kaldirilir
- `source.path` zaten dogru: `plugins/ruby-type-signature-skills/agents/`

#### P16.5 — Uninstall, verify, fix destegi

- `format: agent` ile kurulmus dosyalar icin uninstall/verify/fix mekanizmasi
- Mevcut dongu zaten `installed` index'inden calisir, sadece yol cozumlemesi `agents_dir` kullanmalidir

### Dosyalar

| Dosya | Degisiklik |
|---|---|
| `data/registry/platforms.yaml` | `agents_dir` ekleme (5 platform) |
| `lib/rulepack/installer.rb` | `format: agent` hedef yol cozumleme |
| `lib/rulepack/platform.rb` | `resolve_directory_path` icin agent destegi |
| `data/packages/ruby-update-signatures/PKGBUILD` | `pkg_type: agent`, hedef guncelleme |
| `AGENTS.md` | `pkg_type: agent` dokumantasyonu |
| `README.md` | Agent kurulumu ornekleri |

### Test Stratejisi

- Mevcut 277 testin hepsi gecmeli (geriye uyumluluk)
- Yeni test: `format: agent` hedefi icin kurulum/yol dogrulama
- Yeni test: `agents_dir` olmayan platformda `format: agent` skip edilmeli

### Uygulama Sirasi

1. P16.1 — `pkg_type: agent` ve `format: agent` tanimleri (PKGBUILD + dokuman)
2. P16.2 — Platform registry `agents_dir` (5 platform)
3. P16.3 — Installer `format: agent` yol cozumleme
4. P16.4 — `ruby-update-signatures` paketini duzelt
5. P16.5 — Uninstall/verify/fix entegrasyonu
6. Test + commit



---

## Priority 17 — Platform-Specific Agent Format Translator'leri (P17)

**Durum**: Planlaniyor
**Tarih**: 2026-05-21
**Bagimlilik**: P16 (Ozel Agent Destegi) tamamlandi

### Sorun

P16'de `format: agent` ile dosyalari platformlarin `agents/` dizinlerine kopyalama ozelligi eklendi. Ancak her platformun farkli dosya format beklentisi var:

| Platform | Beklenen Format | Dosya Yapisi | Aciklama |
|---|---|---|---|
| **OpenCode** | Markdown + YAML frontmatter | `agents/my-agent.md` | Frontmatter'da name, model, tools, permissions; body'de prompt |
| **Oh My Pi** | Markdown | `agents/my-agent/agent.md` | Dizin icerisinde markdown prompt; otomatik kesif |
| **Claude Code** | Markdown (section schema) | `.claude/agents/my-agent.md` | `## Metadata`, `## System Prompt`, `## Capabilities` section'lari |
| **Cursor** | JSON manifest + markdown | `.cursor/agents/my-agent/agent.json` + `skills.md` | agent.json manifest zorunlu: name, description, model, temperature, triggers |
| **Windsurf** | Markdown (AGENTS.md format) | `.windsurf/agents/my-agent.md` | Basit markdown; otomatik kesif |

**Mevcut davranis**: `format: agent` tum platformlara ayni ham dosyayi kopyalar. Bu yeterli **Oh My Pi** ve **Windsurf** icin, ama **Cursor** (manifest gerekli), **OpenCode** (frontmatter gerekli), ve **Claude Code** (section schema gerekli) icin yetersiz.

### Tasarim

#### P17.1 — Agent format translator'leri

Her platform icin `data/translators/` altinda translator betigi. PKGBUILD'de kullanim:

```yaml
targets:
  - platform: cursor
    format: agent
    translate: custom:data/translators/agent_to_cursor.rb
    output: .
```

Mevcut `translate` mekanizmasi (build_pipeline'da `:translate` asamasi) zaten var. Sadece agent icin yeni translator'ler yazilmasi gerekiyor.

#### P17.2 — Cursor agent.json manifest uretimi

Cursor icin her agent dizininde zorunlu `agent.json`. PKGBUILD'e opsiyonel `agent_config` alani eklenebilir:

```yaml
targets:
  - platform: cursor
    format: agent
    output: .
    agent_config:
      model: claude-3.5-sonnet
      temperature: 0.3
      triggers:
        file_patterns: ["*.rb", "*.rbs"]
```

#### P17.3 — OpenCode YAML frontmatter enjeksiyonu

OpenCode agent dosyalari YAML frontmatter gerektiriyor. Kaynak dosyada frontmatter yoksa, PKGBUILD metadata'sindan uretilmeli.

#### P17.4 — Claude Code section schema donusumu

Claude Code agent dosyalari belirli markdown section'lari bekliyor. Translator bu formati uretmeli.

### Dosyalar

| Dosya | Degisiklik |
|---|---|
| `data/translators/agent_to_cursor.rb` | Yeni — Cursor manifest + prompt uretimi |
| `data/translators/agent_to_opencode.rb` | Yeni — OpenCode frontmatter enjeksiyonu |
| `data/translators/agent_to_claude_code.rb` | Yeni — Claude Code section schema |
| `data/packages/ruby-update-signatures/PKGBUILD` | `translate` ve `agent_config` ekleme |
| `AGENTS.md` | Translator dokumantasyonu |

### Uygulama Sirasi

1. P17.1 — Translator mekanizmasini agent icin aktif et
2. P17.2 — Cursor translator + PKGBUILD agent_config destegi
3. P17.3 — OpenCode translator
4. P17.4 — Claude Code translator
5. Test + commit

### Not

Oh My Pi ve Windsurf icin translator gerekmez — ham markdown yeterli. Mevcut `format: agent` kopyalama bu platformlar icin dogru calisiyor.
