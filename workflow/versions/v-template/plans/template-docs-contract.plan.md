# Workflow Plan: template-docs-contract

- Version: `v-template`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Module: `workflow-template`
- Status: `ready`
- Kind: `workflow-plan`
- Depends on: None
- Risk: `Low`

## Intent

Prove that template workflow artifacts keep Exact Docs, discussion decisions, and baseline drift checks traceable.

## Docs Change Ledger

| File | Lines | Heading | Operation | Summary | Tasks |
|---|---:|---|---|---|---|
| `workflow/architecture.md` | 17-30 | Architecture Layers | reference | Architecture layers define the conceptual contract that the template instance demonstrates. | `docs-baseline`, `discussion-gate` |
| `workflow/pipeline.md` | 72-91 | docs baseline snapshot | reference | Baseline snapshot is the drift contract that every downstream artifact must preserve. | `docs-baseline` |

## Middle-layer Ledger

- Middle-layer ledger: `workflow/versions/v-template/middle-layer/template-docs-contract.yaml`
- Feature dependencies: None

### Insertions
- `workflow template Exact Docs contract`: Prove that template artifacts keep docs source facts explicit and hash-checkable.

### Linked Features
- `template-execution-contract` (prerequisite-for): Execution contract artifacts must inherit the docs trace established here.

### Slice Plan
- `docs-baseline`: Prove Exact Docs can be snapshotted and drift-checked.
- `discussion-gate`: Prove discussion decisions carry the template reference boundary.

## Exact Docs
- `workflow/architecture.md`
- `workflow/pipeline.md`

## Sync Targets
- `workflow/templates/README.md`

## Code Impact

### Existing
- `workflow/architecture.md`
- `workflow/pipeline.md`
- `workflow/templates/README.md`

### Expected
- `workflow/versions/v-template/baseline/docs.yaml`
- `workflow/versions/v-template/discussion/decisions.yaml`

### Tests
- `scripts/dev_tools/workflow_baseline.py`
- `scripts/dev_tools/discussion.py`

## Risk Boundaries
- Does not define product behavior.
- Does not write live tasks/prompts.
- Docs drift must block downstream template gates.

## Task Split
- `template-docs-contract/docs-baseline`: Validate Exact Docs baseline and drift checks for the template reference.
- `template-docs-contract/discussion-gate`: Validate discussion decisions and boundary language for the template reference.

## Queue Readiness

- Status: `ready`.
- Kind: queue-candidate review only.
- Live queue: blocked while `v1-mvp` is `live-running`.
- Promotion: explicit only; this plan does not write `tasks/prompts/**`.
