# Workflow Plan: v2-asw-governance-adoption

- Version: `v2`
- Source change: `workflow/versions/v2/changes/asw-governance-adoption.yaml`
- Module: `governance`
- Status: `ready`
- Kind: `workflow-plan`
- Depends on: None
- Risk: `High`

## Intent

Establish the complete AreaMatrix-specific enterprise governance baseline and its enforceable authoring boundary.

## Docs Change Ledger

| File | Lines | Heading | Operation | Summary | Tasks |
|---|---:|---|---|---|---|
| `docs/governance/enterprise-workflow-baseline.md` | 1-122 | AreaMatrix 企业工作流治理基线 | create | Record applicability, G0-G8, source facts, tailoring, and upgrade policy. | `authoring` |
| `docs/governance/governance-register.yaml` | 1-119 | AM-GOV-REGISTER-001 | create | Record owners, document metadata, RAID, external dependencies, and capability lifecycle. | `authoring` |

## Middle-layer Ledger

- Middle-layer ledger: `workflow/versions/v2/middle-layer/asw-governance-adoption.yaml`
- Feature dependencies: None

### Insertions
- `AreaMatrix enterprise governance source-of-truth and workflow gates`: Map the upstream enterprise baseline into existing AreaMatrix governance without creating a parallel product source.

### Linked Features
- `v1-mvp` (preserves-history): V1 execution and release residual evidence remain read-only and are not closed by v2 governance authoring.

### Slice Plan
- `authoring`: Establish the complete adapted governance baseline, authoring boundary, adapters, checks, and v2 planning evidence.

## Exact Docs
- `docs/governance/enterprise-workflow-baseline.md`
- `docs/governance/project-charter.md`
- `docs/governance/governance-register.yaml`
- `docs/governance/operations-lifecycle.md`

## Sync Targets
- `CODE_REVIEW.md`
- `CONTRIBUTING.md`
- `docs/development/ci-governance.md`
- `workflow/README.md`
- `workflow/AGENTS.md`
- `.ai-governance/README.md`
- `.ai-governance/project/areamatrix-rules.md`
- `.github/PULL_REQUEST_TEMPLATE.md`

## Code Impact

### Existing
- `scripts/areaflow_shim.py`
- `scripts/dev_tools/checks.py`

### Expected
- `docs/governance/**`
- `workflow/versions/v2/**`

### Tests
- `scripts/dev_tools/test_build_tools.py`
- `scripts/task_loop/self_check.py`

## Risk Boundaries
- Governance authoring only; product behavior and public contracts remain unchanged.
- Promotion apply, execution state, progress, logs, checkpoints, and runner commands remain blocked.
- External dependencies retain real blocked or deferred status.

## Task Split
- `v2-asw-governance-adoption/authoring`: Implement and verify the approved ASW governance authoring baseline.

## Queue Readiness

- Status: `ready`.
- Kind: queue-candidate review only.
- Live queue: blocked until explicit promotion approval and live mapping are configured.
- Promotion: explicit only; this plan does not write `workflow/versions/v2/execution/**`.
