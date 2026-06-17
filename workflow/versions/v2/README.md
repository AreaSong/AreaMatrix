# v2 Workflow Placeholder

`v2` is a clean placeholder for the next real planning discussion after Stage 1 MVP closeout.

Historical Stage 2 Experience specs are archived under `workflow/versions/v1-mvp/source-docs/` because they belong to the Stage 1 MVP task history. They are reference material only and do not define the future v2 scope.

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

- discussion: not started, not approved
- changes / plans / drafts / queue: blocked until discussion gate passes
- live promotion: blocked until explicit approval and live mapping
- inherited release blockers: Developer ID / notarization evidence remains on the v1 formal distribution track, not inside v2 planning
