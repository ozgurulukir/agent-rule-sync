# ast-grep for Structural Code Search

Prefer `ast-grep` over text-based search (grep/rg) when searching for code patterns that involve structure, not just text.

## When to use ast-grep

- Searching for specific language constructs (function declarations, class definitions, method calls)
- Queries involving code relationships (function X contains Y, A is inside B)
- Pattern matching with wildcards (find all calls to `console.log`, find all async functions with await)
- Any search where AST structure matters more than raw text

## When to use grep instead

- Searching for string literals, comments, or exact text
- Simple file content searches where structure is irrelevant
- Searching non-code files (markdown, yaml, json configs)

## Command patterns

Simple pattern search:
```bash
ast-grep run --pattern 'PATTERN' --lang LANGUAGE /path/to/project
```

Rule-based search (for relational/complex queries):
```bash
ast-grep scan --inline-rules "id: rule-name
language: LANGUAGE
rule:
  kind: node_kind
  has:
    pattern: PATTERN
    stopBy: end" /path/to/project
```

Debug AST structure:
```bash
ast-grep run --pattern 'CODE' --lang LANGUAGE --debug-query=cst
```

Always use `stopBy: end` for relational rules (`has`, `inside`).

## Language mapping

For TypeScript/Vue projects, use `--lang typescript` for `.ts`, `.tsx`, `.vue` files (TypeScript portions).

## Skill

The full ast-grep skill with detailed rule syntax and examples is available via the `ast-grep` skill. Load it with the skill tool when you need detailed rule reference (metavariables, composite rules, relational patterns).
