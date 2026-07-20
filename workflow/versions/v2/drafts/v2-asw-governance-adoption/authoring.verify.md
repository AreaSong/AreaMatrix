# V2 Verify-ready Draft: v2-asw-governance-adoption/authoring

你现在进入 AreaMatrix v2 草稿任务只读验收模式。
这次是验收，不是修复：禁止修改文件，禁止边验边改。

## 验收对象
- Source change: `workflow/versions/v2/changes/asw-governance-adoption.yaml`
- Feature: `v2-asw-governance-adoption`
- Module: `governance`
- Task: `authoring` - Implement and verify the approved ASW governance authoring baseline.
- Risk: `High`

## 必须读取
- Change YAML: `workflow/versions/v2/changes/asw-governance-adoption.yaml`
- Manifest draft section: `## v2-asw-governance-adoption/authoring`
- `docs/governance/enterprise-workflow-baseline.md`
- `docs/governance/project-charter.md`
- `docs/governance/governance-register.yaml`
- `docs/governance/operations-lifecycle.md`
- `docs/security/threat-model.md`

## 验收清单
- task 实现必须能回到 Source change、Exact Docs 和 Manifest draft 逐项证明。
- docs/API/UDL sync targets 必须无漂移；如未涉及，需要说明为什么无需修改。
- 风险边界必须逐条证明未破坏。
- 不得把草稿误判为已进入 live v1 queue；不得修改 progress。
- 不能只看 diff；必须核对文档、草稿 manifest、实际文件和验证证据。

## 建议验证
- ./dev workflow discuss --version v2 doctor
- ./dev workflow doctor
- ./dev workflow check-template
- ./dev check governance
- ./dev check docs
- ./dev check task-loop
- ./dev check diff

## 输出要求
- 若通过，最后一行写：`VERIFY_RESULT: PASS`
- 若不通过，最后一行写：`VERIFY_RESULT: FAIL`，并列出阻塞项。
