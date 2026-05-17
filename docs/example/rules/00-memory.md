# Workstation Memory Constraints

**8 GB RAM (7.4 usable), 931 GB HDD, no physical swap** (zram 3.7 GB, zstd only).

## Mandatory: Isolate test and build commands

Any command that may consume >1 GB RAM **MUST** be wrapped:

| Command | Limit |
|---------|-------|
| `npm test`, `vitest`, `jest` | 3G |
| `cargo build`, `cargo test` | 2G |

**No exceptions.**
