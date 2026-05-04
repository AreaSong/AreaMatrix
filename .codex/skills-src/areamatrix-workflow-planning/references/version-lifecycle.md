# Version Lifecycle

AreaMatrix workflow separates large planning work from live task execution.

Standard order:

```text
docs
-> workflow/templates
-> workflow/versions/v*/discussion
-> changes
-> plans
-> drafts
-> queue
-> promotion preview
-> tasks/prompts/**
```

Layer responsibilities:

- `discussion`: decide docs scope and middle-layer handoff before prompt generation.
- `changes`: structured source for feature tracking.
- `plans`: docs-change ledger and code impact map.
- `drafts`: reviewable manifest/copy/verify prompt drafts.
- `queue`: candidate tasks, still outside live runner.
- `promotion preview`: semantic-to-numeric task mapping, no live writes.
- `tasks/prompts/**`: approved small-task live queue only.

`v1-mvp` remains live-running until its current queue completes. Existing `v2` has a compatibility exemption because it predates the discussion gate. Future versions must pass discussion before changes.

