# AreaMatrix Workflow Versions

This directory tracks versioned workflow instances without moving the live v1 task queue.

- `v1-mvp/` records the current `tasks/prompts/**` queue as the active MVP workflow. It is a placeholder only until the 637-task queue is finished and archived.
- `v-template/` is the managed template reference instance. It validates the reusable artifact chain and must never promote into `tasks/prompts/**`.
- Future versions should be created with `./dev workflow init --version v2` or another real `vN`.
- New versions use version-local numbering (`phase-0 / 0-1 / task-01`) and leave live mapping pending until explicitly configured.

Current live state remains:

- prompts: `tasks/prompts/**`
- progress: `tasks/prompts/_shared/progress.json`
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
./dev workflow init --version v2
```

Real version zero-start path:

```bash
./dev workflow init --version v2
./dev workflow init --version v2 --write
./dev workflow discuss --version v2 doctor
```

Only enter baseline, middle-layer, changes, plans, drafts, queue, and promotion
preview after the discussion gate is explicitly ready.
