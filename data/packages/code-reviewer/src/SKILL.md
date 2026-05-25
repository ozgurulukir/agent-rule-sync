# code-reviewer

Automated code quality review skill for AI coding agents.

## Overview

This skill runs a structured review pass over any code the agent writes or modifies. It checks for:

- Logic that could be simplified or extracted into reusable utilities
- Functions that violate single responsibility
- Inconsistent patterns compared to the rest of the codebase
- Performance inefficiencies (unnecessary re-renders, N+1 queries, blocking operations)
- Dead code and unused imports
- Naming that doesn't communicate intent

## Usage

Invoke automatically or with `/code-reviewer` in supported agents.

## Review Checklist

1. **Simplify**: Look for repeated patterns that can be extracted
2. **Single Responsibility**: Each function should do one thing well
3. **Naming**: Names should communicate intent clearly
4. **Performance**: Flag N+1 queries, unnecessary re-renders, blocking I/O
5. **Dead Code**: Remove unused imports, variables, and functions

## Output Format

Provide:
1. Issues found (grouped by severity)
2. Suggested fixes with code examples
3. Updated code if changes are straightforward
