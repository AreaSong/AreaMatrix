# Queue Candidate: template-execution-contract

- Version: `v-template`
- Status: `ready`
- Kind: queue-candidate
- Promotion: explicit only
- Live queue blocked: true while `v1-mvp` is `live-running`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`

## Candidate Tasks
- `template-execution-contract/queue-candidate`: Validate version-local queue candidate structure for the template reference.
- `template-execution-contract/promotion-preview`: Validate promotion preview and apply-preview safety gates for the template reference.
- `template-execution-contract/projection-closeout`: Validate projection and closeout evidence gates for the template reference.

## Promotion Notes

- Do not write `tasks/prompts/**` in this phase.
- Promotion must be a later explicit command after gates pass.
- Queue candidates can be reviewed while v1 is still running.
