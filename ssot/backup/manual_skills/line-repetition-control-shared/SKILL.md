---
name: line-repetition-control
description: Detects and reports unintentional line or block repetitions often produced by AI agents during code generation. It uses smart heuristics to filter out intentional syntactic repetitions (like closing brackets, comment separators, or boilerplate). Counts repetitions beyond 2x and is .gitignore aware.
---

# Line Repetition Control

## Overview
Detects and reports unintentional line or block repetitions often produced by AI agents during code generation. It uses smart heuristics to filter out intentional syntactic repetitions (like closing brackets or boilerplate).

## Capabilities
- Detect consecutive identical lines (ignoring whitespace).
- Detect consecutive identical code blocks (2-5 lines).
- Counts repetitions beyond 2x (e.g., reports "Repeated 4x").
- Built-in `.gitignore` awareness (via `git ls-files`).
- Parallel processing for codebase-wide scanning.

## Usage

### High-Performance Python Scanner (Recommended)
Best for large projects and codebase-wide scans.
```bash
uv run ~/.config/opencode/skills/line-repetition-control/scripts/detect_repeats_fast.py [path]
```

### Shell Implementation (Awk-based)
Lightweight alternative for single-file scanning.
```bash
bash ~/.config/opencode/skills/line-repetition-control/scripts/detect_repeats.sh <path_to_file>
```

## Heuristics
1. **Minimum Length**: Single-word lines or lines shorter than 3 characters are ignored unless they are part of a larger block.
2. **Exception List**: Common keywords, single brackets (`}`, `else`, `end`), and closure patterns (`});`, `},`, `],`) are excluded.
3. **Separator Filtering**: Comment separators like `// ============`, `# ------------`, or `***` are automatically ignored to avoid false positives in structured code.
4. **Block Detection**: Identifies repeated sequences of lines, prioritizing larger blocks (up to 5 lines) to catch degenerate "looping" failures.
4. **Git-Awareness**: Automatically skips files ignored by `.gitignore`.

## Examples
**Input Code:**
```python
def example():
    print("hello")
    print("hello")
    print("hello")
    return True
    return True
```

**Detection Output:**
- Line 2: Repeated 3x: print("hello")
- Line 5: Repeated 2x: return True

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
    }
  ]
}
```
