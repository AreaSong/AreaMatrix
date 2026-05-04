# v1-mvp Workflow

`v1-mvp` is the current AreaMatrix prompt queue: 637 tasks under `tasks/prompts/**`.

This directory is only an archive placeholder plus metadata for now. Do not move, rename, or regenerate the live prompt queue here while v1 is still running. The task-loop continues to read the existing prompt files and `tasks/prompts/_shared/progress.json`, preserving completed progress and evidence.

v1 skipped the workflow middle layers because MVP scope is mandatory: docs were directly split into executable tasks. That is acceptable for v1, but future v* work uses `changes -> plans -> drafts -> queue -> tasks`.

Future archive work can snapshot copy-ready, verify-ready, manifests, progress summaries, and run evidence here after the v1 queue is complete.
