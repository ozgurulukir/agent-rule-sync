# REFACTOR_RULEPACK_COMMON.md

> **Goal**: Split `Rulepack::Common` (~300 LOC, 17 public methods) into focused, single-responsibility modules while maintaining 100% backward compatibility and passing all 277+ tests.

---

## Current State

`lib/rulepack/common.rb` — **302 lines**, **17 public methods** under `Rulepack::Common`

```
Rulepack::Common
├── Configuration (path overrides)
│   ├── build_index_path / build_index_path=
│   ├── index_yaml_path / index_yaml_path=
│   └── build_dir / build_dir=
├── Logging
│   ├── log_level / log_level=
│   ├── show_timing / show_timing=
│   └── (log, log_error, log_warn, log_debug — defined elsewhere)
├── IO Utilities
│   ├── load_yaml
│   ├── write_yaml_atomic
│   ├── atomic_write
│   ├── atomic_append
│   ├── update_marked_content
│   └── remove_marked_content
├── Validation
│   ├── verify_checksum
│   └── validate_targets_and_packages
├── Path Utilities
│   ├── expand_user_path
│   └── strip_frontmatter
└── Install Helpers
    ├── uninstall_packages
    └── migrate_installed_records
```

---

## Target Architecture

```
Rulepack
├── Config          (existing — move to separate file)
├── Common          (facade — delegates to submodules)
│   └── (all current call sites continue to work)
├── Logging         (lib/rulepack/logging.rb)
├── IO              (lib/rulepack/io.rb)
├── Validation      (lib/rulepack/validation.rb)
├── Path            (lib/rulepack/path_utils.rb)
└── Install         (lib/rulepack/install_helpers.rb)
```

### Design Principles

1. **Zero behavioral change** — all existing call sites (`Rulepack::Common.xxx`) must continue to work
2. **Gradual extraction** — each module extracted in its own commit, tests pass after each step
3. **Single responsibility** — each new module has one clear concern
4. **Internal modules** — new modules live under `Rulepack::Lib` namespace internally, exposed via `Rulepack::Common` facade
5. **Test preservation** — no test modifications required (backward compatibility maintained)

---

## Extraction Plan

### Phase 0 — Baseline (Current State)

**Commit**: `88dbd26` (P18 complete)

**Test baseline**:
```bash
$ rake test
276 runs, 842 assertions, 6 failures, 6 errors, 6 skips
```

**Call site audit** — grep all `Rulepack::Common\.` usages:
```bash
$ grep -rn "Rulepack::Common\." lib/ test/ bin/
# Expected: ~40-50 call sites across:
# - lib/rulepack/build.rb
# - lib/rulepack/installer.rb
# - lib/rulepack/uninstaller.rb
# - lib/rulepack/fix.rb
# - lib/rulepack/query.rb
# - test/**/*.rb
```

---

### Phase 1 — Extract `Rulepack::Logging` (Easiest — No Dependencies)

**File**: `lib/rulepack/logging.rb`

**Move methods**:
- `log(msg, level: :info, log_file: nil)`
- `log_error(msg)`
- `log_warn(msg)`
- `log_debug(msg)`
- `log_level` / `log_level=`
- `show_timing` / `show_timing=`

**Keep in Common**: delegation wrappers
```ruby
module Common
  def self.log(*args) = Logging.log(*args)
  def self.log_error(*args) = Logging.log_error(*args)
  # ... etc
end
```

**Test**: `rake test` → identical results

**Commit message**: `refactor: extract Rulepack::Logging module`

---

### Phase 2 — Extract `Rulepack::IO` (Low Dependencies)

**File**: `lib/rulepack/io.rb`

**Move methods**:
- `load_yaml(path)`
- `write_yaml_atomic(path, data)`
- `atomic_write(path, content)`
- `atomic_append(path, content)`
- `update_marked_content(path, pkgname, content)`
- `remove_marked_content(path, pkgname)`

**Keep in Common**: delegation wrappers

**Test**: `rake test` → identical results

**Commit message**: `refactor: extract Rulepack::IO module`

---

### Phase 3 — Extract `Rulepack::Validation` (Medium Dependencies)

**File**: `lib/rulepack/validation.rb`

**Move methods**:
- `verify_checksum(path, expected_checksum, pkgname)`
- `validate_targets_and_packages(target_arg, package_arg, packages, registry, ...)`

**Dependencies**: `Rulepack::Common` (for `log_error`), `Rulepack::Config` (for paths)

**Keep in Common**: delegation wrappers

**Test**: `rake test` → identical results

**Commit message**: `refactor: extract Rulepack::Validation module`

---

### Phase 4 — Extract `Rulepack::Path` (Low Dependencies)

**File**: `lib/rulepack/path_utils.rb`

**Move methods**:
- `expand_user_path(path)`
- `strip_frontmatter(content)`

**Keep in Common**: delegation wrappers

**Test**: `rake test` → identical results

**Commit message**: `refactor: extract Rulepack::Path module`

---

### Phase 5 — Extract `Rulepack::InstallHelpers` (Highest Dependencies)

**File**: `lib/rulepack/install_helpers.rb`

**Move methods**:
- `uninstall_packages(index, platform_id, dry_run: false, project_root: nil, ...)`
- `migrate_installed_records(pkg_index)`

**Dependencies**: `Rulepack::Common` (for logging, index paths), `Rulepack::Config`

**Keep in Common**: delegation wrappers

**Test**: `rake test` → identical results

**Commit message**: `refactor: extract Rulepack::InstallHelpers module`

---

### Phase 6 — Extract `Rulepack::Config` to Separate File

**File**: `lib/rulepack/config.rb` (already exists inline in `common.rb` lines 11-33)

**Move**: entire `Rulepack::Config` module

**Update requires**: `lib/rulepack/common.rb` → `require_relative 'config'`

**Keep in Common**: `Common` still references `Config` via `Rulepack::Config.xxx`

**Test**: `rake test` → identical results

**Commit message**: `refactor: extract Rulepack::Config to separate file`

---

### Phase 7 — Slim Down `Rulepack::Common` to Facade Only

**Final `lib/rulepack/common.rb`** (~50 lines):

```ruby
require_relative 'config'
require_relative 'logging'
require_relative 'io'
require_relative 'validation'
require_relative 'path_utils'
require_relative 'install_helpers'

module Rulepack
  module Common
    # Path overrides (test seam)
    class << self
      attr_accessor :_build_index_override, :_index_yaml_override, :_build_dir_override
    end

    # Facade — delegates to submodules
    def self.method_missing(method, *args, &block)
      if Logging.respond_to?(method)
        Logging.send(method, *args, &block)
      elsif IO.respond_to?(method)
        IO.send(method, *args, &block)
      elsif Validation.respond_to?(method)
        Validation.send(method, *args, &block)
      elsif Path.respond_to?(method)
        Path.send(method, *args, &block)
      elsif InstallHelpers.respond_to?(method)
        InstallHelpers.send(method, *args, &block)
      else
        super
      end
    end

    def self.respond_to_missing?(method, include_private = false)
      Logging.respond_to?(method) ||
        IO.respond_to?(method) ||
        Validation.respond_to?(method) ||
        Path.respond_to?(method) ||
        InstallHelpers.respond_to?(method) ||
        super
    end
  end
end
```

**Alternative (explicit delegation)** — preferred for clarity:
```ruby
module Rulepack
  module Common
    # Explicit delegation to submodules
    Logging.public_instance_methods.each { |m| define_singleton_method(m, &Logging.method(m)) }
    IO.public_instance_methods.each { |m| define_singleton_method(m, &IO.method(m)) }
    Validation.public_instance_methods.each { |m| define_singleton_method(m, &Validation.method(m)) }
    Path.public_instance_methods.each { |m| define_singleton_method(m, &Path.method(m)) }
    InstallHelpers.public_instance_methods.each { |m| define_singleton_method(m, &InstallHelpers.method(m)) }
  end
end
```

**Test**: `rake test` → identical results

**Commit message**: `refactor: slim Common to facade-only, delegate to submodules`

---

## Test Strategy

### Before Each Phase

```bash
$ rake test  # baseline snapshot
# Record: runs, assertions, failures, errors, skips
```

### After Each Phase

```bash
$ rake test  # must match baseline exactly
# If failures/errors change → revert, debug, retry
```

### Regression Guard

Add to `test/test_common.rb`:
```ruby
def test_common_facade_unchanged
  # Verify every public method still accessible via Common
  methods = %i[
    log log_error log_warn log_debug
    load_yaml write_yaml_atomic atomic_write atomic_append
    update_marked_content remove_marked_content
    verify_checksum validate_targets_and_packages
    expand_user_path strip_frontmatter
    uninstall_packages migrate_installed_records
  ]
  methods.each { |m| assert Rulepack::Common.respond_to?(m), "Missing: #{m}" }
end
```

---

## Rollback Strategy

Each phase is a single commit. To rollback:
```bash
$ git revert <commit-sha>
$ rake test  # verify back to baseline
```

---

## Timeline

| Phase | Module | Est. LOC | Complexity |
|-------|--------|----------|------------|
| 1 | Logging | ~60 | Low |
| 2 | IO | ~80 | Low |
| 3 | Validation | ~70 | Medium |
| 4 | Path | ~20 | Low |
| 5 | InstallHelpers | ~50 | Medium |
| 6 | Config | ~30 | Low |
| 7 | Facade | ~50 | Low |

**Total**: ~360 LOC across 7 phases (1 commit each = 7 commits)

---

## Success Criteria

- ✅ All 277+ tests pass after each phase
- ✅ Zero test file modifications required
- ✅ Zero behavioral changes (CLI output, exit codes, file I/O identical)
- ✅ `Rulepack::Common.xxx` calls continue to work everywhere
- ✅ Final `common.rb` < 100 LOC (facade only)

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| `method_missing` misses a method | Use explicit delegation (Phase 7 alt) or exhaustive `respond_to_missing?` test |
| Thread-safety of `module_function` | Each submodule is `module_function`; `Common` delegates via singleton methods |
| Performance overhead of delegation | Negligible — single method call indirection |
| Breaking existing tests | Run full suite after each phase; revert on any failure |

---

## Completed Phases

### ✅ Phase 1 — Extract `Rulepack::Logging` (COMPLETED)

- **Commit**: `30d6e1d`
- **Test baseline**: 276 runs, 842 assertions, 6 failures, 6 errors, 6 skips
- **Changes**:
  - Moved logging state (@_log_level, @_show_timing) and methods to `Rulepack::Logging` module
  - Added `require_relative 'logging'` before `module Common`
  - Added delegation via `define_singleton_method` loop in Common
  - All call sites continue to work via `Rulepack::Common.log(...)`

---

## Next Steps

1. Review and approve this plan
2. Execute Phase 2 (IO extraction) — low dependencies
3. Execute Phase 3 (Validation extraction) — medium dependencies
4. Execute Phase 4 (Path extraction) — low dependencies
5. Execute Phase 5 (InstallHelpers extraction) — medium dependencies
6. Execute Phase 6 (Config extraction) — low dependencies
7. Execute Phase 7 (Slim Common to facade) — final cleanup
