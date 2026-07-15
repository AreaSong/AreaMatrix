# V2 Copy-ready Draft: v2-asw-governance-adoption/authoring

你现在进入 AreaMatrix v2 草稿任务执行模式。

## 工作边界
- Source change: `workflow/versions/v2/changes/asw-governance-adoption.yaml`
- Feature: `v2-asw-governance-adoption`
- Module: `governance`
- Task: `authoring` - Implement and verify the approved ASW governance authoring baseline.
- Risk: `High`
- 是否允许修改文件：`是，但仅限本 v2 草稿任务直接要求的 docs/API/UDL/实现/测试；不得接入 live v1 task-loop queue`

## Exact Docs
- `docs/governance/enterprise-workflow-baseline.md`
- `docs/governance/project-charter.md`
- `docs/governance/governance-register.yaml`
- `docs/governance/operations-lifecycle.md`

## 必须同步检查
- `CODE_REVIEW.md`
- `CONTRIBUTING.md`
- `docs/development/ci-governance.md`
- `workflow/README.md`
- `workflow/AGENTS.md`
- `.ai-governance/README.md`
- `.ai-governance/project/areamatrix-rules.md`
- `.github/PULL_REQUEST_TEMPLATE.md`

## 风险边界
- Governance authoring only; product behavior and public contracts remain unchanged.
- Promotion apply, execution state, progress, logs, checkpoints, and runner commands remain blocked.
- External dependencies retain real blocked or deferred status.

## 执行要求
- 先读取 Source change、Exact Docs、Sync Targets，再决定实现范围。
- 若涉及 Core API，必须保持 `docs/api/core-api.md` 与 `core/area_matrix.udl` 一致。
- 不得移动、删除、覆盖用户原文件；不得把 v2 草稿直接写入 `workflow/versions/v2/execution/**`。
- 完成后记录实际改动、验证命令、风险处理和未覆盖项。

## 建议验证
- ./dev workflow discuss --version v2 doctor
- ./dev workflow doctor
- ./dev workflow check-template
- ./dev check governance
- ./dev check docs
- ./dev check task-loop
- ./dev check diff
