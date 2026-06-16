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
- release: blocked for formal Stage 1 alpha; `0.1.0-local-qa` is internal QA only, and
  `v0.1.0-unnotarized-preview.1` may be published only as a trusted-tester GitHub prerelease
- checkpoint evidence: incomplete; 36 completed tasks lack committed checkpoint metadata in `progress.json`
  - 35 have `VERIFY_RESULT: PASS` logs but no committed checkpoint metadata
  - 1 is a local QA / release gate sync entry without task-loop run evidence
  - detail: `workflow/versions/v1-mvp/closeout/checkpoint-gaps.md`
- dirty worktree: Xcode derived-data log removed from Git tracking and ignored via `.gitignore`
- archive readiness: blocked until release blockers and checkpoint evidence gaps are dispositioned

Future archive work can snapshot copy-ready, verify-ready, manifests, progress summaries, and run evidence here after the closeout blockers are resolved.
