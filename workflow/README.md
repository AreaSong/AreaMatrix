# AreaMatrix Workflow

`workflow/` tracks large feature, version, refactor, and optimization lifecycles.
It is separate from `tasks/prompts/**`, which is the approved small-task execution queue.

## Layers

- `workflow/`: requirement flow, version planning, docs-change ledger, drafts, queue candidates, and archive policy.
- `tasks/prompts/**`: executable copy-ready / verify-ready task queue.
- `./task-loop`: runner that executes approved tasks; it does not make requirement decisions.

## Standard Flow

```text
docs
-> workflow/templates
-> workflow/versions/v*/version.yaml
-> workflow/versions/v*/changes
-> workflow/versions/v*/plans
-> workflow/versions/v*/drafts
-> workflow/versions/v*/queue
-> workflow/versions/v*/promotion preview
-> tasks/prompts/**
-> ./task-loop run
-> workflow/versions/v*/archive
```

Large features and versioned work go through `workflow` first. Small, already
clear bug fixes can go directly to `tasks/prompts/**` or a focused local task.

Promotion preview maps semantic workflow tasks to future live task labels without
writing the live queue. Real promotion into `tasks/prompts/**` is a later
explicit step and remains blocked while prerequisite live versions are still
running.
