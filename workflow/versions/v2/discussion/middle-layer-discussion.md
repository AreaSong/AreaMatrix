# v2 Middle-layer Discussion

## Workflow Carry-forward

- Version: `v2`
- Stage name: not started.
- Discussion must feed `changes/*.yaml`.
- Changes must feed docs-change ledger plans.
- Plans and drafts must keep docs/API/UDL/task sync targets explicit.
- Queue candidates use the version-local queue before live promotion mapping is configured.
- Promotion preview must not write `workflow/versions/v2/execution/**`.

## Local Queue

- Local phase: `phase-0`
- Local batch: `0-1`
- Local task start: `task-01`

## Required Sync Targets

- Docs: `docs/README.md`, `docs/roadmap/milestones.md`
- API: to be confirmed after real v2 scope is approved
- UDL: to be confirmed after real v2 scope is approved
- Tasks: version-local queue candidates only until explicit promotion

## Layer Decisions

- `changes`: waiting for discussion approval.
- `plans`: waiting for changes.
- `drafts`: waiting for plans.
- `queue`: waiting for drafts.
- `promotion`: blocked until live mapping is configured.
