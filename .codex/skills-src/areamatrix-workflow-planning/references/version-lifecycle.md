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
-> workflow/versions/<version>/execution/**
```

Layer responsibilities:

- `discussion`: decide docs scope and middle-layer handoff before prompt generation.
- `middle-layer`: feature-level handoff from docs semantics into change structure.
- `changes`: structured source for feature tracking.
- `plans`: docs-change ledger, code impact map, owner / landing, exact paths, validation commands, and blocked / rollback wording.
- `drafts`: reviewable manifest plus separate copy-ready and verify-ready prompt drafts.
- `queue`: candidate tasks, still outside live runner and still not progress state.
- `promotion preview`: semantic-to-numeric task mapping, no live writes.
- `workflow/versions/<version>/execution/**`: approved version-local execution queue only.

`v1-mvp` is archived with its technical queue complete. Its formal alpha
release residuals still block formal distribution, but they do not block future
version discussion, middle-layer, changes, plans, drafts, or queue candidates.
They do block claims that the v1 release / closeout residuals are closed.
`v-template` is a managed template reference instance for doctor coverage and is
not a real product workflow. Future real versions must pass discussion before
changes.

Check the managed template reference with `./dev workflow check-template`.

Create future versions with:

```bash
./dev workflow init --version v2
./dev workflow init --version v2 --write
./dev workflow discuss --version v2 doctor
```

New versions use version-local numbering starting at `phase-0 / 0-1 / task-01`;
live `workflow/versions/<version>/execution/**` mapping remains pending until a later explicit promotion
mapping step. Do not enter baseline, middle-layer, changes, plans, drafts,
queue, or promotion preview until the discussion gate is explicitly ready.

V2 bootstrap rule:

- Start with `workflow/versions/v2/discussion/` and keep open product scope questions in `discussion/decisions.yaml`.
- Do not turn discussion-period open questions into residual ledger items unless they become durable `blocked-decision`, `blocked-external`, `deferred`, `accepted-exception`, `reference-only`, or `template-only` states after the discussion gate decision.
- If v2 creates its own durable residuals, add `workflow/versions/v2/residuals/README.md` and `residuals.yaml`, then add a matching `version_residuals` entry in `workflow/residuals/residuals.yaml`.
- V2 can reach queue candidates while v1 release residuals remain open, but promotion into `workflow/versions/v2/execution/**` still requires explicit approval and live mapping.

Planning handoff requirements:

- Every plan must include goal, non-goals, source of truth, owner / landing, exact file paths, ordered execution steps, validation commands, and blocked / rollback wording.
- Copy-ready and verify-ready artifacts stay separate; copy-ready may implement, verify-ready is read-only acceptance.
- Backlog prompt packages stay outside live queue and must not write `workflow/versions/<version>/execution/**`, `workflow/versions/<version>/execution/_shared/progress.json`, checkpoints, run summaries, or runner locks.
- If any required source, path, validation command, owner, or promotion approval is missing, keep the artifact `blocked` or `not-ready` instead of promoting it.
