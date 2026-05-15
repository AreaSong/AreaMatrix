# Version Plan Template

## Feature

- Version: `v*`
- Feature: `v*-feature-id`
- Module: `module`
- Status: `ready`
- Kind: workflow-plan
- Owner: `areamatrix-workflow-planning`
- Landing: `workflow/versions/v*/plans/<feature-id>.plan.md`

## Goal

- Deliver the smallest approved planning unit for this feature.

## Non-goals

- Do not write `tasks/prompts/**`.
- Do not write `tasks/prompts/_shared/progress.json`.
- Do not claim live task-loop execution or checkpoint evidence.

## Source of Truth

- Product docs: `docs/example/source.md`
- Discussion gate: `workflow/versions/v*/discussion/`
- Middle-layer ledger: `workflow/versions/v*/middle-layer/<feature-id>.yaml`
- Source change: `workflow/versions/v*/changes/<feature-id>.yaml`

## Docs Change Ledger

| File | Lines | Heading | Operation | Summary |
|---|---:|---|---|---|
| `docs/example/source.md` | 10-20 | Example heading | update | What changed and why. |

## Dependencies

- Feature dependencies: None
- Docs dependencies: None

## Code Impact

### Existing

- `apps/macos/AreaMatrix/**`

### Expected

- `apps/macos/AreaMatrix/Features/Example/**`

### Tests

- `apps/macos/AreaMatrixTests/**`

## Execution Order

1. Read the source of truth paths listed above.
2. Confirm non-goals and high-risk boundaries.
3. Update only the exact paths listed in Code Impact.
4. Render separate copy-ready and verify-ready drafts.
5. Run the validation commands below.

## Validation Commands

```bash
./dev workflow doctor
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
```

## Rollback / Blocked

- If source paths, owner / landing, exact paths, or validation commands are missing, keep status `blocked`.
- If promotion approval is missing, leave live mapping pending and do not write live queue files.
- If a preview artifact is wrong, fix or revert only the workflow/backlog artifact; do not repair by editing `tasks/prompts/**`.

## Task Split

- `docs-contract`: Align docs and public contracts.

## Queue Readiness

- Candidate only; not promoted to `tasks/prompts/**`.
