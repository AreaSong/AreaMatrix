# v1 Historical Workflow Archive

`v1-mvp` is the archived AreaMatrix v1 prompt queue record: 637 tasks under
`workflow/versions/v1-mvp/execution/**`.

The live queue is complete (`637/637`). The closeout decision is recorded in
`closeout/closeout-decision.md`: v1 is technically complete, formal v1 alpha
remains blocked, and release blockers are deferred to the formal
distribution track. The historical prompt files remain in `workflow/versions/v1-mvp/execution/**` for
traceability; do not rewrite `progress.json`, task-loop runs, or checkpoint
metadata to make the archive look cleaner.

Current live sources:

- live queue: `workflow/versions/v1-mvp/execution/**`
- task count source: `python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py doctor`
- progress source: `workflow/versions/v1-mvp/execution/_shared/progress.json`
- runner: `./task-loop`
- console: `./dev`

v1 skipped the workflow middle layers because its scope had already been fixed:
docs were directly split into executable tasks. That is acceptable for v1, but
future v* work uses `changes -> plans -> drafts -> queue -> tasks`.

Closeout status:

- queue: complete (`637/637`)
- runner: idle, no stale in-progress tasks
- decision: technical completion recorded; formal alpha not approved
- release: blocked for formal v1 alpha; `0.1.0-local-qa` is internal QA only, and
  `v0.1.0-unnotarized-preview.2` may be published only as a trusted-tester GitHub prerelease
- release blockers: deferred to formal distribution evidence, not closed; these are formal
  distribution blockers, not active task-loop work
- checkpoint evidence: 36 completed tasks lack committed checkpoint metadata in `progress.json`
  - 35 have `VERIFY_RESULT: PASS` logs but no committed checkpoint metadata
  - 1 is a local QA / release gate sync entry without task-loop run evidence
  - detail: `workflow/versions/v1-mvp/closeout/checkpoint-gaps.md`
- dirty worktree: Xcode derived-data log removed from Git tracking and ignored via `.gitignore`
- archive readiness: v1 historical source docs and release evidence are archived here; optional local log bundling remains a separate evidence decision
- source docs scope: internal v1 numbered specs from the completed task queue live under `source-docs/`; old 2/3/4 labels here are not future workflow versions

Future v* work must start by creating a real version from the workflow template,
then passing a fresh discussion under `workflow/versions/<version>/`;
it must not reuse the archived v1 internal numbered specs as current
version scope. Promotion / apply into `workflow/versions/<version>/execution/**` still requires explicit
approval and a configured live mapping.
