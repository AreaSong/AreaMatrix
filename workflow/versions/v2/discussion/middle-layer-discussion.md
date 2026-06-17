# v2 Middle-layer Discussion

## Workflow Carry-forward

- Version: `v2`
- Stage name: `v2-experience`
- Discussion must feed `changes/*.yaml`.
- Changes must feed docs-change ledger plans.
- Plans and drafts must keep docs/API/UDL/task sync targets explicit.
- Queue candidates use the version-local queue before live promotion mapping is configured.
- Promotion preview must not write live `tasks/prompts/**`.

## Local Queue

- Local phase: `phase-0`
- Local batch: `0-1`
- Local task start: `task-01`

## Required Sync Targets

- Docs: `docs/roadmap/milestones.md`, `docs/ux/page-specs/stage-2-experience.md`, `docs/core/capability-specs/stage-2-experience.md`
- API: to be confirmed per Stage 2 feature
- UDL: to be confirmed per Stage 2 feature
- Tasks: version-local queue candidates only until explicit promotion

## Layer Decisions

- `changes`: waiting for discussion approval.
- `plans`: waiting for changes.
- `drafts`: waiting for plans.
- `queue`: waiting for drafts.
- `promotion`: blocked until live mapping is configured.
