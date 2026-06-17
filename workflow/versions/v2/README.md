# v2 Workflow

`v2` is the Stage 2 `v2-experience` planning workflow instance created from the reusable v* template.

## Flow

```text
discussion
-> middle-layer
-> changes
-> plans
-> drafts
-> queue
-> promotion preview
-> future explicit promote into tasks/prompts/**
```

The version-local queue starts at `phase-0 / 0-1 / task-01`. Future live mapping
is pending and must be configured before promotion preview can target global
`tasks/prompts/**` labels.

Current status:

- discussion: draft, not approved
- changes / plans / drafts / queue: blocked until discussion gate passes
- live promotion: blocked until explicit approval and live mapping
- inherited release blockers: Developer ID / notarization evidence remains on the v1 formal distribution track, not inside v2 planning
