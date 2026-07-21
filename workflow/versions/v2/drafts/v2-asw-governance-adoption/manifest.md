# V2 Manifest Draft: v2-asw-governance-adoption

## v2-asw-governance-adoption/authoring

> source change: `workflow/versions/v2/changes/asw-governance-adoption.yaml`
> feature: `v2-asw-governance-adoption`
> module: `governance`
> depends: None

### Intent
- Establish the complete AreaMatrix-specific enterprise governance baseline and its enforceable authoring boundary.

### Task
- `authoring`: Implement and verify the approved ASW governance authoring baseline.

### Exact Docs
- `docs/governance/enterprise-workflow-baseline.md`
- `docs/governance/project-charter.md`
- `docs/governance/governance-register.yaml`
- `docs/governance/operations-lifecycle.md`
- `docs/security/threat-model.md`

### Sync Targets
- `CODE_REVIEW.md`
- `CONTRIBUTING.md`
- `docs/development/ci-governance.md`
- `workflow/README.md`
- `workflow/AGENTS.md`
- `.ai-governance/README.md`
- `.ai-governance/project/areamatrix-rules.md`
- `.github/PULL_REQUEST_TEMPLATE.md`

### Risk Level
- High

### Risk Boundaries
- Governance authoring only; product behavior and public contracts remain unchanged.
- Promotion apply, execution state, progress, logs, checkpoints, and runner commands remain blocked.
- External dependencies retain real blocked or deferred status.

### Validation
- ./dev workflow discuss --version v2 doctor
- ./dev workflow doctor
- ./dev workflow check-template
- ./dev check governance
- ./dev check docs
- ./dev check task-loop
- ./dev check diff
