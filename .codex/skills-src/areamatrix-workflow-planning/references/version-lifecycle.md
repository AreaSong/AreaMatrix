# Version Lifecycle

AreaMatrix workflow separates large planning work from live task execution.

Standard order:

```text
docs
-> workflow/templates
-> workflow/versions/v*/discussion
-> middle-layer
-> changes
-> plans
-> drafts
-> queue
-> promotion preview
-> tasks/prompts/**
```

Layer responsibilities:

- `discussion`: decide docs scope and middle-layer handoff before prompt generation.
- `middle-layer`: feature-level handoff from docs semantics into change structure.
- `changes`: structured source for feature tracking.
- `plans`: docs-change ledger and code impact map.
- `drafts`: reviewable manifest/copy/verify prompt drafts.
- `queue`: candidate tasks, still outside live runner.
- `promotion preview`: semantic-to-numeric task mapping, no live writes.
- `tasks/prompts/**`: approved small-task live queue only.

`v1-mvp` remains live-running until its current queue completes. `v-template`
is a managed template reference instance for doctor coverage and is not a real
product workflow. Future real versions must pass discussion before changes.

Check the managed template reference with `./dev workflow check-template`.

Create future versions with:

```bash
./dev workflow init --version v2
./dev workflow init --version v2 --write
./dev workflow discuss --version v2 doctor
```

New versions use version-local numbering starting at `phase-0 / 0-1 / task-01`;
live `tasks/prompts/**` mapping remains pending until a later explicit promotion
mapping step. Do not enter baseline, middle-layer, changes, plans, drafts,
queue, or promotion preview until the discussion gate is explicitly ready.
