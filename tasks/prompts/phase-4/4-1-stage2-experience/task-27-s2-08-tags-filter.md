# 4-1/task-27: S2-08 page atomic

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

实现 S2-08 单页或单状态接入。

## 绑定

- UX 页面：S2-08
- Core 能力：C2-02

## 核对清单

1. 只实现该页面规格。
2. 只接入绑定的主 Core 能力。
3. 不顺手实现相邻页面。

## 完成标准

- S2-08 页面可按 page spec 验收。
- 没有使用 mock 伪造真实闭环。

## 验证

```bash
./scripts/check-all.sh
```
