# 4-1/task-143: stage-2-experience integration verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

验收 Stage 2 Experience 的 Core 能力、页面功能任务和阶段闭环。

## 绑定

- Core 能力数量：19
- UX 页面数量：23
- 阶段：Stage 2 Experience

## 核对清单

1. 检查本阶段全部 Core integration verify 已完成。
2. 检查本阶段全部 page-feature task 和 page integration verify 已完成。
3. 运行 `audit --pages`，确认本阶段页面能力覆盖为 OK。
4. 不新增本阶段 control map 之外的页面、能力或产品代码。

## 完成标准

- Stage 2 Experience 可以按 control map 完整验收。
- 所有失败项有明确证据、阻塞项和后续任务。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
python3 tasks/prompts/_shared/prompt_pipeline.py audit --pages
./scripts/check-all.sh
```
