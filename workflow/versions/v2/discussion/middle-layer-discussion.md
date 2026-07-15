# v2 Middle-layer Discussion

## Workflow Carry-forward

- Version: `v2`
- Discussion feeds one governance-adoption change ledger.
- Middle-layer and changes must agree on Exact Docs, allowed paths, validation, and execution boundaries.
- Plans and drafts keep copy-ready implementation and read-only acceptance separate.
- Promotion preview must not write v2 execution or historical v1 execution.

## Local Queue

- Local phase: `phase-0`
- Local batch: `0-1`
- Local task start: `task-01`

## Required Sync Targets

- Docs: `docs/governance/**`, `CODE_REVIEW.md`, `CONTRIBUTING.md`, `docs/development/ci-governance.md`.
- Governance adapters: `.ai-governance/**`, `.github/PULL_REQUEST_TEMPLATE.md`.
- Checks: `scripts/areaflow_shim.py`, `scripts/dev_tools/checks.py`, `scripts/task_loop/self_check.py`.
- API: none.
- UDL: none.
- Product code: none.

## Layer Decisions

- `middle-layer`: one governance-adoption mapping.
- `changes`: one governance-adoption change ledger.
- `plans`: one plan with exact paths and validation.
- `drafts`: separate authoring copy-ready and read-only verify-ready artifacts.
- `queue`: version-local governance authoring entry only.
- `promotion`: preview-only, live mapping pending.
- `execution`: blocked until a separate execution cutover is approved.

