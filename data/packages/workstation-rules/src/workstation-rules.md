# Workstation Memory Constraints

**8 GB RAM (7.4 usable), 931 GB HDD, no physical swap** (zram 3.7 GB, zstd only). This machine crashes if memory exhausts.

## Mandatory: Isolate test and build commands

Any command that may consume >1 GB RAM **MUST** be wrapped in `systemd-run --user --scope -p MemoryMax=`:

| Command | Limit |
|---------|-------|
| `npm test`, `npm run test`, `vitest`, `jest` | 3G |
| `cargo build`, `cargo test`, `go test` | 2G |
| `pnpm install`, `npm install`, `bun install` | 3G |
| `bun run build`, `bun run test`, `tsc --build`, `webpack` | 2G |


**No exceptions.** Without this, kernel OOM kills gnome-shell and crashes the desktop.

## Don't run heavy processes in parallel

`cargo build` + `npm install` simultaneously will thrash the HDD and crash the desktop. Run one at a time.

## System-wide memory caps

- **Node.js**: 1.5 GB (`NODE_OPTIONS` in `/etc/environment.d/nodejs.conf`)
- **Bun**: 2 GB (`BUN_CONFIG_MAX_MEMORY` in `~/.profile`)

Do not override these.


# Non-Interactive Shell Strategy

All shell commands **MUST be non-interactive**. Assume no TTY, no stdin.

## Prohibited

- `sudo` without explicit user confirmation
- `apt`, `apt-get`, `nix-env`, package manager operations
- Interactive prompts (`read`, `vim`, `less`, `fzf`, etc.)
- `cd` into unknown directories
- `ssh` without user approval

## Required

- Use `batch mode` flags where available (`npm --yes`, `cargo -y`, `yes | ...`).
- Verify commands before execution (`echo` first if unsure).
- Check return codes (`|| exit 1`).

**This machine is a build/CI workstation — not an interactive shell.**


# Patterns & Anti-Patterns

## ✅ Do

- **Verify, don't assert.** Run the actual test, don't reason about correctness.
- **Read before write.** Load surrounding context before editing.
- **Fail loudly.** Prefer `Result` / `Option` over unwrap/panic/ignore. Never swallow errors silently.
- **Isolate side effects.** Pure functions > shared state.
- **DRY.** Don't repeat yourself — extract shared logic.

## ❌ Don't

- Don't guess about code behavior — **run it**.
- Don't edit without reading surrounding context.
- Don't silently ignore errors (`unwrap()`, `panic!()`, `try!()` without handling).
- Don't duplicate logic across files.
- Don't make assumptions about input validation — verify.

## Golden Rule

**Evidence before "done".** Run tests/lint/verification first.


# Git Workflow

## Branch Before Code Changes

Always create a branch **before** modifying files:
```bash
git checkout -b feature/foo
```

## Small, Focused Commits

- One logical change per commit.
- Commit message: imperative mood, concise body explaining "what" and "why".
- Reference issue numbers if applicable.

## Test Before Push

```bash
cargo test   # or npm test, bun test, etc.
git add .
git commit -m "Brief message"
git push origin HEAD
```

## Never Force Push Shared Branches

- No `git push --force` on `main`, `develop`, or any shared branch.
- Use `--force-with-lease` only for private branches.

## Rebase, Don't Merge (for local branches)

Keep history clean:
```bash
git fetch origin
git rebase origin/main
```

