# Queue Candidate: template-docs-contract

- Version: `v-template`
- Status: `ready`
- Kind: queue-candidate
- Promotion: explicit only
- Live queue blocked: true while `v1-mvp` is `live-running`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`

## Candidate Tasks
- `template-docs-contract/docs-baseline`: Validate Exact Docs baseline and drift checks for the template reference.
- `template-docs-contract/discussion-gate`: Validate discussion decisions and boundary language for the template reference.

## Promotion Notes

- Do not write `tasks/prompts/**` in this phase.
- Promotion must be a later explicit command after gates pass.
- Queue candidates can be reviewed while v1 is still running.
