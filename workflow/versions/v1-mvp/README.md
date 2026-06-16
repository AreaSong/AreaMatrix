# v1-mvp Workflow

`v1-mvp` is the current AreaMatrix prompt queue: 637 tasks under `tasks/prompts/**`.

The live queue is complete (`637/637`), but this version is still in closeout.
Do not move, rename, or regenerate the live prompt queue while closeout is
blocked. The task-loop continues to read the existing prompt files and
`tasks/prompts/_shared/progress.json`, preserving completed progress and
evidence.

Current live sources:

- live queue: `tasks/prompts/**`
- task count source: `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- progress source: `tasks/prompts/_shared/progress.json`
- runner: `./task-loop`
- console: `./dev`

v1 skipped the workflow middle layers because MVP scope is mandatory: docs were directly split into executable tasks. That is acceptable for v1, but future v* work uses `changes -> plans -> drafts -> queue -> tasks`.

Closeout status:

- queue: complete (`637/637`)
- runner: idle, no stale in-progress tasks
- release: blocked; `0.1.0-local-qa` is internal QA only
- checkpoint evidence: incomplete; 36 completed tasks lack committed checkpoint metadata in `progress.json`
- archive readiness: blocked until release blockers and checkpoint evidence gaps are dispositioned

Future archive work can snapshot copy-ready, verify-ready, manifests, progress summaries, and run evidence here after the closeout blockers are resolved.
