# v2 Workflow

`v2` is a planning workflow instance created from the reusable v* template.

## Flow

```text
discussion
-> middle-layer
-> changes
-> plans
-> drafts
-> queue
-> promotion preview
-> execution
-> projection
-> closeout
```

The version-local queue starts at `phase-0 / 0-1 / task-01`. Future execution
mapping is pending and must be configured before promotion preview can target
`workflow/versions/v2/execution/**`. Historical v1 execution now lives at
`workflow/versions/v1-mvp/execution/**`.

## Durable Residuals

Version-local governance residuals are indexed in [`residuals/`](residuals/):

- `v2-risk-001`: qualified independent review remains an open governance risk.
- `v2-dep-003`: promotion and live execution authorization remain deferred.
- `v2-dep-004`: remote CI and branch protection evidence remain deferred.

All three entries are non-executable indexes backed by
`docs/governance/governance-register.yaml`; they do not authorize promotion or execution.
