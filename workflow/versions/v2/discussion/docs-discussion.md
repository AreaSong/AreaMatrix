# v2 Docs Discussion

## Feature Intent

- Version: `v2`
- Intent: Adopt `ASW-EWF-001@1.0.0` as the complete AreaMatrix governance baseline.
- User paths: Maintainer intake, design, implementation review, release evidence, operations, and retirement.

## Exact Docs

- `docs/governance/enterprise-workflow-baseline.md`
- `docs/governance/project-charter.md`
- `docs/governance/governance-register.yaml`
- `docs/governance/operations-lifecycle.md`
- `CODE_REVIEW.md`
- `docs/development/ci-governance.md`
- `workflow/README.md`

## Contention Points

- AreaFlow permits governance authoring but not execution cutover.
- Single-maintainer roles may be combined, while L3/L4 independent review remains mandatory.
- Desktop operations use file-safety, quality, performance, recovery, release, and support signals rather than SaaS uptime.

## Non-goals

- Do not modify `workflow/versions/v2/execution/**` beyond its generated boundary README.
- Do not modify historical `workflow/versions/v1-mvp/execution/**` or its evidence.
- Do not modify Rust Core, Swift/macOS product code, UDL, DB schema, runtime configuration, or user files.
- Do not close v1 release residuals without fresh external evidence.

## Acceptance Boundary

- All 37 ASW domains are classified as satisfied, adapted, or not applicable.
- G0-G8, source facts, owners, RAID, external dependencies, review, CI, operations, and retirement are explicit.
- Promotion remains preview-only with live mapping pending.

