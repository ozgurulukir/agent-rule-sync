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
from typing import List, Dict, Any

# Heuristic Exception List (Lines to ignore if repeated)
EXCEPTIONS = {
    '', '{', '}', '[', ']', '(', ')', 'else:', 'else', 'end', 'pass', 'continue', 'break',
    '});', '};', '],', '},', ');', '),'
}

def is_ignorable_line(line: str) -> bool:
    """Heuristic to check if a line is a common separator or boilerplate."""
    if line in EXCEPTIONS or len(line) < 3:
        return True
    
    # Filter out common comment/visual separators (e.g., // ============, # ------------)
    # If the line consists only of comment markers and 3+ repeating symbols
    if re.match(r'^(/+|#|--|[ \t])*([=\-_*])\2\2+[ \t]*$', line):
        return True
        
    return False

def get_ignored_files(root_path: Path) -> set:
    """Uses git ls-files to get all ignored files authoritatively if in a git repo."""
    ignored = set()
    try:
        import subprocess
        # Get all files that git would ignore or doesn't know about
        cmd = ["git", "-C", str(root_path), "ls-files", "--others", "--ignored", "--exclude-standard", "--directory"]
        output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        for line in output.splitlines():
            ignored.add(str(root_path / line.strip().rstrip('/')))
    except Exception:
        pass
    return ignored

def detect_repetitions_in_content(content: List[str]) -> List[Dict[str, Any]]:
    """Optimized core detection logic."""
    findings = []
    lines = [line.strip() for line in content]
    num_lines = len(lines)
    
    i = 0
    while i < num_lines - 1:
        current_line = lines[i]
        
        # 1. Consecutive Line Detection
        if not is_ignorable_line(current_line):
            count = 1
            while i + count < num_lines and lines[i + count] == current_line:
                count += 1
            
            if count > 1:
                findings.append({
                    "type": "consecutive_line",
                    "line_start": i + 1,
                    "content": current_line,
                    "count": count
                })
                i += count
                continue

        # 2. Block Detection (2-5 lines) - priority to larger blocks
        found_block = False
        for block_size in range(5, 1, -1):
            if i <= num_lines - (block_size * 2):
                block = lines[i : i + block_size]
                
                # Count how many times this block repeats consecutively
                count = 1
                while i + (count + 1) * block_size <= num_lines:
                    next_block = lines[i + count * block_size : i + (count + 1) * block_size]
                    if next_block == block:
                        count += 1
                    else:
                        break
                
                if count > 1 and any(not is_ignorable_line(line) for line in block):
                    findings.append({
                        "type": "consecutive_block",
                        "line_start": i + 1,
                        "block_size": block_size,
                        "content": block,
                        "count": count
                    })
                    i += (block_size * count)
                    found_block = True
                    break
        if not found_block:
            i += 1

    return findings

def process_file(file_path: Path) -> tuple[str, List[Dict[str, Any]]]:
    """Worker function for parallel processing."""
    try:
        # Use fast IO reading
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.readlines()
        findings = detect_repetitions_in_content(content)
        return str(file_path), findings
    except Exception as e:
        return str(file_path), [{"error": str(e)}]

def scan_codebase(root_path: Path, extensions: set, exclude_dirs: set):
    """Scans the codebase in parallel, respecting .gitignore via git-awareness."""
    ignored_paths = get_ignored_files(root_path)
    tasks = []
    
    for root, dirs, files in os.walk(root_path):
        current_root = Path(root)
        # Filter dirs
        dirs[:] = [d for d in dirs if d not in exclude_dirs and str(current_root / d) not in ignored_paths]
        
        for file in files:
            file_path = current_root / file
            if file_path.suffix in extensions and str(file_path) not in ignored_paths:
                tasks.append(file_path)
    
    all_results = {}
    # Use ProcessPoolExecutor only for non-trivial number of files
    if len(tasks) < 5:
        for f in tasks:
            file_name, results = process_file(f)
            if results:
                all_results[file_name] = results
    else:
        with concurrent.futures.ProcessPoolExecutor() as executor:
            future_to_file = {executor.submit(process_file, f): f for f in tasks}
            for future in concurrent.futures.as_completed(future_to_file):
                file_name, results = future.result()
                if results:
                    all_results[file_name] = results
                
    return all_results

def main():
    parser = argparse.ArgumentParser(description="High-performance repetition detector.")
    parser.add_argument("path", nargs="?", default=".", help="Root path to scan (default: current dir)")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--ext", default=".py,.js,.ts,.c,.cpp,.rs,.go,.sh,.java,.php", help="Comma-separated extensions")
    parser.add_argument("--exclude", default=".git,__pycache__,node_modules,dist,build,venv,.venv", help="Comma-separated dirs to exclude")
    args = parser.parse_args()

    extensions = {f".{ext.lstrip('.')}" for ext in args.ext.split(",")}
    exclude_dirs = set(args.exclude.split(","))
    root_path = Path(args.path)

    if not root_path.exists():
        print(f"Error: Path {root_path} does not exist.")
        sys.exit(1)

    if root_path.is_file():
        file_name, results = process_file(root_path)
        all_results = {file_name: results} if results else {}
    else:
        all_results = scan_codebase(root_path, extensions, exclude_dirs)

    if args.json:
        print(json.dumps(all_results, indent=2))
    else:
        if not all_results:
            print("No significant repetitions found.")
        else:
            for file, reps in all_results.items():
                print(f"\n[FILE] {file}")
                for rep in reps:
                    if "error" in rep:
                        print(f"  !! Error: {rep['error']}")
                    elif rep['type'] == 'consecutive_line':
                        print(f"  - Line {rep['line_start']}: Repeated {rep['count']}x -> {rep['content']}")
                    else:
                        print(f"  - Line {rep['line_start']}: Repeated Block ({rep['block_size']} lines)")
                        for line in rep['content']:
                            print(f"    > {line}")

if __name__ == "__main__":
    main()
