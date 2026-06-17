# v1-mvp Workflow

`v1-mvp` is the archived AreaMatrix MVP prompt queue record: 637 tasks under `tasks/prompts/**`.

The live queue is complete (`637/637`). The closeout decision is recorded in
`closeout/closeout-decision.md`: v1 is technically complete, formal Stage 1
alpha remains blocked, and release blockers are deferred to the formal
distribution track. The historical prompt files remain in `tasks/prompts/**` for
traceability; do not rewrite `progress.json`, task-loop runs, or checkpoint
metadata to make the archive look cleaner.

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
- decision: technical completion recorded; formal alpha not approved
- release: blocked for formal Stage 1 alpha; `0.1.0-local-qa` is internal QA only, and
  `v0.1.0-unnotarized-preview.2` may be published only as a trusted-tester GitHub prerelease
- release blockers: deferred to formal distribution evidence, not closed
- checkpoint evidence: 36 completed tasks lack committed checkpoint metadata in `progress.json`
  - 35 have `VERIFY_RESULT: PASS` logs but no committed checkpoint metadata
  - 1 is a local QA / release gate sync entry without task-loop run evidence
  - detail: `workflow/versions/v1-mvp/closeout/checkpoint-gaps.md`
- dirty worktree: Xcode derived-data log removed from Git tracking and ignored via `.gitignore`
- archive readiness: Stage 1 source docs and release evidence are archived here; optional local log bundling remains a separate evidence decision

Future v2 work may start in `workflow/versions/v2/` discussion, middle-layer,
changes, plans, drafts, and queue candidates. Promotion / apply into
`tasks/prompts/**` still requires explicit approval and a configured live mapping.
