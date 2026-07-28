# v4 Observability And Diagnostics

`v4` owns the AreaMatrix structured observability, local diagnostics, user incident capture,
developer trace console, privacy-preserving diagnostic package, and support handoff contracts.

Product and architecture behavior remains authoritative under `docs/`. This version carries the
approved design through middle-layer, changes, plans, drafts, queue, and promotion review without
writing live execution before explicit approval and mapping.

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
`workflow/versions/v4/execution/**`. Historical v1 execution now lives at
`workflow/versions/v1-mvp/execution/**`.
