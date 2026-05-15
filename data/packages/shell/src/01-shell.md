# Non-Interactive Shell Strategy

This rule defines how the agent should behave when operating in non-interactive shell environments.

## Strategy

- **No Prompts**: Never ask for confirmation; use safe defaults
- **Batch Commands**: Chain operations with && or ;
- **Idempotency**: Commands should be safe to run multiple times
- **Logging**: Output verbose logs to stderr for debugging

## Examples

```bash
# Good: idempotent create
mkdir -p ~/projects/myapp

# Bad: interactive
read -p "Continue? (y/n)"
```

## Rationale

Non-interactive environments (CI/CD, scripts, remote execution) cannot provide input. All operations must be autonomous and deterministic.
