# Workflow Plan: template-execution-contract

- Version: `v-template`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Module: `workflow-template`
- Status: `ready`
- Kind: `workflow-plan`
- Depends on: `template-docs-contract`
- Risk: `Low`

## Intent

Prove that plans, drafts, queue candidates, promotion preview, projection, and closeout remain preview-first and traceable.

## Docs Change Ledger

| File | Lines | Heading | Operation | Summary | Tasks |
|---|---:|---|---|---|---|
| `workflow/pipeline.md` | 282-386 | queue candidates | reference | Queue and promotion stages must stay preview-first until explicit promote. | `queue-candidate`, `promotion-preview` |
| `workflow/pipeline.md` | 448-496 | result projection | reference | Projection and closeout must require runtime, verify, checkpoint, and trace evidence. | `projection-closeout` |

## Middle-layer Ledger

- Middle-layer ledger: `workflow/versions/v-template/middle-layer/template-execution-contract.yaml`
- Feature dependencies: `template-docs-contract`

### Insertions
- `workflow template execution gate contract`: Prove queue, promotion preview, projection, and closeout stay traceable and preview-first.

### Linked Features
- `template-docs-contract` (depends-on): Execution artifacts must preserve the Exact Docs trace.

### Slice Plan
- `queue-candidate`: Prove version-local queue candidates trace back to drafts and plans.
- `promotion-preview`: Prove promotion preview renders live file mappings without writing them.
- `projection-closeout`: Prove projection and closeout stay evidence-based instead of task-existence-based.

## Exact Docs
- `workflow/pipeline.md`

## Sync Targets
- `workflow/templates/README.md`
- `tasks/prompts/README.md`

## Code Impact

### Existing
- `workflow/pipeline.md`
- `tasks/prompts/README.md`
- `scripts/dev_tools/workflow.py`
- `scripts/dev_tools/promotion.py`
- `scripts/dev_tools/workflow_projection.py`

### Expected
- `workflow/versions/v-template/queue/template-execution-contract/queue.yaml`
- `workflow/versions/v-template/promotion/promotion.yaml`
- `workflow/versions/v-template/projection/projection.yaml`
- `workflow/versions/v-template/closeout/closeout.yaml`

### Tests
- `scripts/dev_tools/workflow.py`
- `scripts/dev_tools/promotion.py`
- `scripts/dev_tools/workflow_projection.py`

## Risk Boundaries
- Promotion apply write is blocked for v-template.
- Preview commands must not write tasks/prompts or progress.json.
- Closeout cannot claim done without verify pass and checkpoint evidence.

## Task Split
- `template-execution-contract/queue-candidate`: Validate version-local queue candidate structure for the template reference.
- `template-execution-contract/promotion-preview`: Validate promotion preview and apply-preview safety gates for the template reference.
- `template-execution-contract/projection-closeout`: Validate projection and closeout evidence gates for the template reference.

## Queue Readiness

- Status: `ready`.
- Kind: queue-candidate review only.
- Live queue: blocked while `v1-mvp` is `live-running`.
- Promotion: explicit only; this plan does not write `tasks/prompts/**`.
