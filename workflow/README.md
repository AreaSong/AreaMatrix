# AreaMatrix Workflow

`workflow/` tracks large feature, version, refactor, and optimization lifecycles.
The target standard keeps version planning and version execution together under
`workflow/versions/<version>/`. The historical Stage 1 execution queue has been
hard-migrated to `workflow/versions/v1-mvp/execution/**`.

## Layers

- `workflow/`: requirement flow, version planning, middle-layer ledgers, docs-change ledger, drafts, queue candidates, execution evidence, projection, and archive policy.
- `workflow/versions/<version>/execution/`: target standard location for approved copy-ready / verify-ready task execution materials.
- `workflow/versions/v1-mvp/execution/**`: Stage 1 historical execution queue and current v1 task-loop runtime.
- `workflow/residuals/`: cross-version residual index for release blockers, accepted exceptions, historical references, and template-only material. It is index-only and does not replace `docs/`, `evidence/`, `closeout/`, `tasks/active/**`, or live execution queues.
- `./task-loop`: runner that executes approved tasks; it does not make requirement decisions.

For the conceptual architecture behind these boundaries, see
[`architecture.md`](architecture.md).
For the pre-discussion question and routing entry, see
[`intake.md`](intake.md). For the detailed docs-to-task-loop execution flow, see
[`pipeline.md`](pipeline.md). For the execution layer contract, see
[`execution.md`](execution.md). For the hard migration record from historical
`tasks/prompts/**` into version-local execution, see
[`references/execution-hard-migration-plan.md`](references/execution-hard-migration-plan.md).

## Standard Flow

```text
intake
-> docs
-> workflow/templates
-> workflow/versions/v*/version.yaml
-> workflow/versions/v*/discussion
-> workflow/versions/v*/middle-layer
-> workflow/versions/v*/changes
-> workflow/versions/v*/plans
-> workflow/versions/v*/drafts
-> workflow/versions/v*/queue
-> workflow/versions/v*/promotion preview
-> workflow/versions/v*/execution
-> ./task-loop run
-> workflow/versions/v*/projection
-> workflow/versions/v*/closeout
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
`phase-0 / 0-1 / task-01`. Execution labels remain version-local;
new versions keep `promotion_preview.live_mapping: pending` until a later
explicit mapping step.

Check the managed template reference with:

```bash
./dev workflow check-template
```

`v-template` is only the golden reference for templates and doctors. It may show
future live paths in promotion preview, but those paths are not written unless a
later explicit apply gate passes; `v-template` itself can never apply to live
`workflow/versions/v-template/execution/**`.

Large features and versioned work go through `workflow` first. Small, already
clear bug fixes may use the lightweight `tasks/active/<number>.<slug>/`
structure without creating a full workflow version. `tasks/backlog/` remains a
candidate pool and is not current task progress.

Promotion preview maps semantic workflow tasks to future live task labels without
writing execution files. Real promotion into `workflow/versions/<version>/execution/**`
is a later explicit step and remains blocked until approval artifacts and live
mapping are configured, even after prerequisite versions are archived.
