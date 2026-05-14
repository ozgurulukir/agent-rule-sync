# Workstation Memory Constraints

This rule defines memory usage constraints for the agent operating on this workstation.

## Constraints

- **Max Context**: Do not exceed available RAM; monitor memory usage
- **Cleanup**: Clear temporary files after operations
- **Batch Size**: Process large datasets in chunks to avoid OOM

## Rationale

Memory is a finite resource. Agents must be mindful of their memory footprint to maintain system stability and performance.


---

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


---

# Vibe Security Skill

Audit codebases for security vulnerabilities commonly introduced by AI code generation in "vibe-coded" applications.

## Checks

- Exposed secrets (API keys, tokens)
- Broken access control (RLS, Firebase rules)
- Missing auth validation
- Client-side trust issues
- Insecure payment flows

## Usage

Trigger when:
- User asks about security
- Mentions "vibe coding"
- Requests code review
- Handles auth/payments/user data
