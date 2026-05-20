#!/usr/bin/env python3
# /// script
# dependencies = []
# ///

import re
import os
import sys
import json
import argparse
import concurrent.futures
from pathlib import Path
from typing import List, Dict, Any, Tuple

# ── Heuristic Exception List (Lines to ignore if repeated) ──────────────────────

EXCEPTIONS = frozenset({
    '', '{', '}', '[', ']', '(', ')',
    'else:', 'else', 'end', 'pass', 'continue', 'break',
    '});', '};', '],', '},', ');', '),',
    'return', 'return;', 'return null', 'return nil', 'return True', 'return False',
    'break;', 'continue;', 'super();',
})

# Precompiled patterns for performance
_SEPARATOR_RE = re.compile(r'^[/#\- \t]*([=\-_*])\1{2,}[ \t]*$')
_STRING_LITERAL_RE = re.compile(r'''(?:"[^"]*"|'[^']*')''')
_NUMERIC_RE = re.compile(r'\b\d+\.?\d*\b')
_HEX_RE = re.compile(r'0x[0-9a-fA-F]+')
_WHITESPACE_RE = re.compile(r'\s+')

# Lines that normalize to import/require patterns are structural, not AI failures
# Lines that normalize to structural patterns are NOT AI failures:
# - import/require/include (module loading)
# - puts/print/log/warn/printf (output formatting)
_STRUCTURAL_NORM_RE = re.compile(
    r'^(require |require_relative |import |from \S+ import |#include |use |include '
    r'|puts |print |warn |@out\.puts |logger\.\w+ |console\.log |printf |fmt\.)'
)

# ── Binary detection ────────────────────────────────────────────────────────────

def is_binary(file_path: Path, sample_size: int = 8192) -> bool:
    """Check first N bytes for null byte (universal binary indicator)."""
    try:
        with open(file_path, 'rb') as f:
            chunk = f.read(sample_size)
            return b'\x00' in chunk
    except OSError:
        return True

# ── Heuristic filters ───────────────────────────────────────────────────────────

def is_ignorable_line(line: str) -> bool:
    """Check if a line is a common separator, bracket, or boilerplate."""
    if line in EXCEPTIONS or len(line) < 3:
        return True
    if _SEPARATOR_RE.match(line):
        return True
    return False

def normalize_line(line: str) -> str:
    """Normalize a line for near-duplicate detection.

    Replaces string literals, numbers, and hex literals with placeholders,
    then collapses whitespace. This catches AI agent failures like:
        logger.info("Processing item 1")
        logger.info("Processing item 2")
    which normalize to the same string.
    """
    s = _STRING_LITERAL_RE.sub('""', line)
    s = _HEX_RE.sub('0x0', s)
    s = _NUMERIC_RE.sub('0', s)
    s = _WHITESPACE_RE.sub(' ', s).strip()
    return s

# ── Git awareness ───────────────────────────────────────────────────────────────

def get_ignored_paths(root_path: Path) -> set:
    """Return set of absolute paths git would ignore."""
    ignored = set()
    try:
        import subprocess
        cmd = [
            "git", "-C", str(root_path),
            "ls-files", "--others", "--ignored",
            "--exclude-standard", "--directory",
        ]
        output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        for line in output.splitlines():
            ignored.add(str(root_path / line.strip().rstrip('/')))
    except Exception:
        pass
    return ignored

# ── Core detection ──────────────────────────────────────────────────────────────

def detect_repetitions_in_content(content: List[str]) -> List[Dict[str, Any]]:
    """Detect both exact and near-duplicate repetitions.

    Returns findings sorted by line number, with exact matches preferred
    over near-duplicates at the same location.
    """
    findings: List[Dict[str, Any]] = []
    raw_lines = content
    stripped = [line.strip() for line in content]
    normalized = [normalize_line(s) for s in stripped]
    num_lines = len(stripped)

    i = 0
    while i < num_lines - 1:
        cur_stripped = stripped[i]
        cur_normalized = normalized[i]

        # Skip ignorable lines entirely
        if is_ignorable_line(cur_stripped):
            i += 1
            continue

        # ── 1. Exact consecutive line detection ──────────────────────────────
        exact_count = 1
        while i + exact_count < num_lines and stripped[i + exact_count] == cur_stripped:
            exact_count += 1

        if exact_count > 1:
            findings.append({
                "type": "consecutive_line",
                "line_start": i + 1,
                "content": cur_stripped,
                "count": exact_count,
            })
            i += exact_count
            continue

        # ── 2. Near-duplicate consecutive line detection ─────────────────────
        # Same structure but different literals/numbers
        # Skip import/require/include patterns (structural, not AI failures)
        if _STRUCTURAL_NORM_RE.match(cur_normalized):
            i += 1
            continue
        near_count = 1
        while i + near_count < num_lines and normalized[i + near_count] == cur_normalized:
            # Don't group if the raw lines are actually identical (already handled above)
            # or if the next line is ignorable on its own
            if stripped[i + near_count] == cur_stripped:
                break
            if is_ignorable_line(stripped[i + near_count]):
                break
            near_count += 1

        if near_count > 1:
            findings.append({
                "type": "near_duplicate",
                "line_start": i + 1,
                "content": cur_stripped,
                "variants": stripped[i + 1 : i + near_count],
                "count": near_count,
            })
            i += near_count
            continue

        # ── 3. Block detection (2-5 lines), exact match ──────────────────────
        found_block = False
        for block_size in range(5, 1, -1):
            if i + block_size * 2 > num_lines:
                continue

            block = stripped[i : i + block_size]

            # All-ignorable blocks are not interesting
            if all(is_ignorable_line(ln) for ln in block):
                continue

            block_count = 1
            while i + (block_count + 1) * block_size <= num_lines:
                next_block = stripped[i + block_count * block_size : i + (block_count + 1) * block_size]
                if next_block == block:
                    block_count += 1
                else:
                    break

            if block_count > 1:
                findings.append({
                    "type": "consecutive_block",
                    "line_start": i + 1,
                    "block_size": block_size,
                    "content": block,
                    "count": block_count,
                })
                i += block_size * block_count
                found_block = True
                break

        if not found_block:
            i += 1

    return findings

# ── File processing ─────────────────────────────────────────────────────────────

def process_file(file_path: Path) -> Tuple[str, List[Dict[str, Any]]]:
    """Process a single file, skipping binaries."""
    try:
        if is_binary(file_path):
            return str(file_path), []

        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.readlines()

        findings = detect_repetitions_in_content(content)
        return str(file_path), findings
    except Exception as e:
        return str(file_path), [{"error": str(e)}]

def scan_codebase(root_path: Path, extensions: set, exclude_dirs: set):
    """Scan codebase in parallel, respecting .gitignore."""
    ignored_paths = get_ignored_paths(root_path)
    tasks = []

    for root, dirs, files in os.walk(root_path):
        current_root = Path(root)
        dirs[:] = [
            d for d in dirs
            if d not in exclude_dirs and str(current_root / d) not in ignored_paths
        ]

        for fname in files:
            fp = current_root / fname
            if fp.suffix in extensions and str(fp) not in ignored_paths:
                tasks.append(fp)

    all_results: Dict[str, List[Dict[str, Any]]] = {}

    if len(tasks) < 5:
        for f in tasks:
            name, results = process_file(f)
            if results:
                all_results[name] = results
    else:
        with concurrent.futures.ProcessPoolExecutor() as pool:
            futures = {pool.submit(process_file, f): f for f in tasks}
            for future in concurrent.futures.as_completed(futures):
                name, results = future.result()
                if results:
                    all_results[name] = results

    return all_results

# ── Output formatting ───────────────────────────────────────────────────────────

def severity_of(count: int) -> str:
    if count >= 5:
        return "critical"
    if count >= 3:
        return "high"
    return "low"

def print_human(all_results: Dict, show_summary: bool = False) -> int:
    """Print human-readable output. Returns total finding count."""
    total_findings = 0
    total_files = 0
    sev_counts = {"critical": 0, "high": 0, "low": 0}

    if not all_results:
        print("No significant repetitions found.")
        return 0

    for file_path, reps in sorted(all_results.items()):
        total_files += 1
        print(f"\n[FILE] {file_path}")
        for rep in reps:
            if "error" in rep:
                print(f"  !! Error: {rep['error']}")
                continue

            total_findings += 1
            count = rep['count']
            sev = severity_of(count)
            sev_counts[sev] += 1
            tag = sev.upper()

            if rep['type'] == 'consecutive_line':
                print(f"  [{tag}] Line {rep['line_start']}: Repeated {count}x -> {rep['content']}")
            elif rep['type'] == 'near_duplicate':
                print(f"  [{tag}] Line {rep['line_start']}: Near-duplicate {count}x -> {rep['content']}")
                for v in rep.get('variants', []):
                    print(f"         variant: {v}")
            else:
                print(f"  [{tag}] Line {rep['line_start']}: Repeated block ({rep['block_size']} lines) {count}x")
                for line in rep['content']:
                    print(f"    > {line}")

    if show_summary:
        print(f"\n{'─' * 50}")
        print(f"Files with issues: {total_files}")
        print(f"Total findings:    {total_findings}")
        if total_findings:
            print(f"  Critical (>=5x): {sev_counts['critical']}")
            print(f"  High (>=3x):     {sev_counts['high']}")
            print(f"  Low (2x):        {sev_counts['low']}")

    return total_findings

# ── CLI ─────────────────────────────────────────────────────────────────────────

DEFAULT_EXTS = (
    ".py,.js,.ts,.jsx,.tsx,.c,.cpp,.h,.hpp,.rs,.go,.sh,.bash,.zsh,"
    ".java,.php,.rb,.lua,.swift,.kt,.scala,.clj,.ex,.exs,.erl,.hs,"
    ".ml,.nim,.zig,.r,.R,.sql,.html,.css,.scss,.vue,.svelte,"
    ".yaml,.yml,.toml,.json,.md,.rst,.txt,.cfg,.ini,.conf,.env"
)

DEFAULT_EXCLUDE = ".git,__pycache__,node_modules,dist,build,venv,.venv,target,cargo-target,.cache,.next,.nuxt"

def main():
    parser = argparse.ArgumentParser(
        description="Detect unintentional line/block repetitions (exact + near-duplicates)."
    )
    parser.add_argument("path", nargs="?", default=".", help="Root path to scan (default: .)")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--summary", action="store_true", help="Print summary statistics")
    parser.add_argument("--ext", default=DEFAULT_EXTS, help="Comma-separated file extensions")
    parser.add_argument("--exclude", default=DEFAULT_EXCLUDE, help="Comma-separated dirs to exclude")
    parser.add_argument("--min-count", type=int, default=2, help="Minimum repetition count to report (default: 2)")
    args = parser.parse_args()

    extensions = {f".{e.lstrip('.')}" for e in args.ext.split(",")}
    exclude_dirs = set(args.exclude.split(","))
    root_path = Path(args.path).resolve()

    if not root_path.exists():
        print(f"Error: Path {root_path} does not exist.", file=sys.stderr)
        sys.exit(2)

    # Single file mode
    if root_path.is_file():
        name, results = process_file(root_path)
        all_results = {name: results} if results else {}
    else:
        all_results = scan_codebase(root_path, extensions, exclude_dirs)

    # Filter by min-count
    if args.min_count > 2:
        filtered = {}
        for fp, reps in all_results.items():
            kept = [r for r in reps if "error" in r or r.get("count", 0) >= args.min_count]
            if kept:
                filtered[fp] = kept
        all_results = filtered

    # Output
    total = 0
    if args.json:
        print(json.dumps(all_results, indent=2))
        total = sum(len(v) for v in all_results.values())
    else:
        total = print_human(all_results, show_summary=args.summary)

    # Exit code: 1 if repetitions found, 0 if clean
    sys.exit(1 if total > 0 else 0)

if __name__ == "__main__":
    main()
