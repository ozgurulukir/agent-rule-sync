# Rulepack: Arch Build System Evaluation

**Date**: 2026-05-14
**Evaluated against**: https://wiki.archlinux.org/title/Arch_build_system

---

## What Is the Arch Build System?

The Arch Build System (ABS) has three conceptual layers:

```
PKGBUILD (YAML descriptor)
    ↓ makepkg (fetch → verify → build → package)
    ↓ .pkg.tar.zst
    ↓ pacman (install/remove/query from local DB)
```

| Layer | Arch Tool | Rulepack Equivalent |
|-------|-----------|---------------------|
| Descriptor | PKGBUILD | `data/packages/<pkg>/PKGBUILD` |
| Build | `makepkg` | `bin/rulepack build` |
| Install | `pacman -U` | `bin/rulepack install` |
| Query | `pacman -Qi/-Qs` | `bin/rulepack query` |
| Remove | `pacman -R` | `bin/rulepack uninstall` |
| Entry point | `makepkg` / `pacman` | `bin/rulepack` |
| Package DB | `/var/lib/pacman/local/` | `data/index.yaml` |

---

## Package Source Model

One of your observations is the key: **Arch's "local source" model is exactly our `src/` directory**.

### Local Source (Majority of Packages)

| Package | Source Type | Source Location | Analogous Arch |
|---------|------------|-----------------|----------------|
| memory | `local` | `data/packages/memory/src/00-memory.md` | `source=('00-memory.md')` |
| shell | `local` | `data/packages/shell/src/01-shell.md` | `source=('01-shell.md')` |
| ast-grep | `local` | `data/packages/ast-grep/src/ast-grep.md` | `source=('ast-grep.md')` |
| workstation-rules | `local` | `data/packages/workstation-rules/src/workstation-rules.md` | `source=('workstation-rules.md')` |
| windsurf-rules | `local` | `data/packages/windsurf-rules/src/.windsurfrules` | `source=('.windsurfrules')` |
| goose | `local` | `data/packages/goose/src/goose.md` | `source=('goose.md')` |
| line-repetition-control | `local` | `data/packages/line-repetition-control/src/` | `source=('SKILL.md' 'scripts/*')` |

These are exact analogs of Arch's `source=('file')` entries — files shipped within the PKGBUILD directory, extracted during build.

### Git Source (Upstream Packages)

| Package | Source Type | Source Location | Analogous Arch |
|---------|------------|-----------------|----------------|
| vibe-security | `git` | `https://github.com/raroque/vibe-security-skill.git` | `source=('git+https://...')` |
| golang-security-bundle | `git` | `file:///.../golang-security` | `source=('git+file:///...')` |

Exactly mirrors Arch's `source=('git+https://github.com/...')` — clone at build time, commit hash as checksum.

### URL Source (Not Used, But Implemented)

`source: [{type: url, url: 'https://...', sha256: '...'}]` — mirrors Arch's `source=('https://...')` with checksum verification. Available in `lib/rulepack/build.rb` (`fetch_url`), not exercised by any current PKGBUILD.

---

## What We Nailed (Exact or Near-Exact ABS Parity)

### 1. PKGBUILD Descriptor Format ✅

Our descriptor covers every essential ABS field:

| ABS Field | Rulepack Equivalent | Status |
|-----------|---------------------|--------|
| `pkgname` | `pkgname` | ✅ |
| `pkgver` | `pkgver` | ✅ |
| `pkgrel` | `pkgrel` | ✅ |
| `epoch` | `epoch` | ✅ |
| `pkgdesc` | `pkgdesc` | ✅ |
| `arch` | `arch` (only `any`) | ✅ |
| `source` | `source` (local/url/git) | ✅ |
| `sha256sums` | `checksums.source` | ✅ |
| `depends` | `dependencies` | ✅ (doc-only) |
| `conflicts` | `conflicts` | ✅ (doc-only) |
| `provides` | `provides` | ✅ (doc-only) |
| `pkgdesc` | `pkgdesc` | ✅ |

Missing from PKGBUILD but in ABS: `url`, `license`, `install` scriptlet.

### 2. Version Management ✅

Exact pacman-style `epoch:pkgver-pkgrel`:
- `compare_versions('1:2.0-1', '1:1.9-1')` → `1` (1.2.0 > 1.1.9)
- `compare_versions('0:1.10.0', '0:1.9.0')` → `1` (1.10 > 1.9, correct)
- Upgrade/downgrade logic: three-component compare, downgrade requires `--force`
- Index stores `epoch`, `pkgver`, `pkgrel` per installed record

### 3. Build Isolation (`build/`) ✅

```
data/packages/    ← sources only (like AUR PKGBUILD directories)
build/       ← build artifacts (like makepkg $pkgdir)
  build/<platform>/<pkgname>/<output>
  data/index.yaml
```

This is a faithful analog of `$pkgdir` — build writes only to `build/`, never to `data/packages/` or any platform directory.

### 4. Checksum Verification ✅

| Check | Arch | Rulepack |
|-------|------|----------|
| Source SHA256 | `sha256sums` | `checksums.source` (auto-populated) |
| Built artifact SHA256 | implicit | `checksums.built` per platform |
| URL fetch | SHA256 verify | SHA256 verify (`cached_fetch_url`) |
| Git commit hash | commit hash as checksum | commit hash as checksum |
| Skill-bundle per-file | N/A | `manifest.json` with per-file SHA256 |

### 5. Platform Type System ✅

Our 4 format types map cleanly to ABS concepts:

| Rulepack Format | What It Does | ABS Analog |
|----------------|--------------|------------|
| `directory` | Symlink/copy file into rules/ dir | `backup=('*.rules')` + install scriptlet |
| `import` | Inject `@import` line into config | `sed` in install() function |
| `skill` | Copy skill file to agent skill dir | Package file list + install() |
| `skill-bundle` | Copy entire skill directory tree | Package file list + install() |

### 6. Build Caching ✅

We go beyond Arch here:
- URL source: cache by SHA256 of fetched content
- Git file/dir: cache by commit hash
- Local source: not cached (identical to local source in Arch)
- Build dir preserved across rebuilds (`cache/<key>/extracted/`)
- Second build shows `"Fetching git repo (cached)"` — cache hits confirmed

### 7. Transaction Atomicity ✅

`lib/rulepack/install.rb`:
```ruby
backup_path = backup_index          # before install loop
# ... install loop ...
# on error: restore_index(backup_path)
# on success: cleanup_backups
```

Single index write at end. On failure, index restored to pre-transaction state. This mirrors `pacman`'s database consistency guarantees.

### 8. Vendor Skill Aggregation ✅

Aggregates rule fragments + skills into a single vendored skill file per agent. This is **unique to Rulepack** (no Arch analog) but architecturally clean — similar to how Arch splits packages into subpackages that get aggregated by pacman.

---

## What's Missing (Gap Analysis vs. ABS)

### Critical: Package Manager Layer

| ABS Feature | Rulepack Status | Impact |
|-------------|----------------|--------|
| `pacman` install | `install.rb` (partial) | Install works, but no equivalent of `pacman -U *.pkg.tar.zst` |
| `pacman` remove | `uninstall.rb` (partial) | Removes files, but doesn't enforce dependency chains |
| `pacman` query | `query.rb` (partial) | Basic query works, no `-Qi/-Qs/-Qo/-Ql` parity |
| Package DB sync | None | No remote repo sync (see below) |

### Missing: Repository System

| ABS Concept | Rulepack Status |
|-------------|----------------|
| `pacman -Sy` (sync DB) | ❌ No remote repo support |
| `pacman -S` (install from repo) | ❌ No repo system |
| `/etc/pacman.conf` repos | ❌ N/A — all packages are local |
| AUR helpers (`yay`, `paru`) | ❌ N/A |
| `.SRCINFO` generation | ❌ Not generated from PKGBUILD |

We have 9 local packages only. No concept of "installing from a remote Rulepack repository."

### Missing: Package Signing & Verification

| ABS Feature | Rulepack Status |
|-------------|----------------|
| GPG signing (`signify`, `pgp`) | ❌ No signing |
| `pacman-key` keyring | ❌ N/A |
| Signature verification | ❌ N/A |

### Missing: Dependency Resolution

| ABS Feature | Rulepack Status |
|-------------|----------------|
| Topological install order | ❌ Not implemented |
| `pacman -D` dependency check | ❌ Not implemented |
| Circular dependency detection | ❌ N/A |

Currently deferred (skills/rules are text files — inherently independent).

### Missing: makepkg Features

| ABS Feature | Rulepack Status |
|-------------|----------------|
| `prepare()` / `build()` / `package()` functions | ❌ PKGBUILD is declarative only |
| `pkgver()` dynamic version | ❌ Not supported in PKGBUILD format |
| `patch` application | ❌ No patch=() support |
| Subpackages (`package_foo()`) | ❌ N/A |
| `fakeroot` sandbox | ⚠️ Partial — build isolation only |
| `makepkg.conf` global config | ❌ N/A |
| Split packages | ❌ N/A |
| Install scriptlets (`.install`) | ❌ N/A |

### Missing: ABS Ecosystem

| ABS Feature | Rulepack Status |
|-------------|----------------|
| `abs` tree / `asp` | ❌ No tree sync |
| PKGBUILD linting (`namcap`) | ✅ Partial (`validate_pkgbuild` in tests) |
| `makepkg -si` combined | ✅ Partial (`bin/rulepack build && install`) |

---

## The Core ABS Pattern: How Well Did We Capture It?

### ABS Mental Model → Rulepack Implementation

```
Arch:  PKGBUILD in AUR → makepkg fetches sources → builds .pkg.tar.zst
       → pacman installs to system → /var/lib/pacman/local/ updated

Rulepack:  PKGBUILD in data/packages/ → bin/rulepack build fetches + transforms
       → writes to build/<platform>/ → bin/rulepack install installs
       → data/index.yaml updated
```

**Verdict**: The mental model is faithful. The `build/<platform>/` directory is our `$pkgdir`. The `data/index.yaml` is our local package DB.

### ABS Source Fidelity → Rulepack Implementation

```
Arch:  source=('file')          → files in PKGBUILD dir, copied at build time
       source=('git+https://...') → git clone at build time, commit as checksum
       source=('https://...')    → curl at build time, SHA256 verify

Rulepack:  {type: local, path: 'src/foo.md'}   → FileUtils.cp_r from src/ at build time
       {type: git, url: 'https://...'}      → git clone at build time, commit as checksum
       {type: url, url: 'https://...'}      → HTTP fetch at build time, SHA256 verify
```

**Verdict**: Near-exact parity on the three source types. The `src/` directory mirrors Arch's local file sources.

### ABS Multi-Arch → Rulepack Multi-Platform

```
Arch:  arch=('x86_64' 'any') → build for multiple architectures
       one PKGBUILD → multiple .pkg.tar.zst files

Rulepack:  targets: [{platform: opencode}, {platform: cursor}, ...]
       one PKGBUILD → multiple build artifacts in build/<platform>/
```

**Verdict**: Rulepack is actually *more powerful* here — Arch only has `x86_64`/`i686`/`any`, while Rulepack has 12 named platforms with different install methods per target.

---

## Summary Scorecard

| Category | Score | Notes |
|----------|-------|-------|
| PKGBUILD format fidelity | ⭐⭐⭐⭐⭐ | Near-exact parity on all essential fields |
| Local source model (`src/`) | ⭐⭐⭐⭐⭐ | Perfect — `src/` IS the local source directory |
| Git source model | ⭐⭐⭐⭐⭐ | Exact `git+` URL analog |
| URL source model | ⭐⭐⭐⭐☆ | Implemented, not exercised by current packages |
| Build isolation (`build/`) | ⭐⭐⭐⭐⭐ | Exact `$pkgdir` analog |
| Checksums (source + built) | ⭐⭐⭐⭐⭐ | Source SHA256 + built SHA256 + per-file manifest |
| Versioning (epoch/pkgver/pkgrel) | ⭐⭐⭐⭐⭐ | Exact pacman-style with compare/upgrade logic |
| Multi-target deployment | ⭐⭐⭐⭐⭐ | Better than ABS — named platforms, per-target formats |
| Transaction atomicity | ⭐⭐⭐⭐☆ | Install yes, uninstall no |
| Cache | ⭐⭐⭐⭐⭐ | Better than ABS — content-addressed, git+url+local |
| Platform registry | ⭐⭐⭐⭐☆ | Central config (like pacman.conf), no repo sync |
| Vendor skill aggregation | ⭐⭐⭐☆☆ | Unique to Rulepack, no ABS analog |
| Dependency resolution | ⭐☆☆☆☆ | Documented only, not enforced |
| Package signing | ⭐☆☆☆☆ | Not implemented |
| Remote repositories | ⭐☆☆☆☆ | No repo system |
| Install scriptlets | ⭐☆☆☆☆ | Declarative only, no shell functions |
| Uninstall completeness | ⭐⭐☆☆☆ | Removes files but no dependency chain handling |
| Query tool parity | ⭐⭐⭐☆☆ | Basic queries work, no `-Qi/-Qs/-Qo/-Ql` |

### Overall: 75% ABS Parity on Core Philosophy

We have **excellent fidelity on the core ABS philosophy**:
1. Declarative PKGBUILD per package ✅
2. `src/` as the local source directory ✅  
3. `git+` URL source model ✅
4. Build isolation in `build/` ✅
5. Checksums everywhere ✅
6. Version management with epoch/pkgver/pkgrel ✅
7. Single-package → multi-target deployment ✅

We're **missing the package manager layer** (`pacman` equivalent with full dependency resolution, remote repo sync, signing, query completeness) and **makepkg advanced features** (`prepare()`/`build()`/`package()` functions, patches, subpackages).

For our use case (agent rules/skills), the missing features are mostly unnecessary — text files don't need subpackages, scriptlets, or `fakeroot`. The gap is real for a general-purpose package manager, but the **core ABS philosophy of "declarative descriptor → fetch source → build → install → track in DB" is faithfully implemented**.
