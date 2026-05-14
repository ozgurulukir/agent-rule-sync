#!/bin/bash

# detect_repeats.sh
# A shell-based wrapper for line repetition detection using awk and sed.

FILE=$1

if [[ -z "$FILE" ]]; then
    echo "Usage: $0 <file_path>"
    exit 1
fi

if [[ ! -f "$FILE" ]]; then
    echo "Error: File $FILE not found."
    exit 1
fi
# Respect .gitignore if it exists and git is available
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$GIT_ROOT" ]]; then
    if git -C "$GIT_ROOT" check-ignore -q "$FILE"; then
        # File is ignored by git, skip it
        exit 0
    fi
fi


# Use the AWK script for the heavy lifting
awk -f "$(dirname "$0")/detect_repeats.awk" "$FILE"
