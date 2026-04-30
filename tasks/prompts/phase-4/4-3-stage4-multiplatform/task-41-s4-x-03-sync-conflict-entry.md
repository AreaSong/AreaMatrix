# 4-3/task-41: S4-X-03 page atomic

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

实现 S4-X-03 单页或单状态接入。

## 绑定

- UX 页面：S4-X-03
- Core 能力：C4-15

## 核对清单

1. 只实现该页面规格。
2. 只接入绑定的主 Core 能力。
3. 不顺手实现相邻页面。

## 完成标准

- S4-X-03 页面可按 page spec 验收。
- 没有使用 mock 伪造真实闭环。

## 验证

```bash
./scripts/check-all.sh
```
