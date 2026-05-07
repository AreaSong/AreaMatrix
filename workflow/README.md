# AreaMatrix Workflow

`workflow/` tracks large feature, version, refactor, and optimization lifecycles.
It is separate from `tasks/prompts/**`, which is the approved small-task execution queue.

## Layers

- `workflow/`: requirement flow, version planning, middle-layer ledgers, docs-change ledger, drafts, queue candidates, and archive policy.
- `tasks/prompts/**`: executable copy-ready / verify-ready task queue.
- `./task-loop`: runner that executes approved tasks; it does not make requirement decisions.

For the conceptual architecture behind these boundaries, see
[`architecture.md`](architecture.md).
For the detailed docs-to-task-loop execution flow, see
[`pipeline.md`](pipeline.md).

## Standard Flow

```text
docs
-> workflow/templates
-> workflow/versions/v*/version.yaml
-> workflow/versions/v*/discussion
-> workflow/versions/v*/middle-layer
-> workflow/versions/v*/changes
-> workflow/versions/v*/plans
-> workflow/versions/v*/drafts
-> workflow/versions/v*/queue
-> workflow/versions/v*/promotion preview
-> tasks/prompts/**
-> ./task-loop run
-> workflow/versions/v*/archive
```

New v* versions must pass the discussion gate before writing changes. The
discussion gate records docs intent, middle-layer carry-forward rules, decisions,
open questions, blockers, and whether the version may enter `changes/`.

`middle-layer/*.yaml` records feature-level implementation intent after docs
discussion: Exact Docs line references, insertion points, related feature links,
code impact, dependencies, slice plans, and risk boundaries. `changes/*.yaml`
stays focused on the docs-change ledger. Both sources must agree before plans,
drafts, queue candidates, or promotion preview are generated.

Create a new version skeleton with:

```bash
./dev workflow init --version v2
./dev workflow init --version v2 --write
./dev workflow discuss --version v2 doctor
```

Each v* has its own version-local queue numbering, starting at
`phase-0 / 0-1 / task-01`. Live `tasks/prompts/**` labels remain globally unique;
new versions keep `promotion_preview.live_mapping: pending` until a later
explicit mapping step.

Check the managed template reference with:

```bash
./dev workflow check-template
```

`v-template` is only the golden reference for templates and doctors. It may show
future live paths in promotion preview, but those paths are not written unless a
later explicit apply gate passes; `v-template` itself can never apply to live
`tasks/prompts/**`.

Large features and versioned work go through `workflow` first. Small, already
clear bug fixes can go directly to `tasks/prompts/**` or a focused local task.

Promotion preview maps semantic workflow tasks to future live task labels without
writing the live queue. Real promotion into `tasks/prompts/**` is a later
explicit step and remains blocked while prerequisite live versions are still
running.
