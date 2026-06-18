# AreaMatrix Workflow Versions

This directory tracks versioned workflow instances, Stage 1 MVP archives, and future planning work.

- `v1-mvp/` archives the completed MVP workflow. The 637-task queue is complete and the closeout decision is recorded, but formal alpha remains blocked by deferred release evidence.
- `v1-mvp/source-docs/` also archives the historical internal Stage 1/2/3/4 specs from the MVP task queue. Those numbers are not future workflow versions.
- `v2/`, `v3/`, and `v4/` are intentionally absent until those real future versions are created.
- `source-docs-guide.md` explains how to read the archived Stage 1 MVP source docs, including page specs, Core capability specs, and control maps.
- `v-template/` is the managed template reference instance. It validates the reusable artifact chain and must never promote into `workflow/versions/v-template/execution/**`.
- Future versions should be created from `v-template` / `workflow/templates/` only after the relevant discussion gate is ready.
- New versions use version-local numbering (`phase-0 / 0-1 / task-01`) and leave live mapping pending until explicitly configured.

Current v1 execution state:

- prompts: `workflow/versions/v1-mvp/execution/**`
- progress: `workflow/versions/v1-mvp/execution/_shared/progress.json`
- runner: `./task-loop`
- console: `./dev`

Use:

```bash
./dev workflow doctor
./dev workflow status
./dev workflow check-template
./dev workflow middle --version v-template doctor
./dev workflow middle --version v-template preview
./dev workflow plan
./dev workflow queue
```

Real version zero-start path:

```bash
./dev workflow init --version v2
./dev workflow init --version v2 --write
./dev workflow discuss --version v2 doctor
```

Only enter baseline, middle-layer, changes, plans, drafts, queue, and promotion
preview after the discussion gate is explicitly ready.
