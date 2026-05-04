# AreaMatrix Workflow Versions

This directory tracks versioned workflow instances without moving the live v1 task queue.

- `v1-mvp/` records the current `tasks/prompts/**` queue as the active MVP workflow. It is a placeholder only until the 637-task queue is finished and archived.
- `v2/` is the first reusable v* instance. It can advance through changes, plans, drafts, and queue candidates while v1 is still running, but it cannot promote into `tasks/prompts/**`.
- Future versions should be created with `./dev workflow init --version v3`.
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
./dev workflow plan --version v2
./dev workflow queue --version v2
./dev workflow init --version v3
```
