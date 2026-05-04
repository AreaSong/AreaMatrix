# 3-1/task-05: stage1 integration verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

Stage 1 MVP 全量 integration verify（集成验收）。本任务是最终只读发布门禁：发现产品缺口时判定不通过，并回退到 Phase 1/2 对应任务修复；不得在本任务中补主功能。

## 绑定

- 阶段级最终验收任务；读取全部 Stage 1 MVP 相关 UX/Core/发布文档。
- 不绑定单个 UX 页面或 Core 能力，因为本任务验收的是 Phase 1 Core 与 Phase 2 UI 的整体闭环。

## 核对清单

1. 读取 Stage 1 MVP roadmap、MVP control map、Core capability index、UX page-spec index、testing 和 release 文档。
2. 按 control map 全量核对每个 Real Core 页面是否接真实 Core，不得用 mock、fixture、硬编码状态或静态占位通过。
3. 核对 Phase 1 Core 能力与 Phase 2 UI 页面是否都已完成各自 integration verify，尤其是 import、recovery、sync、iCloud、DB repair、file actions。
4. 核对 `3-1/task-01` 到 `3-1/task-04` 的 error recovery、recovery scenarios、performance 和 release checklist 证据。
5. 运行最终自动化综合门禁，并记录手工冒烟、性能基线、release checklist、签名/公证、DMG 干净机首启状态。
6. 若发现产品功能缺口、链路未打通、真实闭环仍用 mock、验证缺失或 P0/P1 风险，判定本任务不通过。
7. 不修改 `core/src/**`、`core/area_matrix.udl`、`apps/macos/AreaMatrix/**` 或 Xcode project；本任务不得补产品实现。

## 完成标准

- Stage 1 MVP roadmap、control map、Core specs、UX specs、release/testing 文档之间完成交叉验收。
- `./dev check all` 通过，且手工冒烟、性能基线、release checklist 均有明确通过证据。
- 所有 P0/P1 已关闭、阻断或明确不放行；没有“功能任务完成但整体不可发布”的未记录风险。
- 未触碰 Forbidden Touches；如发现必须修改产品实现的问题，本任务应停止并回退到 Phase 1/2。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./dev check all
git diff --check
```
