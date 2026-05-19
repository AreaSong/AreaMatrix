# Queue Candidate Template

This file reviews whether a workflow feature is ready to become executable tasks.

- Status: `ready`
- Kind: queue-candidate
- Promotion: explicit only
- Live queue blocked: true while prerequisites are incomplete

## Candidate Tasks

- `v*-feature-id/docs-contract`

## Promotion Notes

Do not write `tasks/prompts/**` until promotion is explicitly requested and gates pass.
Do not write `tasks/prompts/_shared/progress.json`, checkpoints, run summaries,
or runner locks from queue candidate review.

Queue candidates must reference separate copy-ready and verify-ready drafts,
exact validation commands, and the source plan that owns the handoff.
