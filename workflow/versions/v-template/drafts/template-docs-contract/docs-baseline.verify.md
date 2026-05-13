# V-TEMPLATE Verify-ready Draft: template-docs-contract/docs-baseline

你现在进入 AreaMatrix v-template 草稿任务只读验收模式。
这次是验收，不是修复：禁止修改文件，禁止边验边改。

## 验收对象
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Feature: `template-docs-contract`
- Module: `workflow-template`
- Task: `docs-baseline` - Validate Exact Docs baseline and drift checks for the template reference.
- Risk: `Low`

## 必须读取
- Change YAML: `workflow/versions/v-template/changes/template-contracts.yaml`
- Manifest draft section: `## template-docs-contract/docs-baseline`
- `workflow/architecture.md`
- `workflow/pipeline.md`

## 验收清单
- task 实现必须能回到 Source change、Exact Docs 和 Manifest draft 逐项证明。
- docs/API/UDL sync targets 必须无漂移；如未涉及，需要说明为什么无需修改。
- 风险边界必须逐条证明未破坏。
- 不得把草稿误判为已进入 live v1 queue；不得修改 progress。
- 不能只看 diff；必须核对文档、草稿 manifest、实际文件和验证证据。

## 建议验证
- ./dev workflow baseline --version v-template doctor
- ./dev workflow doctor

## 输出要求
- 若通过，最后一行写：`VERIFY_RESULT: PASS`
- 若不通过，最后一行写：`VERIFY_RESULT: FAIL`，并列出阻塞项。
