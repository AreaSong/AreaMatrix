# v2 Execution

Execution is the version-local target for separately approved copy-ready, verify-ready, manifest, progress, checkpoint, log, and report material. The current governance authoring cutover does not authorize any of those writes.

- Version-local queue starts at `phase-0 / 0-1 / task-01`.
- Execution root: `workflow/versions/v2/execution/`.
- Historical v1 execution root: `workflow/versions/v1-mvp/execution/`.
- Do not modify execution files or progress from this layer unless the layer is explicit promoted execution.
- Promotion approval, live mapping, recovery evidence, and execution cutover are all absent; keep this directory at README-only state.
