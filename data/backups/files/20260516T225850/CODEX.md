EXISTING CODEX

<!-- rulepack:codex_vendor start -->
# Codex Skills

Skill definitions aggregated by the SSoT system for Codex CLI. Codex reads this from `AGENTS.md` in the project root.


---

# Workstation Memory Constraints

## Overview

Memory is a finite resource. Agents must be mindful of their memory footprint to maintain system stability and performance.

## Capabilities

- **Max Context**: Do not exceed available RAM; monitor memory usage
- **Cleanup**: Clear temporary files after operations
- **Batch Size**: Process large datasets in chunks to avoid OOM


---

# Non-Interactive Shell Strategy

## Overview

Non-interactive environments (CI/CD, scripts, remote execution) cannot provide input. All operations must be autonomous and deterministic.

## Usage

- **No Prompts**: Never ask for confirmation; use safe defaults
- **Batch Commands**: Chain operations with && or ;
- **Idempotency**: Commands should be safe to run multiple times
- **Logging**: Output verbose logs to stderr for debugging


---

# Codex Skills

Skill definitions aggregated by the SSoT system for Codex CLI. Codex reads this from `AGENTS.md` in the project root.

<!-- rulepack:codex_vendor end -->