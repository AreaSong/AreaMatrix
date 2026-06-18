# v2 Workflow Placeholder

`v2` is the real planning track for Stage 2 Experience Improvement after Stage
1 MVP historical execution closeout.

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
-> execution
-> projection
-> closeout
```

The version-local queue starts at `phase-0 / 0-1 / task-01`. Future execution
mapping is pending and must be configured before promotion preview can target
`workflow/versions/v2/execution/**`. Historical `workflow/versions/v2/execution/**` compatibility
remains until the hard migration is approved.

Current status:

- discussion: approved for initial middle-layer and changes ledgers
- changes / middle-layer: allowed for initial v2 scope ledger
- plans / drafts / queue: blocked until their own gates pass
- execution promotion: blocked until explicit approval and execution mapping
- inherited release blockers: Developer ID / notarization evidence remains on the v1 formal distribution track, not inside v2 planning
