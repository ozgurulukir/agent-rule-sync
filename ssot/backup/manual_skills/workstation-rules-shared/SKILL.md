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
| `code-tandem index` (large projects) | 2G |

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


# Code Navigation Hierarchy

Always solve for the **smallest context** first. Never load a 500-line file to understand a 10-line function.

## Order of Operations

1. **Structural (AST)**: Use `ast-grep` for code construct patterns (function signatures, call expressions, imports).
   - Full examples: see `ast-grep` skill
2. **Exploration (semantic)**: Use `code-tandem` for broad discovery when you don't know what you're looking for.
   - Full reference: see `06-tci.md` (Tandem Code Intelligence)
3. **Textual (grep)**: Search plain strings, comments, non-code files.
   - Use `rg` for speed, `grep` for portability
4. **Manual (Read)**: Last resort. Only for small files (<50 lines) or after precise discovery.
   - Use `peek --symbol` or `impl` for targeted reading

## Know Your Environment

Understand available tools. **SSoT, DRY, and modularity** are first-class principles.


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


# Tandem Code Intelligence — Rules

> Tree-sitter-backed structural code analysis. Call graphs, dependency analysis, flow tracing, test discovery — from the terminal.

**CRITICAL: Use `code-tandem` for ALL source code analysis because `code-tandem` gives byte-exact, AST-aware answers in a single command..** Unless for text only jobs (markdown, config, JSON, YAML) or when `code-tandem` returns insufficient results.

```
Agent → code-tandem (Crystal CLI) → code-tandem-server (Rust, port 3000)
```

## Quick Start

```bash
code-tandem init                  # Create session (auto-waits for index)
code-tandem stats                 # Symbol count, file count
code-tandem integration           # Component matrix
code-tandem search "symbol"       # Find symbols
code-tandem graph "main" --top 5  # Hub functions
code-tandem flow "A" --to "B"     # Trace execution path
code-tandem tests                 # Test discovery
code-tandem strings "error"       # String literal search
```

**First run (gen 0) — define component boundaries:**

```bash
code-tandem integration --learn --verbose
code-tandem integration --apply-patterns '{
  "component_rules": [
    {"pattern": "server/", "name": "server", "language": "rust", "confidence": 0.95},
    {"pattern": "cli/src/", "name": "cli", "language": "crystal", "confidence": 0.95},
    {"pattern": "cli/spec/", "name": "other", "language": "crystal", "confidence": 0.9}
  ],
  "noise_identifiers": ["search", "get", "size", "emit", "save_output", "epoch_info", "parse_qualified", "language_ext", "make_key", "to_json", "clone", "push", "new", "load", "save", "from", "remove", "clear", "invalidate", "peek", "post", "request", "content", "index", "stats", "symbol", "symbols"],
  "cluster_depth": 1
}'
code-tandem integration  # verify
```

No `code-tandem config` command exists. Config is at `.code-tandem/config.json`, created only via `--apply-patterns`.

**Symbol names are project-specific.** Discover your project's structure: `code-tandem stats`, `graph "main" --top 10`, `search "build"`. Symbols like `handle_events`, `build_graph` are from this repo and may not exist in yours.

## Command Quick Reference

| Command | Purpose | Key flags |
|---------|---------|-----------|
| `init` | Session & indexing | `-f` force re-index |
| `search` | Find symbols | `--limit N`, supports `\|`/`,` multi-query |
| `impl` | Function body source | `--file` disambiguate |
| `callers` | Reverse call graph | `--depth N`, `--component`, `--format dot` |
| `graph` | Directed call graph | `--top N`, `--topo`, `--shortest`, `--exhaustive`, `--component`, `--format dot` |
| `flow` | Trace execution path | `--to`, `--from-file`/`--to-file`, `--exhaustive`, `--format inline` |
| `integration` | Component matrix | `--learn`, `--apply-patterns`, `--raw` |
| `tests` | Test discovery | `--component` |
| `strings` | String literal search | `--exact`, `--file`, `--limit` |
| `pseudocode` | LLM-ready summary | `--file`, returns `quality` metadata |
| `peek` | View source lines | `--symbol`, `--expand`, `--outline`, `--blame`, `--format raw` |
| `query` | JMESPath filtering | `--json`, `--stdin`, `--raw` |
| `output` | Cache management | `list`, `read`, `delete`, `clean` |
| `note` | Agent scratchpad | `add`, `list`, `read`, `edit`, `delete`, `clean` |

Full command details: `agents/opencode/docs/cli-reference.md`

## Analysis Workflows

**Recommended sequence:**

```
1. Stats + integration          → 10,000-foot view
2. Graph + flow                 → trace specific paths
3. Impl + callers               → byte-exact code
4. Tests + search               → find gaps
5. Init --force + re-query      → verify changes
```

**When to use which:**

| Question | Command |
|----------|---------|
| "What's in this codebase?" | `stats` + `integration` |
| "Where do I start?" | `graph "main" --top 5` |
| "How does A reach Z?" | `flow "A" --to "Z"` |
| "Is there a cycle?" | `graph "X" --topo` |
| "Show me the code" | `impl "func"` + `peek --file path --line N` |
| "What's untested?" | `tests` + `search` for gaps |
| "Where is this string?" | `strings "pattern"` |
| "Did my fix break anything?" | `init --force` + `impl`/`integration`/`tests` |

## Code Navigation Hierarchy

| Priority | Tool | When |
|----------|------|------|
| 1st | `integration` / `stats` | Broad view: component matrix, counts |
| 2nd | `callers` / `flow` / `graph` | Call chains, paths, dependency structure |
| 3rd | `search` / `impl` / `peek` | Symbol discovery, function bodies, source |
| 4th | `tests` / `strings` | Test coverage, string literals |
| Last | `rg` / `grep` / `find` | Comments, non-code files |

## Evo-Loop (Pattern Engine)

Iterative agent-driven loop for reducing false cross-refs: learn → classify → apply → verify. Repeat until `converged=true`.

**On gen 0:** Run at least 2 iterations. Set `component_rules` before using `--component`. Apply `noise_identifiers` for same-name utility functions. After each `--apply-patterns`, run `--learn` to check for remaining noise.

Full details: `agents/opencode/docs/evo-loop.md`

## Session & Server

```bash
# Server management
systemctl --user start code-tandem-server    # Start
systemctl --user stop code-tandem-server     # Stop
systemctl --user status code-tandem-server   # Status
journalctl --user -u code-tandem-server -f   # Logs

# Session
code-tandem init                    # Create session (idempotent)
code-tandem init -f                 # Force new session
rm ~/.code-tandem/session.json      # Force fresh start
```

Server: `127.0.0.1:3000`. Session: `~/.code-tandem/session.json`.

## Architecture Rules

- **Evo-loop** primarily affects `integration` matrix scoring. But `noise_identifiers` and `component_rules` also affect `graph`/`flow`/`callers` (callee resolution + component scoping).
- **`ref_key`** format: `symbol_name@dest_file` (NOT `symbol -> source -> dest`).
- **`--apply-patterns`** accepts inline JSON, stdin (`--stdin`), or file path. Updates memory atomically.
- **Cache invalidation:** epoch-based (poll every 15s) + tag-based delta for ≤100 files, full flush for >100.
- **Component filter:** `--component <name>` scopes to that component tree. Requires `component_rules`. `flow` has no `--component` — use `--from-file`/`--to-file` instead.
- **Keyword filtering:** `find_callees` filters language keywords via exact-match. 11 languages supported. Functions containing keyword substrings (e.g., `perform_match`) are NOT filtered.

## Config

All config via `integration --apply-patterns`. No `config` command exists.

| Config Key | Default | Controls |
|-----------|---------|----------|
| `min_confidence` | 0.5 | Minimum score for above-threshold refs |
| `cluster_depth` | 1 | Directory depth for auto-clustering |
| `sample_limit` | 75 | Max symbols per component in matrix |
| `component_rules` | [] | Explicit component patterns |
| `noise_identifiers` | [] | Filtered from id_refs |
| `patterns` | [] | Pattern list for scoring refs |
| `whitelist` / `blacklist` | [] | Per-ref overrides |

Full config reference: `agents/opencode/docs/config-tuning.md`

## Supported Languages

Rust, Python, TypeScript, JavaScript, Go, Java, Scala, Vue, Crystal, C, C++.

## External References

Load these on-demand when the task requires deep knowledge:

- `agents/opencode/docs/cli-reference.md` — Full command details, flags, examples, output compression
- `agents/opencode/docs/evo-loop.md` — Pattern engine deep dive, LearningReport format, experiment tracking
- `agents/opencode/docs/config-tuning.md` — All config tables, pseudocode config, quality feedback loop


Audit code for security vulnerabilities commonly introduced by AI code generation. These issues are prevalent in "vibe-coded" apps — projects built rapidly with AI assistance where security fundamentals get skipped.

AI assistants consistently get these patterns wrong, leading to real breaches, stolen API keys, and drained billing accounts. This skill exists to catch those mistakes before they ship.


## The Core Principle

Never trust the client. Every price, user ID, role, subscription status, feature flag, and rate limit counter must be validated or enforced server-side. If it exists only in the browser, mobile bundle, or request body, an attacker controls it.


## Audit Process

Examine the codebase systematically. For each step, load the relevant reference file only if the codebase uses that technology or pattern. Skip steps that aren't relevant.

1. **Secrets & Environment Variables** — Scan for hardcoded API keys, tokens, or credentials. Check for secrets exposed via client-side env var prefixes (`NEXT_PUBLIC_`, `VITE_`, `EXPO_PUBLIC_`). Verify `.env` is in `.gitignore`. See `references/secrets-and-env.md`.

2. **Database Access Control** — Check Supabase RLS policies, Firebase Security Rules, or Convex auth guards. This is the #1 source of critical vulnerabilities in vibe-coded apps. See `references/database-security.md`.

3. **Authentication & Authorization** — Validate JWT handling, middleware auth, Server Action protection, and session management. See `references/authentication.md`.

4. **Rate Limiting & Abuse Prevention** — Ensure auth endpoints, AI calls, and expensive operations have rate limits. Verify rate limit counters can't be tampered with. See `references/rate-limiting.md`.

5. **Payment Security** — Check for client-side price manipulation, webhook signature verification, and subscription status validation. See `references/payments.md`.

6. **Mobile Security** — Verify secure token storage, API key protection via backend proxy, and deep link validation. See `references/mobile.md`.

7. **AI / LLM Integration** — Check for exposed AI API keys, missing usage caps, prompt injection vectors, and unsafe output rendering. See `references/ai-integration.md`.

8. **Deployment Configuration** — Verify production settings, security headers, source map exposure, and environment separation. See `references/deployment.md`.

9. **Data Access & Input Validation** — Check for SQL injection, ORM misuse, and missing input validation. See `references/data-access.md`.

If doing a partial review or generating code in a specific area, load only the relevant reference files.


## Core Instructions

- Report only genuine security issues. Do not nitpick style or non-security concerns.
- When multiple issues exist, prioritize by exploitability and real-world impact.
- If the codebase doesn't use a particular technology (e.g., no Supabase), skip that section entirely.
- When generating new code, consult the relevant reference files proactively to avoid introducing vulnerabilities in the first place.
- If you find a critical issue (exposed secrets, disabled RLS, auth bypass), flag it immediately at the top of your response — don't bury it in a long list.


## Output Format

Organize findings by severity: **Critical** → **High** → **Medium** → **Low**.

For each issue:
1. State the file and relevant line(s).
2. Name the vulnerability.
3. Explain what an attacker could do (concrete impact, not abstract risk).
4. Show a before/after code fix.

Skip areas with no issues. End with a prioritized summary.

### Example Output

#### Critical

**`lib/supabase.ts:3` — Supabase `service_role` key exposed in client bundle**

The `service_role` key bypasses all Row-Level Security. Anyone can extract it from the browser bundle and read, modify, or delete every row in your database.

```typescript
// Before
const supabase = createClient(url, process.env.NEXT_PUBLIC_SUPABASE_SERVICE_KEY!)

// After — use the anon key client-side; service_role belongs only in server-side code
const supabase = createClient(url, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!)
```

#### High

**`app/api/checkout/route.ts:15` — Price taken from client request body**

An attacker can set any price (including $0.01) by modifying the request. Prices must be looked up server-side.

```typescript
// Before
const session = await stripe.checkout.sessions.create({
  line_items: [{ price_data: { unit_amount: req.body.price } }]
})

// After — look up the price server-side
const product = await db.products.findUnique({ where: { id: req.body.productId } })
const session = await stripe.checkout.sessions.create({
  line_items: [{ price: product.stripePriceId }]
})
```

### Summary

1. **Service role key exposed (Critical):** Anyone can bypass all database security. Rotate the key immediately and move it to server-side only.
2. **Client-controlled pricing (High):** Attackers can purchase at any price. Use server-side price lookup.


## When Generating Code

These rules also apply proactively. Before writing code that touches auth, payments, database access, API keys, or user data, consult the relevant reference file to avoid introducing the vulnerability in the first place. Prevention is better than detection.


## References

- `references/secrets-and-env.md` — API keys, tokens, environment variable configuration, and `.gitignore` rules.
- `references/database-security.md` — Supabase RLS, Firebase Security Rules, and Convex auth patterns.
- `references/authentication.md` — JWT verification, middleware, Server Actions, and session management.
- `references/rate-limiting.md` — Rate limiting strategies and abuse prevention.
- `references/payments.md` — Stripe security, webhook verification, and price validation.
- `references/mobile.md` — React Native and Expo security: secure storage, API proxy, deep links.
- `references/ai-integration.md` — LLM API key protection, usage caps, prompt injection, and output sanitization.
- `references/deployment.md` — Production configuration, security headers, and environment separation.
- `references/data-access.md` — SQL injection prevention, ORM safety, and input validation.

