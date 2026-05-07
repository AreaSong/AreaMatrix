# v-template Docs Discussion

## Feature Intent

- Version: `v-template`
- Intent: Maintain a concrete, machine-checkable reference instance for the workflow template chain.
- User paths:
  - A maintainer checks the workflow template contract with `./dev workflow doctor`.
  - A maintainer checks default versioned gates without creating a real product workflow.

## Exact Docs

- `workflow/architecture.md`
- `workflow/pipeline.md`

## Contention Points

- `v-template` is not a product feature and does not define AreaMatrix product behavior.
- `v-template` may preview promotion artifacts but must never apply them to live `tasks/prompts/**`.

## Non-goals

- Do not use this instance as a real v* product roadmap.
- Do not start task-loop from this instance.
- Do not modify live `tasks/prompts/**` or `progress.json`.

## Acceptance Boundary

- Every artifact can trace back to `workflow/architecture.md` or `workflow/pipeline.md`.
- Doctor commands validate schema, status, trace, drift, preview, projection, and closeout behavior.
- Promotion apply write remains blocked for `v-template`.
