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
| `docs/governance/enterprise-workflow-baseline.md` | 1-152 | AreaMatrix 企业工作流治理基线 | create | Record applicability, G0-G8, RAID assessment dimensions, source facts, tailoring, and upgrade policy. | `authoring` |
| `docs/governance/governance-register.yaml` | 1-1634 | AM-GOV-REGISTER-001 | create | Record owners, per-file document registration, document domains, repo-wide domain ownership, core module and macOS feature correspondence, RAID probability/impact/scope, external dependencies, and capability lifecycle. | `authoring` |
| `docs/governance/project-charter.md` | 1-64 | AreaMatrix 项目章程 | create | Record mission, scope, non-goals, responsibility, cost boundary, and exit conditions. | `authoring` |
| `docs/governance/operations-lifecycle.md` | 1-67 | AreaMatrix 运行与能力生命周期 | create | Record the desktop operations model, incident loop, capability states, and retirement gates. | `authoring` |
| `docs/security/threat-model.md` | 1-82 | AreaMatrix 威胁模型 | create | Record trust boundaries, threat actors, data classification, and control mapping for the desktop product. | `authoring` |

## Middle-layer Ledger

- Middle-layer ledger: `workflow/versions/v2/middle-layer/asw-governance-adoption.yaml`
- Feature dependencies: None

### Insertions
- `AreaMatrix enterprise governance source-of-truth and workflow gates`: Map the upstream enterprise baseline into existing AreaMatrix governance without creating a parallel product source.

### Linked Features
- `v1-mvp` (preserves-history): V1 execution and release residual evidence remain read-only and are not closed by v2 governance authoring.

### Durable Residuals
- `v2-risk-001`: open independent-review governance risk.
- `v2-dep-003`: deferred promotion/live-execution authorization dependency.
- `v2-dep-004`: deferred remote CI/branch-protection dependency.
- Source: `docs/governance/governance-register.yaml`; all remain `executable_task: false`.

### Slice Plan
- `authoring`: Establish the complete adapted governance baseline, authoring boundary, adapters, checks, and v2 planning evidence.

## Exact Docs
- `docs/governance/enterprise-workflow-baseline.md`
- `docs/governance/project-charter.md`
- `docs/governance/governance-register.yaml`
- `docs/governance/operations-lifecycle.md`
- `docs/security/threat-model.md`

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
- Baseline or queue readiness must not close v2 durable residuals or treat them as executable tasks.

## Task Split
- `v2-asw-governance-adoption/authoring`: Implement and verify the approved ASW governance authoring baseline.

## Queue Readiness

- Status: `ready`.
- Kind: queue-candidate review only.
- Live queue: blocked until explicit promotion approval and live mapping are configured.
- Promotion: explicit only; this plan does not write `workflow/versions/v2/execution/**`.
