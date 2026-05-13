# Promotion Preview Template

Promotion preview maps semantic workflow tasks to future live `tasks/prompts/**`
labels without writing the live queue.

- Mode: preview only
- Target queue: `tasks/prompts`
- Version-local label example: `phase-0 / 0-1 / task-01`
- Live mapping: pending until explicitly configured
- Future live label example after mapping: `v*-feature-id/docs-contract` -> `5-1/task-01`
- Gate: blocked while prerequisite versions are still live-running

Use this as a review artifact before implementing a future explicit apply step.
