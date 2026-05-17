---
name: update-signatures
description: >
  Updates Ruby type signatures for uncommitted file changes. Triggers on
  "update signatures", "sync types", "generate types for changes".
tools:
  - Read
  - Write
  - Edit
  - MultiEdit
  - NotebookEdit
  - Glob
  - Grep
  - LS
  - WebFetch
  - WebSearch
  - Task
  - TodoWrite
  - AskUserQuestion
  - Bash
---

# Update Signatures Agent

Updates or generates Ruby type signatures (RBS or Sorbet) for uncommitted file changes in a Git repository.

## Instructions

When updating type signatures for uncommitted changes, always follow these steps.

Copy this checklist and track your progress:

```
Update Signatures Progress:
- [ ] Step 1: Get changed Ruby files from Git and create tracking file
- [ ] Step 2: Detect signature system (RBS vs Sorbet)
- [ ] Step 3: Detect signature style (inline vs separate)
- [ ] Step 4: Process each file using appropriate skill (mark progress in tracking file)
- [ ] Step 5: Report results and cleanup tracking file
```

## Rules

There are several rules that you MUST follow while performing this agent:

- You MUST verify this is a Git repository before proceeding.
- You MUST auto-detect the signature system unless the user provides override.
- You MUST auto-detect the signature style unless the user provides override.
- You MUST use the existing skills for actual signature generation — do not duplicate their logic.
- You MUST ask the user if detection is ambiguous (both systems detected or neither).
- You MUST use the tracking file (`.signatures-todo.tmp`) to track progress and mark each file as processed.
- You MUST remove the tracking file only after all files are successfully processed.

## User Overrides

The user may provide flags to override auto-detection:

- `--rbs` — Force RBS signature system
- `--sorbet` — Force Sorbet signature system
- `--inline` — Force inline signature style
- `--separate` — Force separate file signature style

If overrides are provided, skip the corresponding detection step.

## Step 1: Get Changed Ruby Files from Git

Always perform this step.

First, verify this is a Git repository:

```bash
git rev-parse --git-dir
```

If not a Git repository, inform the user and exit.

Get all uncommitted Ruby file changes (staged, unstaged, and untracked):

```bash
# Staged changes (including deleted files)
git diff --cached --name-only --diff-filter=ACMD -- '*.rb'

# Unstaged changes (including deleted files)
git diff --name-only --diff-filter=ACMD -- '*.rb'

# Untracked Ruby files (ask user if they want to include these)
git ls-files --others --exclude-standard -- '*.rb'
```

Combine results and remove duplicates.

If no Ruby files have changed, inform the user and exit.

### Create Tracking File

Create a temporary tracking file `.signatures-todo.tmp` to track progress through all changed files:

```
# .signatures-todo.tmp format:
# All entries start as [ ] pending, mark [x] when processed
# (deleted) suffix indicates the Ruby file was deleted
# Example:
[ ] app/models/user.rb
[ ] app/services/auth_service.rb
[ ] app/models/old_model.rb (deleted)
```

For each changed file, add a pending entry:

- `[ ] path/to/file.rb` — for existing files (to generate/update)
- `[ ] path/to/file.rb (deleted)` — for deleted files (to remove signatures)

This file ensures no changes are missed and allows resuming if interrupted.

### Process Files

Go through each pending `[ ]` entry in the tracking file one by one:

1. Process the file:
   - If file exists: generate/update signatures using the appropriate skill
   - If file is marked `(deleted)`: remove corresponding signature file (.rbs or .rbi)
2. Mark as processed by changing `[ ]` to `[x]`
3. Save the tracking file after each file is processed
4. Move to the next pending entry

## Step 2: Detect Signature System (RBS vs Sorbet)

Perform this step unless user provided `--rbs` or `--sorbet` override.

Use a scoring system to detect the signature system:

**Sorbet indicators:**

| Indicator | Score |
|-----------|-------|
| `sorbet/` directory exists | +3 |
| `.rbi` files exist in project | +2 |
| `sorbet` or `sorbet-runtime` in Gemfile | +3 |
| `tapioca` in Gemfile | +3 |
| `T::Sig` or `extend T::Sig` in Ruby files | +2 |

**RBS indicators:**

| Indicator | Score |
|-----------|-------|
| `sig/` directory exists | +3 |
| `.rbs` files exist in project | +2 |
| `rbs` in Gemfile | +2 |
| `steep` in Gemfile | +1 |
| `rbs-inline` in Gemfile | +2 |

Check indicators:

```bash
# Sorbet indicators
test -d sorbet && echo "sorbet_dir"
find . -name "*.rbi" -type f | head -1
grep -E "sorbet|sorbet-runtime|tapioca" Gemfile 2>/dev/null

# RBS indicators
test -d sig && echo "sig_dir"
find . -name "*.rbs" -type f | head -1
grep -E "^gem.*rbs|steep|rbs-inline" Gemfile 2>/dev/null
```

Calculate scores and determine system:

- If Sorbet score > RBS score: Use Sorbet
- If RBS score > Sorbet score: Use RBS
- If scores are equal or both zero: Ask user which system to use

## Step 3: Detect Signature Style (Inline vs Separate)

Perform this step unless user provided `--inline` or `--separate` override.

**For Sorbet:**

- Inline indicators: `sig { }` blocks in `.rb` files, `extend T::Sig` usage
- Separate indicators: `.rbi` files in `rbi/` or `sorbet/rbi/` directories

```bash
# Inline Sorbet
grep -r "sig {" --include="*.rb" . | wc -l
grep -r "extend T::Sig" --include="*.rb" . | wc -l

# Separate Sorbet
find . -path "*/rbi/*.rbi" -o -path "*/sorbet/rbi/*.rbi" | wc -l
```

**For RBS:**

- Inline indicators: `# @rbs` comments or `#:` shorthand in `.rb` files, `rbs_inline: enabled` magic comment
- Separate indicators: `.rbs` files in `sig/` directory

```bash
# Inline RBS
grep -r "# @rbs\|#:" --include="*.rb" . | wc -l
grep -r "rbs_inline: enabled" --include="*.rb" . | wc -l

# Separate RBS
find sig -name "*.rbs" 2>/dev/null | wc -l
```

Compare counts:

- If inline count > separate count: Use inline style
- If separate count > inline count: Use separate style
- If counts are equal or both zero: Ask user which style to prefer

## Step 4: Invoke Appropriate Skill

Always perform this step.

Based on the detected (or user-specified) system and style, invoke the appropriate skill:

| System | Style | Skill to Invoke |
|--------|-------|-----------------|
| RBS | Separate | `generating-rbs` |
| RBS | Inline | `generating-rbs-inline` |
| Sorbet | Separate | `generating-sorbet` |
| Sorbet | Inline | `generating-sorbet-inline` |

For each pending `[ ]` entry in the tracking file (`.signatures-todo.tmp`):

1. Read the next pending entry
2. Process based on file status:
   - For existing files: Follow the instructions from the selected skill to generate/update signatures
   - For deleted files (marked with `(deleted)`): Remove the corresponding signature file
3. Mark the entry as processed by changing `[ ]` to `[x]`
4. Save the tracking file
5. Continue to next pending entry

**Important:** Do not duplicate the signature generation logic. The skills contain all the necessary instructions for generating proper signatures.

## Step 5: Report Results and Cleanup

Always perform this step.

### Verify All Files Processed

Check the tracking file to ensure all entries are marked as `[x]`:

- If any entries remain as `[ ]`, process them before continuing
- Do not proceed to cleanup until all files are processed

### Remove Tracking File

Once all files are processed, remove the tracking file:

```bash
rm .signatures-todo.tmp
```

### Provide Summary

Provide a summary to the user:

- Number of Ruby files processed
- Number of signature files removed (for deleted Ruby files)
- Signature system used (RBS or Sorbet)
- Signature style used (inline or separate)
- List of files that were updated/created
- List of signature files that were removed
- Any files that were skipped and why
- Any errors encountered

Example output:

```
Signature Update Complete:
- System: RBS
- Style: Separate (.rbs files)
- Files processed: 5
- Signatures removed: 1
- Signatures created/updated:
  - sig/models/user.rbs (created)
  - sig/models/post.rbs (updated)
  - sig/services/auth_service.rbs (created)
- Signatures removed:
  - sig/models/old_model.rbs (deleted)
```
