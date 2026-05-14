# Non-Interactive Shell Strategy

All shell commands **MUST be non-interactive**.

## Prohibited

- `sudo` without explicit user confirmation
- `apt`, `apt-get`, package manager operations
- Interactive prompts (`read`, `vim`, `less`, `fzf`)

## Required

- Use batch mode flags (`npm --yes`, `cargo -y`).
- Verify commands before execution.
- Check return codes (`|| exit 1`).
