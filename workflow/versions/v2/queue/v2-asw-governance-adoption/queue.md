# Queue Candidate: v2-asw-governance-adoption

- Version: `v2`
- Status: `ready`
- Kind: queue-candidate
- Promotion: explicit only
- Live queue blocked: true until explicit promotion approval and live mapping are configured
- Source change: `workflow/versions/v2/changes/asw-governance-adoption.yaml`

## Candidate Tasks
- `v2-asw-governance-adoption/authoring`: Implement and verify the approved ASW governance authoring baseline.

## Promotion Notes

- Do not write `workflow/versions/v2/execution/**` from this queue candidate.
- Promotion must be a later explicit command after gates pass.
- Queue candidates can be reviewed as template-only preview artifacts; promotion still requires explicit approval and live mapping.
