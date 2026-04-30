# 4-1/task-105: S2-06 page integration verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

验收 S2-06 smart-lists 的整页多功能闭环。

## 绑定

- UX 页面：S2-06 smart-lists
- 页面能力：C2-03 saved-search-crud, C2-04 smart-lists
- 页面功能任务：4-1/task-103, 4-1/task-104
- 阶段：Stage 2 Experience

## 核对清单

1. 逐项验收本页所有 page-feature task 是否完成。
2. 检查页面状态、入口、退出、错误态和 CoreBridge 调用是否能串成完整页面闭环。
3. 移除本页无法通过最终验收的 mock、fixture 或硬编码状态。
4. 不新增本页未在 control map 中声明的功能。

## 完成标准

- S2-06 页面可以按 page spec 和 control map 完整验收。
- 页面声明的所有 Core 能力都已真实接入或有明确阻塞证据。

## 验证

```bash
./scripts/check-all.sh
```
