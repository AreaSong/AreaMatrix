# Promotion Preview Template

Promotion preview maps semantic workflow tasks to future live `tasks/prompts/**`
labels without writing the live queue.

- Mode: preview only
- Target queue: `tasks/prompts`
- Future label example: `v*-feature-id/docs-contract` -> `5-1/task-01`
- Gate: blocked while prerequisite versions are still live-running

Use this as a review artifact before implementing a future explicit apply step.
