# v3 Workflow

`v3` is a planning workflow instance created from the reusable v* template.

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
`workflow/versions/v3/execution/**`. Historical v1 execution now lives at
`workflow/versions/v1-mvp/execution/**`.
