# Workstation Memory Constraints

This rule defines memory usage constraints for the agent operating on this workstation.

## Constraints

- **Max Context**: Do not exceed available RAM; monitor memory usage
- **Cleanup**: Clear temporary files after operations
- **Batch Size**: Process large datasets in chunks to avoid OOM

## Rationale

Memory is a finite resource. Agents must be mindful of their memory footprint to maintain system stability and performance.
