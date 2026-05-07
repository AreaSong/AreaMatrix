# V-TEMPLATE Copy-ready Draft: template-execution-contract/promotion-preview

你现在进入 AreaMatrix v-template 草稿任务执行模式。

## 工作边界
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Feature: `template-execution-contract`
- Module: `workflow-template`
- Task: `promotion-preview` - Validate promotion preview and apply-preview safety gates for the template reference.
- Risk: `Low`
- 是否允许修改文件：`是，但仅限本 v-template 草稿任务直接要求的 docs/API/UDL/实现/测试；不得接入 live v1 task-loop queue`

## Exact Docs
- `workflow/pipeline.md`

## 必须同步检查
- `workflow/templates/README.md`
- `tasks/prompts/README.md`

## 风险边界
- Promotion apply write is blocked for v-template.
- Preview commands must not write tasks/prompts or progress.json.
- Closeout cannot claim done without verify pass and checkpoint evidence.

## 执行要求
- 先读取 Source change、Exact Docs、Sync Targets，再决定实现范围。
- 若涉及 Core API，必须保持 `docs/api/core-api.md` 与 `core/area_matrix.udl` 一致。
- 不得移动、删除、覆盖用户原文件；不得把 v-template 草稿直接写入 `tasks/prompts/**`。
- 完成后记录实际改动、验证命令、风险处理和未覆盖项。

## 建议验证
- ./dev workflow promote --version v-template apply --preview
