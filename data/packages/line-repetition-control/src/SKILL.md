---
name: line-repetition-control
description: Detects and reports unintentional line or block repetitions often produced by AI agents during code generation. It uses smart heuristics to filter out intentional syntactic repetitions (like closing brackets, comment separators, or boilerplate). Counts repetitions beyond 2x and is .gitignore aware.
---

# Line Repetition Control

## Overview
Detects and reports unintentional line or block repetitions often produced by AI agents during code generation. It uses smart heuristics to filter out intentional syntactic repetitions (like closing brackets or boilerplate).

## Capabilities
- Detect **exact** consecutive identical lines (ignoring whitespace).
- Detect **near-duplicate** consecutive lines (same structure, different literals/numbers).
- Detect consecutive identical code blocks (2-5 lines).
- Counts repetitions beyond 2x (e.g., reports "Repeated 4x").
- Severity levels: LOW (2x), HIGH (3-4x), CRITICAL (5x+).
- Built-in `.gitignore` awareness (via `git ls-files`).
- Binary file detection (auto-skip).
- Parallel processing for codebase-wide scanning.
- Non-zero exit code when repetitions found (CI-friendly).

## Usage

### High-Performance Python Scanner (Recommended)
Best for large projects and codebase-wide scans.
```bash
uv run ~/.config/opencode/skills/line-repetition-control/scripts/detect_repeats_fast.py [path]
```

#### Flags
| Flag | Default | Description |
|------|---------|-------------|
| `--json` | off | JSON output (machine-readable) |
| `--summary` | off | Print summary statistics after results |
| `--ext` | (40+ extensions) | Comma-separated file extensions to scan |
| `--exclude` | `.git,node_modules,...` | Comma-separated directories to skip |
| `--min-count` | 2 | Minimum repetition count to report |

#### CI / Pre-commit Hook
```bash
# Fail if any repetitions found
uv run ~/.config/opencode/skills/line-repetition-control/scripts/detect_repeats_fast.py src/
if [ $? -ne 0 ]; then
  echo "::error::Repetitions detected"
fi
```

### Shell Implementation (Awk-based)
Lightweight alternative for single-file scanning (exact matches only).
```bash
bash ~/.config/opencode/skills/line-repetition-control/scripts/detect_repeats.sh <path_to_file>
```

## Heuristics
1. **Minimum Length**: Lines shorter than 3 characters are ignored unless part of a larger block.
2. **Exception List**: Common keywords, single brackets (`}`, `else`, `end`), and closure patterns (`});`, `},`, `],`) are excluded.
3. **Separator Filtering**: Comment separators like `// ============`, `# ------------`, or `***` are automatically ignored.
4. **Near-Duplicate Normalization**: String literals, numbers, and hex values are replaced with placeholders before comparison. This catches AI failures like `logger.info("item 1")` / `logger.info("item 2")`.
5. **Block Detection**: Identifies repeated sequences of lines (2-5 lines), prioritizing larger blocks to catch degenerate "looping" failures.
6. **Binary Guard**: Files containing null bytes are silently skipped.
7. **Git-Awareness**: Automatically skips files ignored by `.gitignore`.

## Examples

### Exact Repeats
**Input:**
```python
def example():
    print("hello")
    print("hello")
    print("hello")
    return True
    return True
```
**Output:**
- `[HIGH] Line 2: Repeated 3x -> print("hello")`
- `[LOW] Line 5: Repeated 2x -> return True`

### Near-Duplicates
**Input:**
```python
logger.info("Processing item 1")
logger.info("Processing item 2")
logger.info("Processing item 3")
logger.info("Processing item 4")
logger.info("Processing item 5")
```
**Output:**
- `[CRITICAL] Line 1: Near-duplicate 5x -> logger.info("Processing item 1")`
- `         variant: logger.info("Processing item 2")`
- `         variant: logger.info("Processing item 3")`
- `         variant: logger.info("Processing item 4")`
- `         variant: logger.info("Processing item 5")`

### Block Repeats
**Input:**
```python
for item in items:
    process(item)
    validate(item)
for item in items:
    process(item)
    validate(item)
for item in items:
    process(item)
    validate(item)
```
**Output:**
- `[HIGH] Line 1: Repeated block (3 lines) 3x`

## JSON Output Format
When using `--json`, the tool returns a dictionary keyed by file path:
```json
{
  "src/main.py": [
    {
      "type": "consecutive_line",
      "line_start": 42,
      "content": "logger.info('Starting...')",
      "count": 3
    },
    {
      "type": "near_duplicate",
      "line_start": 50,
      "content": "process(data=\"input_1\")",
      "variants": ["process(data=\"input_2\")", "process(data=\"input_3\")"],
      "count": 3
    }
  ]
}
```

## Exit Codes
| Code | Meaning |
|------|---------|
| 0 | No repetitions found |
| 1 | Repetitions detected |
| 2 | Invalid arguments or path not found |
